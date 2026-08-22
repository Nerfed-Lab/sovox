import Foundation

/// Result of a transport command, returned to Siri and the Shortcuts app.
enum SovoxCommandResult: String, Sendable {
    case started
    case stopped
    case paused
    case resumed
    case unavailable
    case startFailed
    case alreadyRunning
    case notRunning
    case awaitingConsent

    var spokenText: String {
        switch self {
        case .started: return "started"
        case .stopped: return "stopped"
        case .paused: return "paused"
        case .resumed: return "resumed"
        case .unavailable: return "Sovox is not running. Open the app once, then try again."
        case .startFailed: return "Could not start. Open Sovox to see why."
        case .alreadyRunning: return "already recording"
        case .notRunning: return "not recording"
        case .awaitingConsent: return "Sovox is open and waiting. Tell everyone you are recording, then tap Start."
        }
    }
}

/// Implemented by RecorderController in the app target.
/// Declared here so the intents compile inside the widget extension too,
/// where no implementation exists and the handler stays nil.
@MainActor
protocol SovoxCommandHandler: AnyObject {
    var isRecordingNow: Bool { get }
    func commandStart() async -> SovoxCommandResult
    func commandStop() async -> SovoxCommandResult
    func commandPause() async -> SovoxCommandResult
    func commandResume() async -> SovoxCommandResult
    func commandToggle() async -> SovoxCommandResult
}

/// Registry the App Intents talk to.
/// Intents backing the Live Activity buttons conform to LiveActivityIntent,
/// so iOS performs them inside the app process, launching the app in the
/// background if it is not already alive. That is where this handler lives.
@MainActor
enum SovoxCommands {
    static weak var handler: SovoxCommandHandler?

    /// Short bounded wait so an intent that arrives a few milliseconds before
    /// the app finishes launching still finds the handler. Capped well under
    /// the App Intents execution budget.
    static func resolveHandler(timeoutSeconds: Double = 2.0) async -> SovoxCommandHandler? {
        if let handler { return handler }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let handler { return handler }
        }
        return nil
    }

    static func start() async -> SovoxCommandResult {
        guard let h = await resolveHandler() else { return .unavailable }
        return await h.commandStart()
    }

    static func stop() async -> SovoxCommandResult {
        guard let h = await resolveHandler() else { return .unavailable }
        return await h.commandStop()
    }

    static func pause() async -> SovoxCommandResult {
        guard let h = await resolveHandler() else { return .unavailable }
        return await h.commandPause()
    }

    static func resume() async -> SovoxCommandResult {
        guard let h = await resolveHandler() else { return .unavailable }
        return await h.commandResume()
    }

    static func toggle() async -> SovoxCommandResult {
        guard let h = await resolveHandler() else { return .unavailable }
        return await h.commandToggle()
    }
}
