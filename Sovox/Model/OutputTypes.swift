import Foundation

enum AIDestination: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatgpt
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }

    /// Name of the bridge Shortcut the user creates once. Spaces and hyphens in
    /// the name are why the x-callback URL must be percent encoded properly.
    var shortcutName: String {
        switch self {
        case .chatgpt: return "Sovox Bridge - ChatGPT"
        case .claude: return "Sovox Bridge - Claude"
        }
    }
}

/// Screen order is CaseIterable order. Raw values are deliberately unchanged
/// from the previous release so a stored default set still decodes.
enum OutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cleanedTranscript
    case transcriptSummary
    case actionsAndDecisions
    case taskPrompts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanedTranscript: return "Cleaned transcript"
        case .transcriptSummary: return "Transcript summary"
        case .actionsAndDecisions: return "Actions & decision logs"
        case .taskPrompts: return "Task prompts"
        }
    }
}
