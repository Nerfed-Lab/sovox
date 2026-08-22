import AppIntents

/// All five transport intents live in this file, and this file is a member of
/// both the app target and the widget extension target. Live Activity buttons
/// render from the widget but the intent type must resolve in both binaries.
/// Conforming to LiveActivityIntent makes iOS perform them in the app process,
/// which is the only process that owns the audio engine.

struct StartSovoxIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Sovox"
    static let description = IntentDescription("Begins a new background recording.")
    /// iOS refuses to activate a recording session for a process it launched
    /// straight into the background, so anything that begins a recording brings
    /// the app forward first. Stop, Pause and Resume do not, which is what lets
    /// the Lock Screen buttons work without unlocking.
    static let openAppWhenRun = true

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
struct ToggleSovoxIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Sovox"
    static let description = IntentDescription("Starts a recording, or stops the one in progress.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SovoxCommands.toggle()
        return .result(dialog: IntentDialog(stringLiteral: result.spokenText))
    }
}
