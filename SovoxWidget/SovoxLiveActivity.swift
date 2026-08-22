import SwiftUI
import WidgetKit
import ActivityKit

struct SovoxLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SovoxAttributes.self) { context in
            LockScreenPresentation(state: context.state)
                .widgetURL(SovoxLiveActivity.deepLink)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        PulsingDot(paused: context.state.isPaused, finished: context.state.isFinished, size: 9)
                        Text("Sovox")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WidgetPalette.ink)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state, size: 22)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stateLine(context.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.subdued)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TransportButtons(state: context.state, compact: false)
                }
            } compactLeading: {
                PulsingDot(paused: context.state.isPaused, finished: context.state.isFinished, size: 9)
            } compactTrailing: {
                ElapsedText(state: context.state, size: 13)
                    .frame(width: 54)
            } minimal: {
                PulsingDot(paused: context.state.isPaused, finished: context.state.isFinished, size: 9)
            }
            .widgetURL(SovoxLiveActivity.deepLink)
            .keylineTint(WidgetPalette.recording)
        }
    }

    private func stateLine(_ state: SovoxAttributes.ContentState) -> String {
        if state.isFinished { return "Saved, \(state.segmentIndex) segments" }
        if state.isPaused { return "Paused" }
        if state.lowStorage { return "Low storage, about \(state.remainingMinutes) min left" }
        if let roll = state.nextRollDate {
            return "Segment \(state.segmentIndex) \u{00B7} rolls at \(shortTime(roll))"
        }
        return "Segment \(state.segmentIndex)"
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// The elapsed clock. Text(timerInterval:) is rendered and advanced by the
/// system with zero updates pushed from the app, which is the only way to keep
/// a live counter inside the ActivityKit update budget.
struct ElapsedText: View {
    var state: SovoxAttributes.ContentState
    var size: CGFloat

    var body: some View {
        Text(timerInterval: state.timerRange,
             pauseTime: state.pausedAt,
             countsDown: false,
             showsHours: true)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(state.isFinished ? WidgetPalette.ink
                             : (state.isPaused ? WidgetPalette.paused : WidgetPalette.ink))
            .multilineTextAlignment(.trailing)
    }
}

/// Both intents run in the app process because they conform to LiveActivityIntent
/// and the intent types are compiled into this extension as well as the app.
struct TransportButtons: View {
    var state: SovoxAttributes.ContentState
    var compact: Bool

    var body: some View {
        // A finished card gets no controls at all. A button that renders but
        // cannot act is the one thing this app must never ship.
        if state.isFinished {
            EmptyView()
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if state.isPaused {
                Button(intent: ResumeSovoxIntent()) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(WidgetPalette.paused)
            } else {
                Button(intent: PauseSovoxIntent()) {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(WidgetPalette.subdued)
            }

            Button(intent: StopSovoxIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(WidgetPalette.recording)
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(WidgetPalette.ink)
    }
}

struct LockScreenPresentation: View {
    var state: SovoxAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ElapsedText(state: state, size: 44)
                Spacer()
                HStack(spacing: 6) {
                    PulsingDot(paused: state.isPaused, finished: state.isFinished, size: 9)
                    Text(badge)
                        .font(.caption.weight(.black))
                        .foregroundStyle(badgeTint)
                }
            }

            Text(detailLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.subdued)
                .lineLimit(1)

            TransportButtons(state: state, compact: true)
        }
        .padding(14)
    }

    private var badge: String {
        if state.isFinished { return "SAVED" }
        return state.isPaused ? "PAUSED" : "REC"
    }

    private var badgeTint: Color {
        if state.isFinished { return WidgetPalette.subdued }
        return state.isPaused ? WidgetPalette.paused : WidgetPalette.recording
    }

    private var detailLine: String {
        if state.isFinished { return "Saved, \(state.segmentIndex) segments" }
        var parts = ["Segment \(state.segmentIndex)"]
        if state.remainingMinutes > 0 { parts.append("\(state.remainingMinutes) min space") }
        if state.lowStorage { parts.append("low storage") }
        return parts.joined(separator: "  \u{00B7}  ")
    }
}
