import Foundation
@preconcurrency import Speech

enum TranscriptionError: LocalizedError {
    case notAuthorised
    case recognizerUnavailable
    case onDeviceModelMissing
    case timedOut
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorised:
            return "Speech recognition permission has not been granted."
        case .recognizerUnavailable:
            return "No speech recogniser is available for this language."
        case .onDeviceModelMissing:
            return "The on device speech model is not installed for this language."
        case .timedOut:
            return "Transcription took too long and was abandoned."
        case .underlying(let message):
            return message
        }
    }
}

/// One shot flag guarding a continuation that a callback API may fire more than
/// once. Lock backed so it is safe from any thread without relying on the
/// Sendability of the framework's callback type.
final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Lock backed holder so the watchdog can cancel a recognition task without
/// capturing a non Sendable framework object in a concurrent closure.
final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?

    func store(_ value: SFSpeechRecognitionTask) {
        lock.lock(); defer { lock.unlock() }
        task = value
    }

    func cancel() {
        lock.lock()
        let value = task
        lock.unlock()
        value?.cancel()
    }
}

/// Serialises transcription work off the main thread.
///
/// Segments are handed to SFSpeechURLRecognitionRequest, which streams the file
/// from disk itself. The file is never read into a Data buffer, so a sixty
/// minute segment costs the same memory as a one minute one.
///
/// No speaker identification is attempted. Apple's transcription emits a plain
/// token stream with no diarisation, so any speaker labels here would be
/// fabricated. Attribution is left to the downstream model, which has the
/// meeting context to infer it.
actor SegmentTranscriber {
    static let shared = SegmentTranscriber()

    private var recognizer: SFSpeechRecognizer?

    private var recognizerLocale: String?

    /// Rebuilt when the requested locale changes, so a settings change takes
    /// effect on the next segment rather than the next launch.
    private func makeRecognizer(localeIdentifier: String) -> SFSpeechRecognizer? {
        let wanted = TranscriptionLocale.normalise(localeIdentifier)
        if let recognizer, recognizerLocale == wanted { return recognizer }
        let candidate = SFSpeechRecognizer(locale: Locale(identifier: wanted))
        recognizer = candidate
        recognizerLocale = wanted
        return candidate
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        makeRecognizer(localeIdentifier: TranscriptionLocale.defaultIdentifier)
    }

    static func authorisationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func requestAuthorisation() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// True when the language model asset has actually been installed on device.
    /// iOS downloads it the first time dictation is enabled for the language.
    func supportsOnDevice() -> Bool {
        makeRecognizer()?.supportsOnDeviceRecognition ?? false
    }

    func isAvailable() -> Bool {
        makeRecognizer()?.isAvailable ?? false
    }

    func localeIdentifier() -> String {
        makeRecognizer()?.locale.identifier ?? "unknown"
    }

    func transcribe(fileURL: URL,
                    expectedDuration: TimeInterval,
                    localeIdentifier: String = TranscriptionLocale.defaultIdentifier) async throws -> String {
        try await outcome(fileURL: fileURL,
                          expectedDuration: expectedDuration,
                          localeIdentifier: localeIdentifier).text
    }

    /// The same recognition, with word timings kept. Phase 19f needs them to
    /// find the pauses that both language passes agree on.
    func outcome(fileURL: URL,
                 expectedDuration: TimeInterval,
                 localeIdentifier: String = TranscriptionLocale.defaultIdentifier) async throws -> TranscriptionOutcome {
        // Authorisation is re-checked at every use, never assumed from launch.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorised
        }
        guard let recognizer = makeRecognizer(localeIdentifier: localeIdentifier) else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceModelMissing
        }

        #if SOVOX_SPEECHANALYZER
        let text = try await SpeechAnalyzerTranscriber.transcribe(fileURL: fileURL, locale: Locale(identifier: TranscriptionLocale.normalise(localeIdentifier)))
        return TranscriptionOutcome(text: text, words: [], localeIdentifier: TranscriptionLocale.normalise(localeIdentifier))
        #else
        return try await recognise(fileURL: fileURL,
                                   recognizer: recognizer,
                                   localeIdentifier: TranscriptionLocale.normalise(localeIdentifier),
                                   timeout: max(180, expectedDuration * 2))
        #endif
    }

    private func recognise(fileURL: URL,
                           recognizer: SFSpeechRecognizer,
                           localeIdentifier: String,
                           timeout: TimeInterval) async throws -> TranscriptionOutcome {
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        // Everything stays on the device. This is also the only mode that works
        // with the App Transport Security lockdown in Info.plist.
        request.requiresOnDeviceRecognition = true
        // Phase 19a absolute rule. Server recognition is prohibited outright,
        // and a request that reaches Apple's servers would breach the zero
        // network guarantee the whole app is built on. Asserted rather than
        // trusted, because the flag is a plain Bool one edit away from false.
        precondition(request.requiresOnDeviceRecognition,
                     "speech request would be allowed to leave the device")
        request.addsPunctuation = true
        request.taskHint = .dictation

        let guardBox = ResumeGuard()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranscriptionOutcome, Error>) in
            let handle = TaskHandle()
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if guardBox.claim() { continuation.resume(throwing: TranscriptionError.underlying(error.localizedDescription)) }
                    return
                }
                guard let result, result.isFinal else { return }
                if guardBox.claim() {
                    let best = result.bestTranscription
                    let words = best.segments.map {
                        TimedWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                    }
                    continuation.resume(returning: TranscriptionOutcome(text: best.formattedString,
                                                                       words: words,
                                                                       localeIdentifier: localeIdentifier))
                }
            }

            handle.store(task)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if guardBox.claim() {
                    handle.cancel()
                    continuation.resume(throwing: TranscriptionError.timedOut)
                }
            }
        }
    }
}
