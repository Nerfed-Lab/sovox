import Foundation

enum TodoPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case high, medium, low

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Sort weight. High first.
    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

enum TodoOrigin: String, Codable, Sendable {
    case ai
    case manual
}

struct TodoItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var text: String
    var sourceRecordingId: String?
    var sourceRecordingTitle: String?
    /// Two to four sentences captured at creation, shown when tapped.
    var contextExcerpt: String
    var createdAt: Date
    var priority: TodoPriority
    var isDone: Bool
    var origin: TodoOrigin

    init(id: UUID = UUID(),
         text: String,
         sourceRecordingId: String? = nil,
         sourceRecordingTitle: String? = nil,
         contextExcerpt: String = "",
         createdAt: Date = Date(),
         priority: TodoPriority = .medium,
         isDone: Bool = false,
         origin: TodoOrigin = .manual) {
        self.id = id
        self.text = text
        self.sourceRecordingId = sourceRecordingId
        self.sourceRecordingTitle = sourceRecordingTitle
        self.contextExcerpt = contextExcerpt
        self.createdAt = createdAt
        self.priority = priority
        self.isDone = isDone
        self.origin = origin
    }
}

/// One proposed change from the model. Nothing is applied until the user
/// accepts it in the review sheet.
enum TodoOperation: Equatable, Identifiable, Sendable {
    case add(text: String, priority: TodoPriority, sourceTitle: String, context: String)
    case merge(id: UUID, text: String, reason: String)
    case done(id: UUID, reason: String)

    var id: String {
        switch self {
        case .add(let text, _, _, _): return "add:\(text)"
        case .merge(let id, let text, _): return "merge:\(id):\(text)"
        case .done(let id, _): return "done:\(id)"
        }
    }

    var summary: String {
        switch self {
        case .add(let text, let priority, let source, _):
            return "Add \(priority.title.lowercased()) priority: \(text)  from \(source)"
        case .merge(_, let text, let reason):
            return "Merge into: \(text)  (\(reason))"
        case .done(_, let reason):
            return "Mark done: \(reason)"
        }
    }
}

/// Parses the model's operation lines. Anything malformed is dropped rather
/// than guessed at, and the count of dropped lines is reported so a bad
/// response is visible instead of silently producing nothing.
enum TodoOperationParser {
    static let maxAdds = 5

    struct Result: Equatable {
        var operations: [TodoOperation] = []
        var unparsedLines: [String] = []
        var isNone: Bool = false
    }

    static func parse(_ raw: String, knownIDs: [UUID]) -> Result {
        var result = Result()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NONE" {
            result.isNone = true
            return result
        }

        var adds = 0
        for line in trimmed.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { continue }
            if clean.uppercased() == "NONE" { continue }

            let parts = clean.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let verb = parts.first?.uppercased() else { continue }

            switch verb {
            case "ADD" where parts.count >= 5:
                guard adds < maxAdds else {
                    result.unparsedLines.append("ADD beyond the \(maxAdds) per refresh limit: \(parts[1])")
                    continue
                }
                let priority = TodoPriority(rawValue: parts[2].lowercased()) ?? .medium
                result.operations.append(.add(text: parts[1],
                                              priority: priority,
                                              sourceTitle: parts[3],
                                              context: parts[4...].joined(separator: " | ")))
                adds += 1
            case "MERGE" where parts.count >= 4:
                guard let id = UUID(uuidString: parts[1]), knownIDs.contains(id) else {
                    result.unparsedLines.append(clean)
                    continue
                }
                result.operations.append(.merge(id: id, text: parts[2], reason: parts[3]))
            case "DONE" where parts.count >= 3:
                guard let id = UUID(uuidString: parts[1]), knownIDs.contains(id) else {
                    result.unparsedLines.append(clean)
                    continue
                }
                result.operations.append(.done(id: id, reason: parts[2]))
            default:
                result.unparsedLines.append(clean)
            }
        }
        return result
    }
}

/// The cap, and the rule that manual items are untouchable.
enum TodoPolicy {
    static let maxOpen = 10

    /// Operations that must never be offered, because they target an item the
    /// user created by hand. Only AI created to-dos can be merged or auto
    /// completed.
    static func rejectingManualTargets(_ operations: [TodoOperation],
                                       items: [TodoItem]) -> (kept: [TodoOperation], blocked: [TodoOperation]) {
        var kept: [TodoOperation] = []
        var blocked: [TodoOperation] = []
        for operation in operations {
            let targetID: UUID?
            switch operation {
            case .add: targetID = nil
            case .merge(let id, _, _): targetID = id
            case .done(let id, _): targetID = id
            }
            if let targetID, items.first(where: { $0.id == targetID })?.origin == .manual {
                blocked.append(operation)
            } else {
                kept.append(operation)
            }
        }
        return (kept, blocked)
    }

    /// How many open items would exist if every accepted ADD were applied.
    static func overflow(openCount: Int, acceptedAdds: Int, acceptedDones: Int) -> Int {
        max(0, openCount + acceptedAdds - acceptedDones - maxOpen)
    }
}
