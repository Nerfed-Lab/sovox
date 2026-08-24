import AppIntents

/// All five transport intents live in this file, and this file is a member of
/// both the app target and the widget extension target. Live Activity buttons
/// render from the widget but the intent type must resolve in both binaries.
/// Conforming to LiveActivityIntent makes iOS perform them in the app process,
/// which is the only process that owns the audio engine.

struct StartSovoxIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Sovox"
    static let description = IntentDescription("Begins a new background recording.")
    /// AudioRecordingIntent is what lets a recording begin without the app
    /// coming forward. Before iOS 18 the session simply refused to activate for
    /// a process launched into the background, which is why this used to open
    /// the app; the Action Button now starts the recording and leaves you where
    /// you were, with the Dynamic Island as the only sign.
    ///
    /// If activation still fails, the failure is spoken back and a notification
    /// is posted, because a recording that did not start must never be silent.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.start()
        // A button that does nothing is the worst outcome of all. If the
        // recording could not be started from the background, open the app and
        // start there, which is exactly what this intent used to do every time.
        if result.needsForeground {
            return .result(opensIntent: OpenSovoxAndStartIntent(),
                           dialog: IntentDialog(stringLiteral: "Opening Sovox to start recording"))
        }
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}

/// Opens the app and starts there. Only ever reached when the background start
/// failed, so the Action Button degrades to its old behaviour instead of
/// appearing broken.
struct OpenSovoxAndStartIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sovox and start recording"
    static let description = IntentDescription("Opens Sovox and begins recording.")
    static let openAppWhenRun = true
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.start()
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}

struct StopSovoxIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Sovox"
    static let description = IntentDescription("Stops the recording and finalises every segment.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.stop()
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}

struct PauseSovoxIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Sovox"
    static let description = IntentDescription("Pauses the recording without losing the current segment.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.pause()
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}

struct ResumeSovoxIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Sovox"
    static let description = IntentDescription("Resumes a paused recording on a fresh segment.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.resume()
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}

/// Backs the Control Center control and the Siri phrase "Toggle Sovox".
/// Returns as soon as the transport state flips. Transcription is queued on a
/// detached task and is never awaited here, so this cannot hit the intent
/// execution budget.
struct ToggleSovoxIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Toggle Sovox"
    static let description = IntentDescription("Starts a recording, or stops the one in progress.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.toggle()
        if result.needsForeground {
            return .result(opensIntent: OpenSovoxAndStartIntent(),
                           dialog: IntentDialog(stringLiteral: "Opening Sovox to start recording"))
        }
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}
