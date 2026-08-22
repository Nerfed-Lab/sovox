import SwiftUI

/// Local animation only. Nothing about this indicator is driven by an update
/// pushed from the app, which is what keeps the activity inside its budget.
struct PulsingDot: View {
    var paused: Bool
    var finished: Bool = false
    var size: CGFloat = 10

    private var tint: Color {
        if finished { return WidgetPalette.subdued }
        return paused ? WidgetPalette.paused : WidgetPalette.recording
    }

    private var label: String {
        if finished { return "Recording saved" }
        return paused ? "Paused" : "Recording"
    }

    var body: some View {
        Image(systemName: finished ? "checkmark.circle.fill" : "circle.fill")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: (paused || finished) ? .nonRepeating : .repeating,
                          isActive: !paused && !finished)
            .accessibilityLabel(label)
    }
}
