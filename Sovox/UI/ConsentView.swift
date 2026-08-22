import SwiftUI

/// Shown full screen before recording starts when the consent reminder is on.
struct ConsentView: View {
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            SovoxBackdrop(accent: SovoxPalette.paused, active: true)
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(SovoxPalette.paused)
                Text("Say it out loud")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Tell the room you are recording before you tap start.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SovoxPalette.dim)
                    .padding(.horizontal, 32)
                Spacer()
                VStack(spacing: 12) {
                    GlassProminentButton(title: "I said it, start", systemImage: "record.circle", tint: SovoxPalette.recording, action: onStart)
                    GlassActionButton(title: "Cancel", systemImage: "xmark", tint: nil, action: onCancel)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
