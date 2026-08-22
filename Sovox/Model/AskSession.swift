import Foundation

struct AskTurn: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var question: String
    var answer: String
    var askedAt: Date

    init(id: UUID = UUID(), question: String, answer: String, askedAt: Date = Date()) {
        self.id = id
        self.question = question
        self.answer = answer
        self.askedAt = askedAt
    }
}

/// Phase 8 context length guard. The main failure mode is a confident answer
/// drawn from a context the model silently truncated, which is worse than a
/// refusal, so the top band blocks rather than trims.
enum AskContextGuard {
    static let amberThreshold = 40_000
    static let blockThreshold = 100_000

    enum Verdict: Equatable {
        case ok
        case warn(String)
        case block(String)

        var blocks: Bool { if case .block = self { return true }; return false }
    }

    static func verdict(characterCount count: Int) -> Verdict {
        if count > blockThreshold {
            return .block("\(formatted(count)) characters selected. Deselect some recordings, over \(formatted(blockThreshold)) the model would truncate and answer confidently from a partial context.")
        }
        if count >= amberThreshold {
            return .warn("\(formatted(count)) characters selected. The model may truncate this.")
        }
        return .ok
    }

    static func formatted(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

/// The running thread for this Ask session. Persisted so follow ups keep
/// working: the bridge is stateless, so prior turns have to be resent.
@MainActor
@Observable
final class AskSession {
    static let shared = AskSession()

    private(set) var turns: [AskTurn] = []
    var selectedIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let key = "sovox.askTurns"

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AskTurn].self, from: data) {
            turns = decoded
        }
    }

    func append(question: String, answer: String) {
        turns.append(AskTurn(question: question, answer: answer))
        persist()
    }

    func clear() {
        turns = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(turns) else { return }
        defaults.set(data, forKey: key)
    }
}
