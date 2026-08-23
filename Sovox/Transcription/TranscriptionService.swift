import Foundation

/// Progress is reported through Sendable main actor closures rather than a
/// stored object reference. An actor cannot hold a MainActor isolated object and
/// send it back across the boundary under Swift 6 strict concurrency, and the
/// closures keep the service testable without knowing who consumes it.
typealias TranscriptionStateHandler = @Sendable @MainActor (String, Int, SegmentState) -> Void
typealias TranscriptionTextHandler = @Sendable @MainActor (String, Int, String) -> Void
typealias TranscriptionDrainHandler = @Sendable @MainActor (String) -> Void
/// Duration read off the file itself, for segments the app adopted from disk
/// after a force quit and therefore never timed.
typealias TranscriptionMeasureHandler = @Sendable @MainActor (String, Int, TimeInterval) -> Void

/// The transcription pipeline.
///
/// Owned by the app for its whole lifetime, never by a view, a view model or a
/// task tied to scene lifecycle, so backgrounding, dismissing the recording
/// screen and switching tabs cannot cancel work in flight.
///
/// Strictly serial. Exactly one segment is transcribed at a time. Two at once on
/// a long recording spikes memory and thermals and can glitch the audio path,
/// which is the one thing that must never happen: recording is a real time I/O
/// path, transcription is compute over a file that is already closed, and the
/// audio thread always wins.
actor TranscriptionService {
    static let shared = TranscriptionService()

    struct Job: Sendable, Equatable {
        let sessionID: String
        let index: Int
        let fileURL: URL
        let expectedDuration: TimeInterval
        var localeIdentifier: String = TranscriptionLocale.defaultIdentifier

        var key: String { "\(sessionID)#\(index)" }
    }

    private var pending: [Job] = []
    private var activeKey: String?
    private var worker: Task<Void, Never>?
    private var onState: TranscriptionStateHandler?
    private var onText: TranscriptionTextHandler?
    private var onDrained: TranscriptionDrainHandler?
    private var onMeasure: TranscriptionMeasureHandler?
    private var thermalObserver: NSObjectProtocol?
    private var isDeferred = false

    private init() {}

    // MARK: Wiring

    func attach(onState: @escaping TranscriptionStateHandler,
                onText: @escaping TranscriptionTextHandler,
                onDrained: @escaping TranscriptionDrainHandler,
                onMeasure: TranscriptionMeasureHandler? = nil) {
        self.onState = onState
        self.onText = onText
        self.onDrained = onDrained
        self.onMeasure = onMeasure
        startThermalObservation()
    }

    // MARK: Enqueue

    func enqueue(_ job: Job) {
        guard activeKey != job.key else { return }
        guard !pending.contains(where: { $0.key == job.key }) else { return }
        pending.append(job)
        notify(job, .pending)
        startWorkerIfNeeded()
    }

    func enqueue(_ jobs: [Job]) {
        for job in jobs { enqueue(job) }
    }

    /// Retry is just a re enqueue. Kept as its own entry point so the intent is
    /// legible at the call sites in the UI.
    func retry(_ job: Job) {
        enqueue(job)
    }

    func queueDepth() -> Int {
        pending.count + (activeKey == nil ? 0 : 1)
    }

    func isThermallyDeferred() -> Bool { isDeferred }

    // MARK: Worker

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        // .utility, never .userInitiated. The audio thread must always win.
        worker = Task(priority: .utility) { [weak self] in
            await self?.drain()
            await self?.clearWorker()
        }
    }

    private func clearWorker() {
        worker = nil
        if !pending.isEmpty { startWorkerIfNeeded() }
    }

    private func drain() async {
        while !pending.isEmpty {
            if Task.isCancelled { return }

            if thermalStateBlocksWork() {
                await deferForThermal()
                continue
            }
            markResumedIfNeeded()

            let job = pending.removeFirst()
            activeKey = job.key
            notify(job, .running)

            do {
                // Measured BEFORE verification, deliberately. A file killed
                // mid write fails verification, and if the duration were only
                // taken afterwards the session would keep the zero it was
                // created with, which is indistinguishable from a stray tap.
                if job.expectedDuration <= 0 {
                    let measured = await SegmentFinalisation.duration(of: job.fileURL)
                    if measured > 0 { await measure(job, seconds: measured) }
                }
                try await SegmentFinalisation.verify(url: job.fileURL)
                let text = try await SegmentTranscriber.shared.transcribe(
                    fileURL: job.fileURL,
                    expectedDuration: job.expectedDuration,
                    localeIdentifier: job.localeIdentifier
                )
                // Persisted immediately, keyed by segment. Never held only in
                // memory, so a jetsam between segments cannot lose work.
                await deliver(job, text: text)
                // Phase 18a. Recognition succeeding and hearing nothing is a
                // third outcome, not a failure. Conflating them is what put
                // "could not be transcribed" under recordings where nobody
                // spoke.
                let heardSomething = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                notify(job, heardSomething ? .done : .empty)
            } catch {
                // No try? anywhere in this pipeline. Every thrown error is
                // captured, stored with the segment and displayed.
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                notify(job, .failed(reason: reason))
            }

            activeKey = nil
            if !pending.contains(where: { $0.sessionID == job.sessionID }) {
                await drained(job.sessionID)
            }
        }
    }

    // MARK: Thermal guard

    private func thermalStateBlocksWork() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    /// Defers transcription only. Recording is never paused for thermal reasons.
    private func deferForThermal() async {
        if !isDeferred {
            isDeferred = true
            let reason = "Device is warm, transcription resumes when it cools"
            for job in pending { notify(job, .deferred(reason: reason)) }
        }
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
            // Cancellation is the only thing Task.sleep throws here. Returning
            // lets drain() see isCancelled and unwind.
            return
        }
    }

    private func markResumedIfNeeded() {
        guard isDeferred else { return }
        isDeferred = false
        for job in pending { notify(job, .pending) }
    }

    private func startThermalObservation() {
        guard thermalObserver == nil else { return }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { await TranscriptionService.shared.thermalStateChanged() }
        }
    }

    private func thermalStateChanged() {
        // Waking the worker is enough. drain() re-evaluates the state each pass.
        startWorkerIfNeeded()
    }

    // MARK: Reporting

    private func notify(_ job: Job, _ state: SegmentState) {
        guard let onState else { return }
        let sessionID = job.sessionID
        let index = job.index
        Task { @MainActor in onState(sessionID, index, state) }
    }

    private func deliver(_ job: Job, text: String) async {
        guard let onText else { return }
        let sessionID = job.sessionID
        let index = job.index
        await MainActor.run { onText(sessionID, index, text) }
    }

    private func measure(_ job: Job, seconds: TimeInterval) async {
        guard let handler = onMeasure else { return }
        await MainActor.run { handler(job.sessionID, job.index, seconds) }
    }

    private func drained(_ sessionID: String) async {
        guard let onDrained else { return }
        await MainActor.run { onDrained(sessionID) }
    }
}
