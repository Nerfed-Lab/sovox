import Foundation

/// A word and where it sits in the audio. Phase 19f aligns the two language
/// passes on silence, and silence is only visible through timings.
struct TimedWord: Codable, Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var duration: TimeInterval

    var end: TimeInterval { start + duration }
}

/// What one recognition pass produced.
struct TranscriptionOutcome: Equatable, Sendable {
    var text: String
    var words: [TimedWord]
    var localeIdentifier: String

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func empty(_ locale: String) -> TranscriptionOutcome {
        TranscriptionOutcome(text: "", words: [], localeIdentifier: locale)
    }
}
