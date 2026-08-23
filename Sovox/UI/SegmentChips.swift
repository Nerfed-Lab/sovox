import SwiftUI

struct SegmentChips: View {
    var segments: [SegmentRecord]
    var activeIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    chip(for: segment)
                }
                if !segments.contains(where: { $0.index == activeIndex }) {
                    activeChip
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var activeChip: some View {
        HStack(spacing: 6) {
            Circle().fill(SovoxPalette.recording).frame(width: 7, height: 7)
            Text("Seg \(activeIndex)")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassTintedPill(SovoxPalette.recording)
    }

    private func chip(for segment: SegmentRecord) -> some View {
        HStack(spacing: 6) {
            switch segment.state {
            case .pending:
                Image(systemName: "clock").font(.caption2)
            case .running:
                ProgressView().controlSize(.mini)
            case .deferred:
                Image(systemName: "thermometer.medium").font(.caption2)
            case .done:
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
            case .empty:
                Image(systemName: "speaker.slash").font(.caption2)
            case .failed:
                Image(systemName: "exclamationmark.triangle").font(.caption2)
            }
            Text("Seg \(segment.index)")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(segment.state.isFailure ? SovoxPalette.paused : SovoxPalette.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPill()
    }
}
