import SwiftUI

/// Phase 19a on the device that matters. The simulator answers a different
/// question, so this exists to be read on the phone and pasted back.
struct SpeechCapabilityView: View {
    @Environment(AppSettings.self) private var settings
    @State private var report: SpeechCapabilityReport?
    @State private var running = false
    @State private var copied = false

    var body: some View {
        ZStack {
            SovoxBackdrop(active: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report {
                        tierCard(report)
                        detail(report)
                        GlassActionButton(title: copied ? "Copied" : "Copy full report",
                                          systemImage: copied ? "checkmark" : "doc.on.doc",
                                          tint: nil) {
                            UIPasteboard.general.string = report.plainText
                            copied = true
                        }
                    } else {
                        Text(running ? "Probing" : "Nothing yet")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)
                    }

                    GlassActionButton(title: "Probe again", systemImage: "arrow.clockwise", tint: nil) {
                        Task { await probe() }
                    }

                    Text("Reads capability only. No audio is sent anywhere and no recognition request is made, so running this cannot reach a server.")
                        .font(.caption2)
                        .foregroundStyle(SovoxPalette.dim)
                }
                .padding(20)
            }
        }
        .navigationTitle("Speech capability")
        .navigationBarTitleDisplayMode(.inline)
        .task { if report == nil { await probe() } }
    }

    private func probe() async {
        running = true
        copied = false
        report = await SpeechCapabilityProbe.run(primary: settings.transcriptionLocale)
        running = false
    }

    private func tierCard(_ report: SpeechCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.tier.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(report.tier == .three ? SovoxPalette.paused : SovoxPalette.accent)
            Text(report.tier.summary)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if report.secondaryIsOnlineOnly {
                Text("Hindi dictation is installed but only works with an internet connection. Sovox needs it offline, so this counts as Tier 3. To confirm: turn on Airplane Mode and try dictating Hindi in Notes.")
                    .font(.caption)
                    .foregroundStyle(SovoxPalette.paused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private func detail(_ report: SpeechCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.plainText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 18)
    }
}
