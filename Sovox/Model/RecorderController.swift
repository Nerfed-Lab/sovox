import Foundation
import AVFoundation
import Observation
import UIKit

enum RecorderState: String, Equatable, Sendable {
    case idle
    case recording
    case paused
    case transcribing
    case ready
}

/// Orchestrates the engine, the store, the Live Activity and the transcription
/// queue. This is the object the App Intents reach through SovoxCommands.
@MainActor
@Observable
final class RecorderController: SovoxCommandHandler {
    static let shared = RecorderController()

    private(set) var state: RecorderState = .idle
    private(set) var clock = ElapsedClock()
    private(set) var level: Float = 0
    private(set) var segmentIndex = 1
    private(set) var nextRollDate: Date?
    private(set) var currentSession: RecordingSession?
    private(set) var remainingMinutes: Int = 0

    var alertMessage: String?
    /// Surfaced in the recording detail view so a failure is never silent.
    private(set) var lastTranscriptionFailure: String?
    var liveActivityNotice: String?
    /// Set when transcription finished while the app was in the background.
    /// iOS refuses to open another app from the background, so the hand off is
    /// deferred until the user brings Sovox forward.
    private(set) var pendingHandoffSessionID: String?

    private let engine = AudioCaptureEngine()
    private let activities = LiveActivityController()
    private let store = RecordingStore.shared
    private let settings = AppSettings.shared

    private var isForeground = true
    /// Distinguishes a pause the user asked for from one the system imposed.
    /// An interruption that ends with shouldResume must not undo a user pause.
    private var userPaused = false
    /// Sticky for the life of the session. It used to be a defaulted parameter
    /// on activityState, so the very next push from any other cause silently
    /// cleared the low storage warning off the Lock Screen.
    private var lowStorageActive = false

    private init() {}

    // MARK: Registration

    func bootstrap() {
        SovoxCommands.handler = self
        Task {
            await TranscriptionService.shared.attach(
                onState: { [weak self] sessionID, index, state in
                    self?.transcriptionStateChanged(sessionID: sessionID, index: index, state: state)
                },
                onText: { [weak self] sessionID, index, text in
                    self?.transcriptionProduced(sessionID: sessionID, index: index, text: text)
                },
                onDrained: { [weak self] sessionID in
                    self?.transcriptionQueueDrained(sessionID: sessionID)
                }
            )
        }
        activities.endStaleActivities()
        engine.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        refreshRemainingMinutes()
        resumeUnfinishedTranscriptions()
    }

    /// Leaves the last known figure in place when the volume cannot be read,
    /// rather than reporting zero minutes left.
    private func refreshRemainingMinutes() {
        guard let free = StorageGuard.freeBytes(at: RecordingPaths.documents) else { return }
        remainingMinutes = StorageGuard.recordableMinutes(freeBytes: free)
    }

    func setForeground(_ value: Bool) {
        isForeground = value
    }

    var isRecordingNow: Bool { state == .recording || state == .paused }

    // MARK: Permissions

