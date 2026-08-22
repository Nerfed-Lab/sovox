@preconcurrency import AVFoundation
import Foundation

/// Hands exactly one buffer to AVAudioConverter and then reports no more data.
/// A lock backed box rather than a captured var, because the converter input
/// block is a concurrently executing closure.
private final class ConverterFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let value = buffer
        buffer = nil
        return value
    }
}

enum SovoxEngineEvent: Sendable {
    case segmentOpened(index: Int, rollsAt: Date)
    case segmentClosed(index: Int, fileName: String, duration: TimeInterval)
    case level(Float)
    case interruptionBegan
    case interruptionEnded(resumed: Bool)
    case routeReconfigured
    case mediaServicesReset
    case lowStorage(remainingMinutes: Int)
    case storageRecovered
    case storageCritical
    /// Audio could not be rebuilt. The controller stops cleanly rather than
    /// leaving a recording that looks live and is writing nothing.
    case fatal(String)
    case failed(String)
}

enum SovoxEngineError: LocalizedError {
    case sessionUnavailable(String)
    case sessionActivation(String)
    case noInputFormat
    case cannotCreateFile(String)
    case converterUnavailable
    case engineStart(String)

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable(let m): return "Could not configure the audio session. \(m)"
        case .sessionActivation(let m): return "Could not activate the audio session. Another app may be using the microphone. \(m)"
        case .noInputFormat: return "The microphone reported no usable input format."
        case .cannotCreateFile(let m): return "Could not create the recording file. \(m)"
        case .converterUnavailable: return "Could not build an audio converter for this microphone."
        case .engineStart(let m): return "The audio engine refused to start. \(m)"
        }
    }
}

/// AVAudioEngine based recorder.
///
/// AVAudioRecorder is deliberately not used. Rolling to a new file with
/// AVAudioRecorder means stopping the recorder, which drops audio across the
/// boundary. With an engine tap the next AVAudioFile is opened and installed as
/// the write target before the previous one is released, so no buffer is lost.
///
/// Format handling: the tap must be installed with inputNode.outputFormat(forBus: 0),
/// which on device is typically 48 kHz float. The destination AVAudioFile is
/// declared with AAC settings, and an AVAudioFile always exposes a PCM
/// processingFormat. Writing the raw tap buffer straight in would be a format
/// mismatch, so every buffer goes through a single long lived AVAudioConverter
/// that resamples the hardware format into the file's processingFormat
/// (44.1 kHz mono float32). The file's own encoder then performs the AAC
/// compression on write. This is preferred over writing CAF and transcoding at
/// segment close because it keeps peak disk use at one copy and finishes the
/// segment the instant it rolls, which is what lets transcription start early.
///
/// Threading: ioQueue is the only queue that ever touches an AVAudioFile. The
/// tap callback enters it with sync, which is safe here because a tap block is
/// delivered on a normal priority audio thread and not on the real time render
/// thread.
final class AudioCaptureEngine: NSObject, @unchecked Sendable {

