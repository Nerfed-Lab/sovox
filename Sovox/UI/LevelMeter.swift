import SwiftUI

/// In app only. The Live Activity deliberately has no meter, because feeding one
/// would mean pushing updates many times a second and ActivityKit would throttle
/// the activity into silence.
struct LevelMeter: View {
    var level: Float
    var tint: Color
    var barCount: Int = 28

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: 4, height: height(for: index))
            }
        }
        .frame(height: 56)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func normalised(_ index: Int) -> Double {
        // Centre weighted so the meter reads as a waveform rather than a bar chart.
        let mid = Double(barCount - 1) / 2
        let distance = abs(Double(index) - mid) / mid
        let envelope = 1 - pow(distance, 1.6)
        return max(0.06, Double(level) * envelope)
    }

    private func height(for index: Int) -> CGFloat {
        6 + CGFloat(normalised(index)) * 50
    }

    private func fill(for index: Int) -> Color {
        normalised(index) > 0.12 ? tint : tint.opacity(0.22)
    }
}
