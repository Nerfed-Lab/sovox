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

    static func combinedCharacterCount(_ sources: [Source]) -> Int {
        sources.reduce(0) { $0 + $1.transcript.count }
    }

    static func build(question: String, sources: [Source], history: [AskTurn]) -> String {
        let priorBlock: String
        if history.isEmpty {
            priorBlock = "none"
        } else {
            priorBlock = history.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        }

        let transcriptBlock = sources.map {
            "=== \($0.title) (\($0.date)) ===\n\($0.transcript)"
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

        QUESTION:
        \(question)
        """
    }
}
