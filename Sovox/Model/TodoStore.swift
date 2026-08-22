import Foundation
import Observation

/// Phase 9 store.
///
/// The watermark records which recordings have already been fed to the model.
/// It advances only after a review completes, so a dismissed sheet does not
/// consume the recordings it was about to propose from.
@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()

    private(set) var items: [TodoItem] = []
    private(set) var ingestedRecordingIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let itemsKey = "sovox.todos"
    private let watermarkKey = "sovox.todoWatermark"

    private init() {
        if let data = defaults.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
        }
        ingestedRecordingIDs = Set(defaults.stringArray(forKey: watermarkKey) ?? [])
    }

    // MARK: Queries

    var open: [TodoItem] {
        items.filter { !$0.isDone }
            .sorted { lhs, rhs in
                lhs.priority.rank == rhs.priority.rank
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.priority.rank < rhs.priority.rank
            }
    }

    var completed: [TodoItem] {
        items.filter(\.isDone).sorted { $0.createdAt > $1.createdAt }
    }

    var openCount: Int { open.count }

    var isAtCap: Bool { openCount >= TodoPolicy.maxOpen }

    func item(id: UUID) -> TodoItem? { items.first { $0.id == id } }

    // MARK: Mutation

    func add(_ item: TodoItem) {
        items.append(item)
        persist()
    }

    func update(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        persist()
    }

    func toggleDone(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        persist()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    // MARK: Refresh

    /// Recordings the model has not seen yet.
    ///
    /// Requires the session to be fully settled, not merely to have some text.
    /// A long recording whose first segment alone had transcribed would
    /// otherwise be sent as a fragment and then watermarked as fully consumed,
    /// permanently losing the rest.
    func pendingSources(from sessions: [RecordingSession]) -> [RecordingSession] {
        sessions
            .filter { session in
                if session.source == .pasted { return !session.transcript.isEmpty }
                return session.isComplete && session.isTranscribed && !session.stitchedTranscript.isEmpty
            }
            .filter { !ingestedRecordingIDs.contains($0.id) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Applies only what the user accepted. Nothing here runs without approval.
    func apply(_ operations: [TodoOperation]) {
        for operation in operations {
            switch operation {
            case .add(let text, let priority, let sourceTitle, let context):
                items.append(TodoItem(text: text,
                                      sourceRecordingTitle: sourceTitle,
                                      contextExcerpt: context,
                                      priority: priority,
                                      origin: .ai))
            case .merge(let id, let text, _):
                guard let index = items.firstIndex(where: { $0.id == id }),
                      items[index].origin == .ai else { continue }
                items[index].text = text
            case .done(let id, _):
                guard let index = items.firstIndex(where: { $0.id == id }),
                      items[index].origin == .ai else { continue }
                items[index].isDone = true
            }
        }
        persist()
    }

    /// Called only once a review has actually completed.
    func advanceWatermark(with ids: [String]) {
        ingestedRecordingIDs.formUnion(ids)
        defaults.set(Array(ingestedRecordingIDs), forKey: watermarkKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: itemsKey)
    }
}

/// Phase 9 prompt.
enum TodoPromptBuilder {
    static func build(open: [TodoItem], sources: [RecordingSession]) -> String {
        let existing: String
        if open.isEmpty {
            existing = "none"
        } else {
            existing = open.map {
                "\($0.id.uuidString) | \($0.text) | \($0.sourceRecordingTitle ?? "manual") | \($0.priority.rawValue)"
            }.joined(separator: "\n")
        }

        let transcripts = sources.map {
            "=== \($0.displayTitle) (\($0.dateLine)) ===\n\($0.stitchedTranscript)"
        }.joined(separator: "\n\n")

        return """
        You maintain a short running to-do list from meeting transcripts.

        EXISTING OPEN TO-DOS:
        \(existing)

        NEW TRANSCRIPTS SINCE LAST REFRESH:
        \(transcripts)

        Return ONLY operations, one per line, in these exact formats:

        ADD | <text> | <high|medium|low> | <source title> | <2-4 sentence context excerpt closely paraphrased from the transcript>
        MERGE | <existing id> | <new combined text> | <reason under 10 words>
        DONE | <existing id> | <reason under 10 words>

        Rules:
        - High-level only. "Finalise Q3 pricing model", not "email Tom the spreadsheet". Aim for things taking more than an hour.
        - Maximum 5 ADD operations per refresh.
        - Never duplicate an existing to-do. Propose MERGE instead.
        - Only propose DONE where the transcript gives clear evidence the work was completed. Never infer completion from absence of mention.
        - Never invent a to-do that was not discussed.
        - If there is nothing to propose, return exactly: NONE
        """
    }
}
