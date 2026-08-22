import Foundation

/// Phase 6. Stored per recording, editable on regeneration. Injects exactly one
/// block into the master prompt.
enum ConversationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, executive, working, casual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .executive: return "Executive"
        case .working: return "Working"
        case .casual: return "Casual"
        }
    }

    static let executiveBody = """
    This was a senior client or senior internal meeting. Retain everything of substance; err heavily towards inclusion. Where a point is ambiguous, keep it rather than cut it. Frame decisions and actions strategically, implications, dependencies, and what it means for the engagement, not just what was said. Measured, formal language suitable for forwarding to a senior audience unedited.
    """

    static let workingBody = """
    This was a routine internal working discussion. Filter aggressively: drop scheduling chatter, tangents, and anything not bearing on the work. Actions are tactical and concrete, who does what by when. Plain direct language. Brevity is the priority; if a section would be empty, omit it rather than padding it.
    """

    static let casualBody = """
    This was an informal or unstructured conversation and may wander. Be highly selective: extract only what is genuinely worth remembering. Most of this transcript is probably not worth capturing, and a short output is the correct outcome. Do not manufacture structure that was not there. If there is nothing of substance, say so in one line rather than inventing content.
    """

    /// The single block injected into the prompt.
    var promptBlock: String {
        switch self {
        case .executive:
            return "CONVERSATION TYPE\n" + Self.executiveBody
        case .working:
            return "CONVERSATION TYPE\n" + Self.workingBody
        case .casual:
            return "CONVERSATION TYPE\n" + Self.casualBody
        case .auto:
            return """
            CONVERSATION TYPE
            Determine from the transcript which of the three registers below best fits this conversation, then apply it. Say nothing about which you chose, just apply it.

            Executive: \(Self.executiveBody)

            Working: \(Self.workingBody)

            Casual: \(Self.casualBody)
            """
        }
    }
}
