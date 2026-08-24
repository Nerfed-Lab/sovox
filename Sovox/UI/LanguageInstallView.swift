import SwiftUI

/// Phase 19c. There is no way to deep link into the iOS keyboard settings, so
/// the steps are spelled out one action at a time, the way the bridge wizard
/// does it, and a Verify button re-probes rather than asking the user to trust
/// that it worked.
struct LanguageInstallView: View {
    var identifier: String
    var onReady: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var verdict: String?
    @State private var isReady = false

    private var name: String {
        TranscriptionLocale.displayName(Locale(identifier: identifier))
    }

    private var steps: [String] {
        ["Settings, General, Keyboard, Keyboards, Add New Keyboard",
         "Find and select \(name)",
         "Go back to the main Keyboard page, scroll down, turn on Enable Dictation",
         "Tap Dictation Languages and tick \(name)",
         "Come back here, the language will show as Ready"]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop(active: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Install \(name)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("iOS downloads the offline model when you add the language to dictation. Sovox never transcribes over a network, so the model has to be on the device.")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)

                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.footnote.monospacedDigit().weight(.bold))
                                    .foregroundStyle(SovoxPalette.dim)
                                Text(step)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 14)
                        }

                        GlassActionButton(title: "Open iPhone Settings", systemImage: "gearshape", tint: nil) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }

                        GlassProminentButton(title: "Verify", systemImage: "checkmark.seal", tint: SovoxPalette.accent) {
                            verify()
                        }

                        if let verdict {
                            Text(verdict)
                                .font(.footnote)
                                .foregroundStyle(isReady ? SovoxPalette.ok : SovoxPalette.paused)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 14)
                        }

                        if isReady {
                            GlassActionButton(title: "Use \(name)", systemImage: "checkmark", tint: SovoxPalette.ok) {
                                onReady(identifier)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Three outcomes, and the middle one is the trap: dictation working over a
    /// network says nothing about whether this app can use it.
    private func verify() {
        switch TranscriptionLocale.availability(identifier) {
        case .ready:
            isReady = true
            verdict = "Ready. \(name) works offline on this device."
        case .notUsable:
            isReady = false
            verdict = "\(name) dictation is installed but only works with an internet connection. Sovox needs it offline. Try Airplane Mode and dictate \(name) in Notes to confirm."
        case .needsInstall:
            isReady = false
            verdict = "Not available yet. Check the steps above."
        }
    }
}
