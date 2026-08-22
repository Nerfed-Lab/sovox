import SwiftUI

/// Every Liquid Glass surface in the app funnels through this file. If an iOS 26
/// glass signature ever shifts, this is the only place that needs touching.
extension View {
    func glassCard(cornerRadius: CGFloat = 26) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func glassPill() -> some View {
        self.glassEffect(.regular, in: .capsule)
    }

    func glassTinted(_ color: Color, cornerRadius: CGFloat = 26) -> some View {
        self.glassEffect(.regular.tint(color.opacity(0.4)).interactive(), in: .rect(cornerRadius: cornerRadius))
    }

    /// Circular glass, used for the record hero. The tint stays low so the ring
    /// reads as glass over the backdrop rather than as a painted halo.
    func glassRing(_ color: Color, opacity: Double = 0.14) -> some View {
        self.glassEffect(.regular.tint(color.opacity(opacity)).interactive(), in: .circle)
    }

    func glassTintedPill(_ color: Color) -> some View {
        self.glassEffect(.regular.tint(color.opacity(0.4)).interactive(), in: .capsule)
    }

    /// Hero numerals. Tabular figures so the width never jitters as digits change.
    func heroNumerals(_ size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

struct GlassActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .tint(tint ?? SovoxPalette.ink)
        .buttonStyle(.glass)
    }
}

struct GlassProminentButton: View {
    var title: String
    var systemImage: String?
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .tint(tint)
        .buttonStyle(.glassProminent)
    }
}