    func microphoneGranted() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicrophone() async -> Bool {
        if microphoneGranted() { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: Transport

    @discardableResult
    func start() async -> Bool {
        guard state == .idle || state == .ready else { return false }
        // The smoke test drives a second engine against the same process wide
        // audio session. A disabled button is a rendering hint, not a guard, and
        // a start can arrive from Siri, a Shortcut or the Control Centre control.
        guard !SelfTest.smokeInProgress else {
            alertMessage = "The 60 second smoke test is running. Wait for it to finish, then record."
            return false
        }

        guard await requestMicrophone() else {
            alertMessage = "Sovox needs the microphone. Open Settings, Sovox and switch Microphone on."
            return false
        }
        _ = await SegmentTranscriber.requestAuthorisation()
        _ = await Notifier.requestAuthorisation()

        // Unknown free space allows the start. Refusing on a failed probe would
        // block the one thing the app exists to do, and the write path already
        // fails loudly on a disk that is actually full.
        if let free = StorageGuard.freeBytes(at: RecordingPaths.documents),
           !StorageGuard.canStart(freeBytes: free) {
            alertMessage = "Only \(StorageGuard.formatted(bytes: free)) free. Sovox needs at least 1 GB before it will start a recording."
            return false
        }

        let now = Date()
        let id = RecordingPaths.uniqueSessionID(for: now)
        var session = RecordingSession(id: id, startDate: now)
        session.isComplete = false
        session.localeIdentifier = settings.transcriptionLocale

        do {
            try engine.start(sessionID: id, segmentSeconds: settings.segmentSeconds)
        } catch {
            alertMessage = error.localizedDescription
            return false
        }

        clock = ElapsedClock(startDate: now)
        userPaused = false
        lowStorageActive = false
        segmentIndex = 1
        nextRollDate = now.addingTimeInterval(settings.segmentSeconds)
        currentSession = session
        refreshRemainingMinutes()
        state = .recording
        settings.sessionsStarted += 1
        store.upsert(session)

        do {
            try activities.start(sessionID: id, state: activityState(), segmentSeconds: settings.segmentSeconds)
            liveActivityNotice = nil
        } catch {
            liveActivityNotice = error.localizedDescription
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard state == .recording || state == .paused else { return false }

        let closing = engine.stop()
        userPaused = false
        clock.resume()
        var session = currentSession ?? RecordingSession(id: RecordingPaths.uniqueSessionID(for: clock.startDate), startDate: clock.startDate)
        session.duration = clock.elapsed()
        session.isComplete = true

        if let closing, !session.segments.contains(where: { $0.index == closing.index }) {
            session.segments.append(SegmentRecord(index: closing.index,
                                                  fileName: closing.fileName,
                                                  duration: closing.duration,
                                                  state: .pending,
                                                  text: ""))
        }
        session.segments.sort { $0.index < $1.index }
        currentSession = session
        store.upsert(session)

        activities.end(finalState: activityState())
        state = session.segments.isEmpty ? .idle : .transcribing
        level = 0

        if let closing {
            enqueueTranscription(sessionID: session.id, index: closing.index, duration: closing.duration)
        }
        enqueuePendingSegments(sessionID: session.id)
        return true
    }

    func pause() {
        guard state == .recording else { return }
        userPaused = true
        engine.pause()
        clock.pause()
        state = .paused
        activities.update(activityState(), segmentSeconds: settings.segmentSeconds)
    }

    func resume() {
        guard state == .paused else { return }
        do {
            try engine.resume()
            userPaused = false
            clock.resume()
            state = .recording
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: Command handler

    func commandStart() async -> SovoxCommandResult {
        if isRecordingNow { return .alreadyRunning }
        return await start() ? .started : .startFailed
    }

    func commandStop() async -> SovoxCommandResult {
        guard isRecordingNow else { return .notRunning }
        // Returns as soon as the files are closed. Transcription runs on a
        // detached chain and is never awaited here, so the intent cannot stall.
        return stop() ? .stopped : .notRunning
    }

    func commandPause() async -> SovoxCommandResult {
        guard state == .recording else { return .notRunning }
        pause()
        return .paused
    }

    func commandResume() async -> SovoxCommandResult {
        guard state == .paused else { return .notRunning }
        resume()
        return .resumed
    }

    func commandToggle() async -> SovoxCommandResult {
        if isRecordingNow { return await commandStop() }
        return await commandStart()
    }

    // MARK: Engine events

    private func handle(_ event: SovoxEngineEvent) {
        switch event {
        case .level(let value):
            level = value

        case .segmentOpened(let index, let rollsAt):
            segmentIndex = index
            nextRollDate = rollsAt
            // Keeps the Lock Screen figure tracking the session rather than the
            // value read once at launch.
            refreshRemainingMinutes()
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)

        case .segmentClosed(let index, let fileName, let duration):
            guard var session = currentSession else { return }
            if let existing = session.segments.firstIndex(where: { $0.index == index }) {
                session.segments[existing].duration = duration
            } else {
                session.segments.append(SegmentRecord(index: index,
                                                      fileName: fileName,
                                                      duration: duration,
                                                      state: .pending,
                                                      text: ""))
            }
            session.segments.sort { $0.index < $1.index }
            session.duration = clock.elapsed()
            currentSession = session
            store.upsert(session)
            if state == .recording || state == .paused {
                enqueueTranscription(sessionID: session.id, index: index, duration: duration)
            }

        case .interruptionBegan:
            clock.pause()
            state = .paused
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)

        case .interruptionEnded(let resumed):
            // Nothing to push when the state did not change. An update with no
            // discrete change is pure budget spend.
            guard resumed, !userPaused else { return }
            clock.resume()
            state = .recording
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)

        case .routeReconfigured:
            break

        case .mediaServicesReset:
            liveActivityNotice = "Audio services restarted. Recording continued on a new segment."

        case .lowStorage(let minutes):
            remainingMinutes = minutes
            lowStorageActive = true
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)
            Notifier.post(title: "Sovox", body: "Storage is running low. About \(minutes) minutes of recording left.")

        case .storageRecovered:
            guard lowStorageActive else { return }
            lowStorageActive = false
            refreshRemainingMinutes()
            activities.update(activityState(), segmentSeconds: settings.segmentSeconds)

        case .storageCritical:
            stop()
            Notifier.post(title: "Sovox stopped", body: "Free space fell below 300 MB. Everything recorded so far has been saved.")
            alertMessage = "Recording stopped because free space fell below 300 MB. Every finished segment was saved."

        case .fatal(let message):
            // The engine cannot be brought back. Stop cleanly rather than leave
            // a recording that looks live and is writing nothing.
            stop()
            Notifier.post(title: "Sovox stopped", body: message)
            alertMessage = message

        case .failed(let message):
            alertMessage = message
            // alertMessage only reaches the user on screen. During a locked
            // three hour meeting that is nobody, so a failure would be silent
            // until they came back to a dead recording.
            if !isForeground {
                Notifier.post(title: "Sovox needs attention", body: message)
            }
        }
    }

    // MARK: Live Activity state

    private func activityState() -> SovoxAttributes.ContentState {
        SovoxAttributes.ContentState.from(clock: clock,
                                            segmentIndex: segmentIndex,
                                            nextRollDate: nextRollDate,
                                            remainingMinutes: remainingMinutes,
                                            lowStorage: lowStorageActive)
    }

    // MARK: Transcription

    /// Everything below hands off to TranscriptionService, a long lived actor.
    /// The controller only translates events into persisted state. It owns no
    /// task that could be cancelled by a view going away.

    func enqueueTranscription(sessionID: String, index: Int, duration: TimeInterval) {
        guard let session = store.session(id: sessionID),
              let record = session.segments.first(where: { $0.index == index }) else { return }
        let job = TranscriptionService.Job(sessionID: sessionID,
                                           index: index,
                                           fileURL: session.directory.appendingPathComponent(record.fileName),
                                           expectedDuration: duration,
                                           localeIdentifier: TranscriptionLocale.resolved(session.localeIdentifier))
        Task { await TranscriptionService.shared.enqueue(job) }
    }

    private func enqueueSegments(of sessionID: String, where include: @escaping (SegmentRecord) -> Bool) {
        guard let session = store.session(id: sessionID) else { return }
        let jobs = session.segments.filter(include).map { record in
            TranscriptionService.Job(sessionID: sessionID,
                                     index: record.index,
                                     fileURL: session.directory.appendingPathComponent(record.fileName),
                                     expectedDuration: record.duration,
                                     localeIdentifier: TranscriptionLocale.resolved(session.localeIdentifier))
        }
        guard !jobs.isEmpty else { return }
        Task { await TranscriptionService.shared.enqueue(jobs) }
    }

    private func enqueuePendingSegments(sessionID: String) {
        enqueueSegments(of: sessionID) { !$0.state.isTerminal || $0.state.isFailure }
    }

    /// Anything left behind by a force quit is, by definition, over. Mark it
    /// complete so the transcript is stitched and the ready notification fires.
    func resumeUnfinishedTranscriptions() {
        for var session in store.unfinished {
            if !session.isComplete {
                session.isComplete = true
                session.duration = session.segments.reduce(0) { $0 + $1.duration }
                store.upsert(session)
            }
            enqueueSegments(of: session.id) { $0.state != .done }
        }
    }

    func retrySegment(sessionID: String, index: Int) {
        enqueueSegments(of: sessionID) { $0.index == index }
    }

    func retryAllFailed(sessionID: String) {
        enqueueSegments(of: sessionID) { $0.state.isFailure }
    }


    private func finishTranscription(sessionID: String) {
        guard var session = store.session(id: sessionID), session.isComplete else {
            // The session was deleted, or never completed. Leaving the UI parked
            // on the transcribing screen with no escape is worse than idling.
            if currentSession?.id == sessionID { returnToIdle() }
            return
        }
        session.transcript = session.stitchedTranscript
        store.upsert(session)
        if currentSession?.id == sessionID {
            currentSession = session
            state = .ready
        }
        Notifier.post(title: "Transcript ready",
                      body: "\(DurationFormat.compact(session.duration)) captured. Open Sovox to generate your notes.")
        if !isForeground {
            pendingHandoffSessionID = sessionID
        }
    }


    /// Leaves the transcribing screen without cancelling the work. The chain
    /// keeps running and the ready notification still fires, and the session is
    /// in History either way.
    func dismissTranscribingScreen() {
        guard state == .transcribing else { return }
        returnToIdle()
    }

    /// Applies a segment length change to a recording already in progress.
    /// Without this the Settings picker was inert until the next recording, and
    /// the Live Activity kept advertising a roll time from the old interval.
    func applySegmentLength() {
        guard isRecordingNow else { return }
        engine.updateSegmentSeconds(settings.segmentSeconds)
        nextRollDate = engine.currentSegmentRollDate
        activities.update(activityState(), segmentSeconds: settings.segmentSeconds)
    }

    func clearPendingHandoff() {
        pendingHandoffSessionID = nil
    }

    func returnToIdle() {
        state = .idle
        currentSession = nil
        level = 0
    }

    var transcriptionProgress: Double {
        currentSession?.transcriptionProgress ?? 0
    }
}

// MARK: - Transcription callbacks

extension RecorderController {

    func transcriptionStateChanged(sessionID: String, index: Int, state: SegmentState) {
        guard var session = store.session(id: sessionID),
              let slot = session.segments.firstIndex(where: { $0.index == index }) else { return }
        session.segments[slot].state = state
        store.upsert(session)
        if currentSession?.id == sessionID { currentSession = session }
        if case .failed(let reason) = state {
            lastTranscriptionFailure = "Segment \(index): \(reason)"
        }
    }

    func transcriptionProduced(sessionID: String, index: Int, text: String) {
        guard var session = store.session(id: sessionID),
              let slot = session.segments.firstIndex(where: { $0.index == index }) else { return }
        session.segments[slot].text = text
        session.transcript = session.stitchedTranscript
        store.upsert(session)
        if currentSession?.id == sessionID { currentSession = session }
    }

    func transcriptionQueueDrained(sessionID: String) {
        finishTranscription(sessionID: sessionID)
    }
}
