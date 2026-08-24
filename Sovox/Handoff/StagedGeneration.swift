import Foundation

/// Phase 19h. A merged transcript is roughly twice the size of a single one,
/// and the model's real limit is tokens, which Devanagari spends far faster
/// than Latin. Above the threshold the work is split by what is local and what
/// is global.
///
/// Reconciliation is local: deciding whether a given fifteen seconds was
/// English or Hindi needs no knowledge of what happens forty minutes later.
/// Synthesis is global: a decision taken early and revised late needs both in
/// view. So every segment is resolved on its own, then the whole conversation
/// is summarised once. Notes are never generated per segment and stitched,
/// because three concatenated summaries are a worse artifact than one summary
/// of everything.
struct StagedGeneration: Codable, Equatable, Sendable {
    /// Measured against the merged character count. Set below what a context
    /// window would strictly allow, because characters understate Devanagari.
    static let threshold = 80_000

    var sessionID: String
    var segmentIndices: [Int]
    var resolved: [Int: String]
    var modes: [String]
    var customActionIDs: [String]
    var conversationType: String
    var destination: String

    /// The next segment that still needs resolving.
    var nextSegment: Int? { segmentIndices.first { resolved[$0] == nil } }

    var isReadyForSynthesis: Bool { nextSegment == nil }

    var completedCount: Int { segmentIndices.filter { resolved[$0] != nil }.count }
    var totalCount: Int { segmentIndices.count }

    /// What stage 2 receives: single language, filler stripped, Devanagari
    /// free, and in order.
    var resolvedTranscript: String {
        segmentIndices.compactMap { resolved[$0] }.joined(separator: "\n\n")
    }

    /// Names the stage rather than showing an anonymous spinner, because this
    /// is several trips out to Shortcuts and back and silence looks like a
    /// hang.
    var progressLabel: String {
        if let next = nextSegment, let position = segmentIndices.firstIndex(of: next) {
            return "Resolving segment \(position + 1) of \(totalCount)"
        }
        return "Generating notes"
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        // The final synthesis is the last slice of the bar.
        return Double(completedCount) / Double(totalCount + 1)
    }

    static func plan(for session: RecordingSession,
                     modes: Set<OutputMode>,
                     customActions: [CustomAction],
                     conversationType: ConversationType,
                     destination: AIDestination) -> StagedGeneration {
        StagedGeneration(sessionID: session.id,
                         segmentIndices: session.segments
                            .filter { !$0.mergedWindows.isEmpty }
                            .map(\.index)
                            .sorted(),
                         resolved: [:],
                         modes: modes.map(\.rawValue),
                         customActionIDs: customActions.map { $0.id.uuidString },
                         conversationType: conversationType.rawValue,
                         destination: destination.rawValue)
    }

    /// Whether this recording needs splitting at all. Most do not.
    static func isNeeded(for session: RecordingSession) -> Bool {
        session.hasMergedReading && session.mergedTranscript.count > threshold
    }
}
