import Foundation

struct SegmentTranscript: Codable, Equatable, Sendable, Identifiable {
    var index: Int
    var text: String
    var id: Int { index }
}

/// Joins per segment transcripts back into one document.
/// No speaker labelling is attempted anywhere. Apple's transcription does not
/// emit speaker turns and inventing them would corrupt the downstream summary.
enum TranscriptStitcher {
    static func marker(for index: Int) -> String {
        "--- [segment \(index) begins] ---"
    }

    static func placeholder(for index: Int) -> String {
        "[segment \(index) could not be transcribed]"
    }

    /// Tolerant stitch. A settled segment with no text leaves a visible hole
    /// rather than silently shortening the transcript, because notes built from
    /// a quietly truncated transcript are worse than notes with a stated gap.
    /// A segment still queued or running contributes nothing yet and is skipped,
    /// since it is not a gap, it just has not arrived.
    static func stitch(records: [SegmentRecord]) -> String {
        let ordered = records.sorted { $0.index < $1.index }

        var pieces: [(index: Int, body: String)] = []
        for record in ordered {
            let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                // Phase 18a. A failed segment leaves a stated gap, because the
                // words existed and were lost. A silent one leaves nothing,
                // because there were no words: labelling silence "could not be
                // transcribed" is what filled History with junk.
                if record.state.isFailure {
                    pieces.append((record.index, placeholder(for: record.index)))
                }
                continue
            }
            pieces.append((record.index, text))
        }

        guard let first = pieces.first else { return "" }
        var out = first.body
        for piece in pieces.dropFirst() {
            out += "\n\n" + marker(for: piece.index) + "\n\n" + piece.body
        }
        return out
    }

    static func stitch(_ segments: [SegmentTranscript]) -> String {
        let ordered = segments
            .sorted { $0.index < $1.index }
            .map { SegmentTranscript(index: $0.index, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }

        guard let first = ordered.first else { return "" }

        var out = first.text
        for segment in ordered.dropFirst() {
            out += "\n\n" + marker(for: segment.index) + "\n\n" + segment.text
        }
        return out
    }

    /// The transcript with the app's own scaffolding taken out: the segment
    /// markers and the placeholders that stand in for segments which failed.
    /// What is left is what a person actually said.
    static func spokenContent(_ transcript: String) -> String {
        transcript
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return false }
                if trimmed.hasPrefix("--- [segment "), trimmed.hasSuffix("---") { return false }
                if trimmed.hasPrefix("[segment "), trimmed.hasSuffix("could not be transcribed]") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First non empty line, used for the History list subtitle.
    static func preview(_ transcript: String, limit: Int = 120) -> String {
        let line = transcript
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if line.count <= limit { return line }
        return String(line.prefix(limit)) + "..."
    }
}
