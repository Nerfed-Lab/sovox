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

    /// Name of the bridge Shortcut the user creates once.
    ///
    /// Letters only, deliberately. The previous names carried spaces and a
    /// hyphen, and iOS smart punctuation turned the hyphen the user typed into
    /// an en dash. Shortcuts then matched nothing, and the app blamed a missing
    /// shortcut, which sent the user looking in the wrong place. A name with no
    /// punctuation at all cannot be mangled by anything.
    var shortcutName: String {
        switch self {
        case .chatgpt: return "SovoxChatGPT"
        case .claude: return "SovoxClaude"
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