    // Set once before start, read from any thread afterwards.
    var onEvent: (@Sendable (SovoxEngineEvent) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.sovox.audio.io", qos: .userInitiated)
    private var engine = AVAudioEngine()

    // ioQueue owned state.
    private var currentFile: AVAudioFile?
    private var segmentIndex = 1
    private var segmentStartDate = Date()
    private var segmentFrames: AVAudioFramePosition = 0
    private var lastStorageCheck = Date.distantPast
    private var lowStorageAnnounced = false

    // Configured at start, read on the tap thread.
    private var sessionID = ""
    private var segmentSeconds: TimeInterval = 1800
    private var fileSettings: [String: Any] = [:]
    private var fileProcessingFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?

    private var isRunning = false
    private var isPausedForInterruption = false
    /// False whenever the AVAudioEngine instance has been replaced, which is the
    /// state a media services reset leaves behind. Restarting such an engine
    /// with prepare and start alone yields a running engine with no tap, and a
    /// recording that writes nothing.
    private var tapInstalled = false

    /// True between pause() and resume(). Lock backed as cheap insurance: every
    /// writer now runs on the main queue, but a stale read here would re-arm a
    /// microphone the user believes is off, so it is not left to convention.
    private let stateLock = NSLock()
    private var _pausedByUser = false
    private var pausedByUser: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _pausedByUser }
        set { stateLock.lock(); _pausedByUser = newValue; stateLock.unlock() }
    }
    private var lastLevelEmit = Date.distantPast

    private let targetSampleRate: Double = 44_100
    private let targetChannels: AVAudioChannelCount = 1
    private let targetBitRate = 64_000

    // MARK: Lifecycle

    /// Order matters. Category and activation happen before prepare and start.
    /// Starting the engine against an inactive session yields a running engine
    /// that produces silence.
    func start(sessionID: String, segmentSeconds: TimeInterval) throws {
        self.sessionID = sessionID
        self.segmentSeconds = segmentSeconds

        try configureSession()
        registerObservers()

        fileSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannels),
            AVEncoderBitRateKey: targetBitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        RecordingPaths.ensureDirectory(RecordingPaths.sessionDirectory(sessionID))

        try ioQueueSyncThrowing {
            self.segmentIndex = 1
            self.segmentStartDate = Date()
            self.segmentFrames = 0
            self.lowStorageAnnounced = false
            self.lastStorageCheck = Date()
            try self.openFile(index: 1)
        }

        try startEngineAndTap()
        isRunning = true
        resetPauseFlags()
        emit(.segmentOpened(index: 1, rollsAt: Date().addingTimeInterval(segmentSeconds)))
    }

    /// Finalises the open segment and hands its identity back to the caller.
    @discardableResult
    func stop() -> (index: Int, fileName: String, duration: TimeInterval)? {
        guard isRunning else { return nil }
        isRunning = false
        resetPauseFlags()

        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        engine.stop()
        unregisterObservers()

        var closed: (Int, String, TimeInterval)?
        ioQueue.sync {
            if self.currentFile != nil {
                let duration = Date().timeIntervalSince(self.segmentStartDate)
                closed = (self.segmentIndex, RecordingPaths.segmentFileName(self.segmentIndex), duration)
            }
            // Releasing the handle is what flushes and closes the AAC file.
            self.currentFile = nil
        }

        deactivateSession()
        if let closed {
            emit(.segmentClosed(index: closed.0, fileName: closed.1, duration: closed.2))
            return (closed.0, closed.1, closed.2)
        }
        return nil
    }

    /// Pause stops the engine and closes the open segment. Leaving an AAC file
    /// open across a long pause is the one way a force quit could truncate it,
    /// because the moov atom is only written when the handle is released.
    /// Resume opens a fresh segment.
    func pause() {
        guard isRunning else { return }
        pausedByUser = true
        engine.pause()
        ioQueue.sync { self.closeCurrentSegmentOnIOQueue() }
    }

    /// Resume after either a user pause or an interruption the system declined
    /// to auto resume. If the interruption closed the segment, a fresh one is
    /// opened before any buffer can arrive.
    func resume() throws {
        guard isRunning else { return }
        try configureSession()

        // The engine comes up first. Opening the segment before the restart used
        // to leave a stamped segmentStartDate and cleared pause guards behind
        // when engine.start() threw, which is routine while a route settles, and
        // the next route change would then re-arm the microphone behind a UI
        // that still read Paused. The open writer guard in writeOnIOQueue makes
        // the few milliseconds between start and openFile harmless.
        try restartEngine()

        var needsSegment = false
        ioQueue.sync { needsSegment = self.currentFile == nil }
        if needsSegment {
            try ioQueueSyncThrowing { try self.beginNewSegmentOnIOQueue() }
            emit(.segmentOpened(index: currentSegmentIndex, rollsAt: currentSegmentRollDate))
        }
        resetPauseFlags()
    }

    /// The one way the engine is brought back up. Rebuilds the whole graph when
    /// the engine instance was replaced, otherwise just restarts it.
    private func restartEngine() throws {
        let current = engine.inputNode.outputFormat(forBus: 0)
        let routeMoved = tapFormat.map {
            $0.sampleRate != current.sampleRate || $0.channelCount != current.channelCount
        } ?? true

        if !tapInstalled || routeMoved || converter == nil {
            // Route changes are deliberately ignored while paused, so the graph
            // can be stale by the time Resume arrives. Rebuild it rather than
            // restarting a tap bound to a format the hardware no longer uses.
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            try startEngineAndTap()
            return
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw SovoxEngineError.engineStart(error.localizedDescription)
        }
    }

    /// On stop the session is deactivated with notifyOthersOnDeactivation so the
    /// orange microphone indicator clears and other audio apps regain the route.
    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            emit(.failed("Could not release the audio session. \(error.localizedDescription)"))
        }
    }

    // MARK: Session

    /// Ordered most to least capable.
    ///
    /// Only allowBluetoothHFP is formally valid with the .record category.
    /// allowBluetoothA2DP and defaultToSpeaker are documented against
    /// playAndRecord, and on real hardware setCategory rejects both with
    /// OSStatus -50, paramErr. The first rung is still attempted because the
    /// spec asks for it and a future OS could accept it, but the ladder has to
    /// walk all the way down to an empty option set or a device that refuses
    /// them cannot record at all.
    /// Exposed so a test can assert it without reading the source file.
    ///
    /// Must stay .default. The near field modes, voiceChat and videoChat, enable
    /// voice processing, which is tuned for one close speaker and actively
    /// suppresses the distant participants a table mic exists to capture.
    static let sessionMode: AVAudioSession.Mode = .default

    static let categoryLadder: [AVAudioSession.CategoryOptions] = [
        [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker],
        [.allowBluetoothHFP, .allowBluetoothA2DP],
        [.allowBluetoothHFP],
        []
    ]

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()

        var lastError: Error?
        var applied = false
        for options in Self.categoryLadder {
            do {
                try session.setCategory(.record, mode: Self.sessionMode, options: options)
                applied = true
                break
            } catch {
                lastError = error
            }
        }
        guard applied else {
            throw SovoxEngineError.sessionUnavailable(lastError?.localizedDescription ?? "No usable record category options.")
        }

        do {
            try session.setActive(true)
        } catch {
            throw SovoxEngineError.sessionActivation(error.localizedDescription)
        }
    }

    // MARK: Engine and tap

    private func startEngineAndTap() throws {
        let input = engine.inputNode
        // Any format other than the node's own output format traps at runtime.
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw SovoxEngineError.noInputFormat
        }
        tapFormat = hardwareFormat

        guard let processing = fileProcessingFormatValue() else {
            throw SovoxEngineError.converterUnavailable
        }
        guard let conv = AVAudioConverter(from: hardwareFormat, to: processing) else {
            throw SovoxEngineError.converterUnavailable
        }
        converter = conv

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw SovoxEngineError.engineStart(error.localizedDescription)
        }
        tapInstalled = true
    }

    private func fileProcessingFormatValue() -> AVAudioFormat? {
        if let f = fileProcessingFormat { return f }
        var result: AVAudioFormat?
        ioQueue.sync { result = self.currentFile?.processingFormat }
        fileProcessingFormat = result
        return result
    }

    // MARK: Tap path

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        emitLevel(from: buffer)
        // sync keeps every AVAudioFile touch on the one serial queue without
        // needing to copy the buffer across an isolation boundary.
        ioQueue.sync {
            self.writeOnIOQueue(buffer)
        }
    }

    private func writeOnIOQueue(_ buffer: AVAudioPCMBuffer) {
        // No open writer means no recording is meant to be happening. Checking
        // this before the rollover clock is what stops a stale segmentStartDate
        // from opening a fresh segment on a path where nothing should be armed.
        guard currentFile != nil else { return }

        let now = Date()

        if now.timeIntervalSince(segmentStartDate) >= segmentSeconds {
            rollSegmentOnIOQueue(at: now)
        }

        guard let file = currentFile, let converter, let target = fileProcessingFormat else { return }
        guard let converted = convert(buffer, using: converter, to: target) else { return }
        guard converted.frameLength > 0 else { return }

        do {
            try file.write(from: converted)
            segmentFrames += AVAudioFramePosition(converted.frameLength)
        } catch {
            emit(.failed("Write failed. \(error.localizedDescription)"))
        }

        checkStorageOnIOQueue(now: now)
    }

    private func convert(_ input: AVAudioPCMBuffer,
                         using converter: AVAudioConverter,
                         to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        let feed = ConverterFeed(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let pending = feed.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return pending
        }

        if status == .error { return nil }
        return output
    }

    private func emitLevel(from buffer: AVAudioPCMBuffer) {
        let now = Date()
        // Roughly twelve updates a second is plenty for a meter and keeps the
        // tap thread cheap.
        guard now.timeIntervalSince(lastLevelEmit) > 0.08 else { return }
        lastLevelEmit = now

        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        var index = 0
        while index < count {
            let sample = channel[index]
            sum += sample * sample
            index += 1
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_000_1))
        let normalised = max(0, min(1, (db + 55) / 55))
        emit(.level(normalised))
    }

    // MARK: Segmenting

    /// Gapless by construction. Segment N plus one is created and installed as
    /// the write target first. Only then is the handle for segment N released,
    /// which is what closes and finalises it.
    private func rollSegmentOnIOQueue(at now: Date) {
        let closingIndex = segmentIndex
        let closingName = RecordingPaths.segmentFileName(closingIndex)
        let closingDuration = now.timeIntervalSince(segmentStartDate)
        var closingHandle = currentFile

        let nextIndex = closingIndex + 1
        do {
            try openFile(index: nextIndex)
        } catch {
            // Segment N is still open and still receiving audio. Push the
            // deadline out so this retries in ten seconds rather than on every
            // buffer, which would be thousands of failure events a minute.
            segmentStartDate = now.addingTimeInterval(10 - segmentSeconds)
            emit(.failed("Could not roll to segment \(nextIndex). \(error.localizedDescription)"))
            return
        }

        segmentIndex = nextIndex
        segmentStartDate = now
        segmentFrames = 0

        closingHandle = nil
        _ = closingHandle

        emit(.segmentClosed(index: closingIndex, fileName: closingName, duration: closingDuration))
        emit(.segmentOpened(index: nextIndex, rollsAt: now.addingTimeInterval(segmentSeconds)))
    }

    /// Must be called on ioQueue.
    private func openFile(index: Int) throws {
        let url = RecordingPaths.segmentURL(sessionID: sessionID, index: index)
        RecordingPaths.ensureDirectory(url.deletingLastPathComponent())
        do {
            let file = try AVAudioFile(forWriting: url, settings: fileSettings)
            currentFile = file
            if fileProcessingFormat == nil {
                fileProcessingFormat = file.processingFormat
            }
        } catch {
            throw SovoxEngineError.cannotCreateFile(error.localizedDescription)
        }
    }

    /// Opens the next segment when no file is currently open, which is the state
    /// left behind by an interruption or a media services reset. Must be called
    /// on ioQueue.
    /// Both pause notions cleared together at every session boundary. They were
    /// reset separately once, and isPausedForInterruption leaked out of a call
    /// that ended without shouldResume into the next recording, where it
    /// silently suppressed route change and media services recovery for hours.
    private func resetPauseFlags() {
        pausedByUser = false
        isPausedForInterruption = false
    }

    /// Releases the open handle, which is what flushes and finalises the AAC
    /// file, and reports it. A no op when nothing is open. Must be on ioQueue.
    private func closeCurrentSegmentOnIOQueue() {
        guard currentFile != nil else { return }
        let index = segmentIndex
        let name = RecordingPaths.segmentFileName(index)
        let duration = Date().timeIntervalSince(segmentStartDate)
        currentFile = nil
        emit(.segmentClosed(index: index, fileName: name, duration: duration))
    }

    private func beginNewSegmentOnIOQueue() throws {
        // Closed and reported by construction, so no caller can drop a handle
        // without the controller learning about the segment.
        closeCurrentSegmentOnIOQueue()
        segmentIndex += 1
        segmentStartDate = Date()
        segmentFrames = 0
        try openFile(index: segmentIndex)
    }

    private func ioQueueSyncThrowing(_ work: @escaping () throws -> Void) throws {
        var thrown: Error?
        ioQueue.sync {
            do { try work() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    // MARK: Storage

    private func checkStorageOnIOQueue(now: Date) {
        guard now.timeIntervalSince(lastStorageCheck) >= 5 else { return }
        lastStorageCheck = now

        let free = StorageGuard.freeBytes(at: RecordingPaths.documents)
        if StorageGuard.mustStop(freeBytes: free) {
            emit(.storageCritical)
            return
        }
        if StorageGuard.shouldWarn(freeBytes: free) {
            if !lowStorageAnnounced {
                lowStorageAnnounced = true
                emit(.lowStorage(remainingMinutes: StorageGuard.recordableMinutes(freeBytes: free)))
            }
        } else if lowStorageAnnounced {
            // Space came back, for example the user deleted something. Clearing
            // the latch means the warning can be raised again if it drops twice.
            lowStorageAnnounced = false
            emit(.storageRecovered)
        }
    }

    var remainingMinutes: Int {
        StorageGuard.recordableMinutes(freeBytes: StorageGuard.freeBytes(at: RecordingPaths.documents))
    }

    var currentSegmentIndex: Int {
        var value = 1
        ioQueue.sync { value = self.segmentIndex }
        return value
    }

    var currentSegmentRollDate: Date {
        var value = Date()
        ioQueue.sync { value = self.segmentStartDate.addingTimeInterval(self.segmentSeconds) }
        return value
    }

    func updateSegmentSeconds(_ seconds: TimeInterval) {
        ioQueue.sync { self.segmentSeconds = seconds }
    }

    // MARK: Notifications

    private func registerObservers() {
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(handleMediaServicesReset(_:)),
                           name: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil)
        // Belt to the route change braces. AVAudioEngine posts this when it has
        // already stopped and uninitialised itself after a hardware format
        // change, which does not always arrive as a session route change.
        center.addObserver(self,
                           selector: #selector(handleEngineConfigurationChange(_:)),
                           name: .AVAudioEngineConfigurationChange,
                           object: nil)
    }

    private func unregisterObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    /// A phone call arrives. Close the open segment cleanly so nothing is lost,
    /// then wait for the ended notification and continue on a fresh segment.
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt
        // Values are extracted here because Notification is not Sendable. The
        // work itself moves to the main queue, which is the single owner of the
        // engine graph.
        DispatchQueue.main.async { [weak self] in
            self?.processInterruption(type: type, optionsRaw: optionsRaw)
        }
    }

    private func processInterruption(type: AVAudioSession.InterruptionType, optionsRaw: UInt?) {
        switch type {
        case .began:
            isPausedForInterruption = true
            engine.pause()
            ioQueue.sync { self.closeCurrentSegmentOnIOQueue() }
            emit(.interruptionBegan)

        case .ended:
            var shouldResume = false
            if let optionsRaw {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            }
            guard isPausedForInterruption else {
                emit(.interruptionEnded(resumed: false))
                return
            }
            guard !pausedByUser else {
                // The user paused before the call arrived. Their pause outranks
                // the system's offer to resume.
                emit(.interruptionEnded(resumed: false))
                return
            }
            guard shouldResume else {
                // The system says do not resume automatically. The recording is
                // still live from the app's point of view, so the next explicit
                // resume picks it back up.
                emit(.interruptionEnded(resumed: false))
                return
            }
            do {
                try configureSession()
                // Same ordering rule as resume(): commit nothing until the
                // engine is confirmed running.
                try restartEngine()
                try ioQueueSyncThrowing { try self.beginNewSegmentOnIOQueue() }
                isPausedForInterruption = false
                emit(.segmentOpened(index: currentSegmentIndex, rollsAt: currentSegmentRollDate))
                emit(.interruptionEnded(resumed: true))
            } catch {
                emit(.failed("Could not resume after the interruption. \(error.localizedDescription)"))
            }

        @unknown default:
            break
        }
    }

    /// The engine tore its own graph down. Ownership is matched by object
    /// identity rather than by reading `engine` from the posting thread, since
    /// the engine is main queue owned and gets replaced on a media reset.
    @objc private func handleEngineConfigurationChange(_ note: Notification) {
        guard let object = note.object as AnyObject? else { return }
        let posted = ObjectIdentifier(object)
        DispatchQueue.main.async { [weak self] in
            guard let self, ObjectIdentifier(self.engine) == posted else { return }
            self.processEngineConfigurationChange()
        }
    }

    private func processEngineConfigurationChange() {
        guard isRunning, !pausedByUser, !isPausedForInterruption else { return }
        // The engine is already stopped and uninitialised, so the tap and the
        // converter are both stale. The open segment file is untouched, which is
        // why the rebuild continues into the same segment rather than rolling.
        tapInstalled = false
        converter = nil
        tapFormat = nil
        do {
            try restartEngine()
            emit(.routeReconfigured)
        } catch {
            emit(.failed("Audio stopped after a hardware change and could not restart. \(error.localizedDescription)"))
        }
    }

    /// Headphones or Bluetooth arriving or leaving changes the input format.
    /// Reinstall the tap against the new format and keep writing to the same
    /// file. Never stop the recording for a route change.
    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.processRouteChange(reason: reason)
        }
    }

    private func processRouteChange(reason: AVAudioSession.RouteChangeReason) {
        guard isRunning, !isPausedForInterruption, !pausedByUser else { return }
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange, .override, .categoryChange:
            reconfigureInput()
        default:
            break
        }
    }

    private func reconfigureInput() {
        let input = engine.inputNode
        let newFormat = input.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else { return }
        if let tapFormat, tapFormat.sampleRate == newFormat.sampleRate,
           tapFormat.channelCount == newFormat.channelCount, engine.isRunning {
            return
        }

        engine.pause()
        input.removeTap(onBus: 0)
        tapInstalled = false

        guard let target = fileProcessingFormat,
              let conv = AVAudioConverter(from: newFormat, to: target) else {
            emit(.failed("The new audio route is not usable for recording."))
            return
        }
        converter = conv
        tapFormat = newFormat

        input.installTap(onBus: 0, bufferSize: 4096, format: newFormat) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
            emit(.routeReconfigured)
        } catch {
            emit(.failed("Could not restart after the route change. \(error.localizedDescription)"))
        }
    }

    /// Media services died. Everything held against the old server is invalid,
    /// so build a new engine, reconfigure the session and continue on a fresh
    /// segment. The segments already on disk are untouched.
    @objc private func handleMediaServicesReset(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.processMediaServicesReset()
        }
    }

    private func processMediaServicesReset() {
        guard isRunning else { return }
        engine = AVAudioEngine()
        tapInstalled = false
        converter = nil
        tapFormat = nil

        guard !pausedByUser, !isPausedForInterruption else {
            // Engine rebuilt but deliberately left stopped. Resume owns the
            // restart, otherwise a reset during a pause turns the mic back on.
            emit(.mediaServicesReset)
            return
        }

        // Segment N is finalised and reported now, so it can never be lost if
        // the rebuild takes several attempts or fails outright.
        ioQueue.sync { self.closeCurrentSegmentOnIOQueue() }
        emit(.mediaServicesReset)
        attemptRebuild(attempt: 1)
    }

    /// setActive routinely fails with a busy or cannot-start error until the
    /// audio server has finished restarting, so a single attempt is not enough.
    /// Bounded retry, then a clean stop rather than a recording that looks live
    /// and writes nothing for the rest of the meeting.
    private func attemptRebuild(attempt: Int) {
        let maxAttempts = 6
        guard isRunning, !pausedByUser, !isPausedForInterruption else { return }
        do {
            try configureSession()
            try restartEngine()
            try ioQueueSyncThrowing { try self.beginNewSegmentOnIOQueue() }
            emit(.segmentOpened(index: currentSegmentIndex, rollsAt: currentSegmentRollDate))
        } catch {
            guard attempt < maxAttempts else {
                emit(.fatal("Audio could not be restarted after the system reset it. Everything recorded up to that point has been saved."))
                return
            }
            let delay = 0.4 * Double(attempt)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptRebuild(attempt: attempt + 1)
            }
        }
    }

    private func emit(_ event: SovoxEngineEvent) {
        onEvent?(event)
    }
}
