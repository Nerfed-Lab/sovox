import Foundation

/// Phase 19f. Two complete readings of the same audio, interleaved by pause.
///
/// Aligned on silence rather than on the clock, for one reason: a fixed window
/// cuts through the middle of a clause, and a Hindi clause split across two
/// windows is exactly what must not happen. Silence is acoustic, so both passes
/// agree on where it falls, and speakers switch language at clause boundaries,
/// which nearly always carry a small pause. The alignment key and the switching
/// points are the same thing.
///
/// Nothing here scores, classifies, spell checks or detects a language. The two
/// readings are laid side by side and the model decides. That was a deliberate
/// choice, not an omission.
enum TranscriptMerge {

    /// A pause this long or longer ends a window.
    static let silenceGap: TimeInterval = 0.4
    static let minimumWindow: TimeInterval = 3
    static let maximumWindow: TimeInterval = 20

    struct Window: Equatable, Sendable, Identifiable {
        var start: TimeInterval
        var end: TimeInterval
        var primary: String
        var secondary: String

        var id: String { "\(start)-\(end)" }
        var isEmpty: Bool {
            primary.trimmingCharacters(in: .whitespaces).isEmpty
                && secondary.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Window boundaries, taken from the primary pass alone. The primary is the
    /// canonical reading, so its pauses are the ruler.
    static func boundaries(for words: [TimedWord]) -> [ClosedRange<TimeInterval>] {
        let ordered = words.sorted { $0.start < $1.start }
        guard let first = ordered.first else { return [] }

        var ranges: [ClosedRange<TimeInterval>] = []
        var windowStart = first.start
        var previousEnd = first.end

        for word in ordered.dropFirst() {
            let gap = word.start - previousEnd
            let lengthIfExtended = word.end - windowStart
            // A long enough pause ends the window, but never before the minimum,
            // and a window that would outrun the maximum is split whether or not
            // anybody paused.
            let pauseEnds = gap >= silenceGap && (previousEnd - windowStart) >= minimumWindow
            let tooLong = lengthIfExtended > maximumWindow
            if pauseEnds || tooLong {
                ranges.append(windowStart...previousEnd)
                windowStart = word.start
            }
            previousEnd = max(previousEnd, word.end)
        }
        ranges.append(windowStart...previousEnd)
        return ranges
    }

    /// Words whose midpoint falls inside the range. Midpoint rather than start,
    /// so a word straddling a boundary lands where most of it was spoken.
    static func text(of words: [TimedWord], in range: ClosedRange<TimeInterval>) -> String {
        words
            .filter { word in
                let midpoint = word.start + word.duration / 2
                return midpoint >= range.lowerBound && midpoint <= range.upperBound
            }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func windows(primary: [TimedWord], secondary: [TimedWord]) -> [Window] {
        boundaries(for: primary).compactMap { range in
            let window = Window(start: range.lowerBound,
                                end: range.upperBound,
                                primary: text(of: primary, in: range),
                                secondary: text(of: secondary, in: range))
            // A window both passes heard nothing in is not worth a line.
            return window.isEmpty ? nil : window
        }
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "[%02d:%02d]", total / 60, total % 60)
    }

    /// The merged form that goes into the prompt, and nowhere else.
    ///
    /// Devanagari passes through untouched. The models read it accurately and
    /// transliterating it here would throw information away before they ever
    /// saw it.
    static func render(_ windows: [Window], offset: TimeInterval = 0) -> String {
        windows.map { window in
            var lines = [timestamp(window.start + offset)]
            lines.append("EN: \(window.primary)")
            lines.append("HI: \(window.secondary)")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")
    }
}
