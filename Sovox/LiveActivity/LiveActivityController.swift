import Foundation
import ActivityKit

enum LiveActivityStartError: LocalizedError {
    case disabledByUser
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .disabledByUser:
            return "Live Activities are switched off for Sovox. Open Settings, Sovox, Live Activities and turn them on. Recording still works without them, but Stop will only be available inside the app."
        case .rejected(let message):
            return "The system declined to start the Live Activity. \(message)"
        }
    }
}

/// Owns the single Live Activity for a recording.
///
/// Update budget: nothing here is pushed on a schedule. The elapsed clock in
/// every presentation is rendered by Text(timerInterval:), which ticks entirely
/// on the system side. Updates are pushed only on pause, resume, segment roll,
/// low storage and stop, which for a thirty minute segment length is roughly two
/// updates an hour.
/// ActivityKit's Activity is not marked Sendable, but update and end are
/// documented as callable from any concurrency context. This box states that
/// explicitly in one place instead of leaking an unchecked cast to every call.
private struct ActivityJob: @unchecked Sendable {
    let activity: Activity<SovoxAttributes>
    let content: ActivityContent<SovoxAttributes.ContentState>
}

@MainActor
final class LiveActivityController {

    private var activity: Activity<SovoxAttributes>?
    private(set) var lastError: String?

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isActive: Bool { activity != nil }

    func start(sessionID: String, state: SovoxAttributes.ContentState, segmentSeconds: TimeInterval) throws {
        guard areActivitiesEnabled else { throw LiveActivityStartError.disabledByUser }
        endStaleActivities()

        let content = ActivityContent(state: state,
                                      staleDate: staleDate(for: state, segmentSeconds: segmentSeconds),
                                      relevanceScore: 100)
        do {
            activity = try Activity.request(attributes: SovoxAttributes(sessionID: sessionID),
                                            content: content,
                                            pushType: nil)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw LiveActivityStartError.rejected(error.localizedDescription)
        }
    }

    func update(_ state: SovoxAttributes.ContentState, segmentSeconds: TimeInterval) {
        guard let activity else { return }
        let job = ActivityJob(activity: activity,
                              content: ActivityContent(state: state,
                                                       staleDate: staleDate(for: state, segmentSeconds: segmentSeconds),
                                                       relevanceScore: 100))
        Task { await job.activity.update(job.content) }
    }

    func end(finalState: SovoxAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        // Freeze the clock at the true final elapsed and mark the card finished,
        // so the twenty second dismissal window does not show a ticking timer
        // and a pair of controls that no longer do anything.
        var final = finalState
        final.isFinished = true
        final.pausedAt = Date()
        let job = ActivityJob(activity: activity,
                              content: ActivityContent(state: final, staleDate: nil, relevanceScore: 0))
        let dismissAt = Date().addingTimeInterval(20)
        Task {
            await job.activity.end(job.content, dismissalPolicy: .after(dismissAt))
        }
    }

    /// A force quit leaves the activity orphaned. Clearing it at launch means an
    /// activity can never outlive the recording it describes.
    func endStaleActivities() {
        for existing in Activity<SovoxAttributes>.activities {
            let job = ActivityJob(activity: existing,
                                  content: ActivityContent(state: existing.content.state,
                                                           staleDate: nil,
                                                           relevanceScore: 0))
            Task { await job.activity.end(job.content, dismissalPolicy: .immediate) }
        }
        activity = nil
    }

    /// Comfortably past the next scheduled discrete update, so the activity never
    /// dims mid meeting, and never lingers forever if the app dies.
    private func staleDate(for state: SovoxAttributes.ContentState, segmentSeconds: TimeInterval) -> Date {
        if state.isPaused {
            return Date().addingTimeInterval(60 * 60 * 12)
        }
        return Date().addingTimeInterval(segmentSeconds + 30 * 60)
    }
}
