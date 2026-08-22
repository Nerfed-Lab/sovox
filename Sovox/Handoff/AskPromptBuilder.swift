import Foundation

/// Phase 8 prompt. Grounded strictly in the selected transcripts, with every
/// claim attributed, because an unattributed answer over several meetings is
/// impossible to check.
enum AskPromptBuilder {

    struct Source: Equatable, Sendable {
        var title: String
        var date: String
        var transcript: String
    }

    /// The bridge is stateless, so every prior turn is resent with every
    /// question. Unbounded, a long thread quietly becomes most of the context
    /// and the model truncates the transcripts it was supposed to answer from.
    static let historyBudget = 12_000

    static func combinedCharacterCount(_ sources: [Source]) -> Int {
        sources.reduce(0) { $0 + $1.transcript.count }
    }

    /// What the prompt will actually carry: transcripts plus the history that
    /// survives the budget. The context guard is only honest if it counts both.
    static func promptCharacterCount(sources: [Source], history: [AskTurn]) -> Int {
        combinedCharacterCount(sources) + historyCharacterCount(recentHistory(history))
    }

    static func historyCharacterCount(_ history: [AskTurn]) -> Int {
        history.reduce(0) { $0 + $1.question.count + $1.answer.count }
    }

    /// The most recent turns that fit the budget, oldest dropped first. A turn
    /// longer than the whole budget is still kept when it is the only one, so a
    /// follow up never loses the question it follows.
    static func recentHistory(_ history: [AskTurn], budget: Int = historyBudget) -> [AskTurn] {
        var kept: [AskTurn] = []
        var used = 0
        for turn in history.reversed() {
            let size = turn.question.count + turn.answer.count
            if !kept.isEmpty, used + size > budget { break }
            kept.insert(turn, at: 0)
            used += size
        }
        return kept
    }

    static func build(question: String, sources: [Source], history: [AskTurn]) -> String {
        let recent = recentHistory(history)
        let priorBlock: String
        if recent.isEmpty {
            priorBlock = "none"
        } else {
            let elided = recent.count < history.count
                ? "[\(history.count - recent.count) earlier exchanges not included]\n\n"
                : ""
            priorBlock = elided + recent.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        }

        let transcriptBlock = sources.map {
            "=== \($0.title) (\($0.date)) ===\n" + PromptBuilder.fenced($0.transcript)
        }.joined(separator: "\n\n")

        return """
        You are answering questions about meeting transcripts. Answer only from the transcripts provided. If the answer is not in them, say "Not covered in the selected recordings" and stop.

        Attribute every claim to its source recording, as (Source: <recording title>).

        Never speculate, never generalise beyond the transcripts, never fill gaps with plausible detail.

        Plain text. No markdown.

        PREVIOUS Q&A IN THIS SESSION:
        \(priorBlock)

        TRANSCRIPTS:
        \(transcriptBlock)

        \(PromptBuilder.transcriptDataNotice)

        QUESTION:
        \(question)
        """
    }
}
