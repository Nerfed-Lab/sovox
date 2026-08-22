import Foundation
import ActivityKit

/// Shared between the app target and the widget extension.
/// Every field here is a discrete state value. Nothing in here ticks.
/// The elapsed clock is rendered by Text(timerInterval:) which runs
/// client side with zero updates pushed from the app.
struct SovoxAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// Wall clock instant the recording began.
        var startDate: Date
        /// Seconds spent in pauses that have already ENDED. An open pause is
        /// deliberately excluded, because pausedAt is what freezes the system
        /// rendered timer. Counting it here as well subtracts it twice and the
        /// clock jumps backwards.
        var accumulatedPaused: TimeInterval
        /// Non nil while paused. Freezes the system rendered timer.
        var pausedAt: Date?
        /// 1 based index of the segment currently being written.
        var segmentIndex: Int
        /// Instant the current segment rolls over to the next one.
        var nextRollDate: Date?
        /// Recordable minutes left on the volume at the current bitrate.
        var remainingMinutes: Int
        /// True once free space drops under the warning threshold.
        var lowStorage: Bool
        /// Set on the final content pushed when the recording stops. The widget
        /// branches on this before isPaused so a finished card never shows a
        /// Resume button that would do nothing.
        var isFinished: Bool = false

        var isPaused: Bool { pausedAt != nil }

        /// Shifting the range start forward by the accumulated paused time
        /// makes the system timer read true elapsed recording time.
        var timerRange: ClosedRange<Date> {
            let base = startDate.addingTimeInterval(accumulatedPaused)
            return base...base.addingTimeInterval(60 * 60 * 24)
        }

        /// Single place the running clock is mapped into activity state, so the
        /// open pause can only be handled one way. accumulatedPaused must be the
        /// closed pause total, never totalPaused, because pausedAt already
        /// freezes the system rendered timer.
        static func from(clock: ElapsedClock,
                         segmentIndex: Int,
                         nextRollDate: Date?,
                         remainingMinutes: Int,
                         lowStorage: Bool) -> ContentState {
            ContentState(startDate: clock.startDate,
                         accumulatedPaused: clock.accumulatedPaused,
                         pausedAt: clock.pausedAt,
                         segmentIndex: segmentIndex,
                         nextRollDate: nextRollDate,
                         remainingMinutes: remainingMinutes,
                         lowStorage: lowStorage)
        }

        /// What the system rendered timer actually reads. Exposed so the
        /// contract is testable rather than implied.
        func displayedElapsed(at now: Date) -> TimeInterval {
            let reference = pausedAt ?? now
            return max(0, reference.timeIntervalSince(timerRange.lowerBound))
        }

        static func idle() -> ContentState {
            ContentState(startDate: Date(),
                         accumulatedPaused: 0,
                         pausedAt: nil,
                         segmentIndex: 1,
                         nextRollDate: nil,
                         remainingMinutes: 0,
                         lowStorage: false)
        }
    }

    /// Folder name of the session, for example capture-20260821-1430.
    var sessionID: String
}

/// One place the URL scheme is spelled. The rename broke the deep link handler
/// and the Self Test because each carried its own copy of the string.
enum SovoxURL {
    static let scheme = "sovox"

    static func url(_ host: String) -> URL {
        URL(string: "\(scheme)://\(host)")!
    }

    static let recording = url("recording")
    static let done = url("done")
    static let failed = url("failed")

    enum Host {
        static let recording = "recording"
        static let done = "done"
        static let failed = "failed"
    }

    enum Route: Equatable {
        case collectResult
        case reportFailure
        case openRecording
        case ignore
    }

    /// Routing decision for an incoming URL, kept out of the App struct so it
    /// can be tested.
    ///
    /// Case is normalised because a scheme or host typed by hand into a
    /// Shortcut is not guaranteed to arrive lowercased, and a callback that
    /// silently does nothing is the worst failure this app has: the user waits
    /// for a result that is already sitting in the file.
    ///
    /// An unrecognised host while a request is in flight is still treated as the
    /// success callback. Nothing else opens this scheme, the bridge is the only
    /// caller, and the alternative is an indefinite wait on a mistyped host.
    static func route(for url: URL, isInFlight: Bool) -> Route {
        guard url.scheme?.lowercased() == scheme else { return .ignore }
        switch url.host?.lowercased() {
        case Host.done: return .collectResult
        case Host.failed: return .reportFailure
        case Host.recording: return .openRecording
        default: return isInFlight ? .collectResult : .ignore
        }
    }
}

enum SovoxLiveActivity {
    /// Deep link target for a tap on the Lock Screen presentation.
    static let deepLink = SovoxURL.recording
    static let activityKind = "SovoxRecording"
}
