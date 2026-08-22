import Foundation

/// The single source of truth for recording duration.
///
/// Derived from a stored start Date minus accumulated paused time. Nothing here
/// is incremented by a Timer. Timers stop firing when the process is throttled
/// and the clock would silently stall or drift over a three hour meeting.
struct ElapsedClock: Codable, Equatable, Sendable {
    var startDate: Date
    var accumulatedPaused: TimeInterval = 0
    var pausedAt: Date?

    init(startDate: Date = Date(), accumulatedPaused: TimeInterval = 0, pausedAt: Date? = nil) {
        self.startDate = startDate
        self.accumulatedPaused = accumulatedPaused
        self.pausedAt = pausedAt
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        let wall = now.timeIntervalSince(startDate)
        let inFlightPause = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, wall - accumulatedPaused - inFlightPause)
    }

    mutating func pause(at now: Date = Date()) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date = Date()) {
        guard let began = pausedAt else { return }
        accumulatedPaused += max(0, now.timeIntervalSince(began))
        pausedAt = nil
    }

    /// Total paused seconds including a pause that is still open.
    func totalPaused(at now: Date = Date()) -> TimeInterval {
        accumulatedPaused + (pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

enum DurationFormat {
    /// h:mm:ss once past an hour, m:ss below it. Monospaced digits are applied
    /// by the view, not baked into the string.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "22,815 min of space left" is unreadable. Hours above two, minutes below.
    static func spaceRemaining(minutes: Int) -> String {
        guard minutes > 0 else { return "no space left" }
        if minutes > 120 {
            return "\(minutes / 60) hrs of space left"
        }
        return "\(minutes) min of space left"
    }

    static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}
