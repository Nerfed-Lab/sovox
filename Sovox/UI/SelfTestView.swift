import SwiftUI

struct SelfTestView: View {
    @State private var test = SelfTest()
    @Environment(RecorderController.self) private var recorder

    var body: some View {
        ZStack {
            SovoxBackdrop(active: false)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(test.rows) { row in
                        rowView(row)
                    }

                    if test.rows.isEmpty && test.isRunning {
                        ProgressView().padding(.top, 40)
                    }

                    Divider().padding(.vertical, 8)

                    smokeCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Self Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await test.runAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if test.rows.isEmpty { await test.runAll() }
        }
    }

    private func rowView(_ row: SelfTestRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.passed == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(row.passed == true ? SovoxPalette.ok : SovoxPalette.destructive)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(row.passed == true ? "PASS" : "FAIL")
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(row.passed == true ? SovoxPalette.ok : SovoxPalette.destructive)
                }
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.dim)
                if row.fix != .none {
                    Button(fixTitle(row.fix)) { apply(row.fix) }
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private var smokeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("60 second smoke test")
                .font(.headline)
            Text("Records for a minute with a twenty second segment interval, rolls the segments, transcribes them, stitches and checks for a gap at each boundary.")
                .font(.footnote)
                .foregroundStyle(SovoxPalette.dim)

            if test.smokeRunning {
                ProgressView(value: test.smokeProgress)
                    .progressViewStyle(.linear)
                    .tint(SovoxPalette.accent)
            }

            if let summary = test.smokeSummary {
                Text(summary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(SovoxPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(cornerRadius: 14)
            }

            GlassProminentButton(title: test.smokeRunning ? "Running" : "Run smoke test",
                                 systemImage: "waveform.badge.magnifyingglass",
                                 tint: SovoxPalette.accent) {
                Task { await test.runSmokeTest() }
            }
            .disabled(test.smokeRunning || recorder.isRecordingNow)

            if recorder.isRecordingNow {
                Text("Stop the current recording first.")
                    .font(.caption)
                    .foregroundStyle(SovoxPalette.paused)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func fixTitle(_ fix: SelfTestFix) -> String {
        switch fix {
        case .none: return ""
        case .openAppSettings: return "Open Sovox settings"
        case .requestSpeech: return "Ask again"
        case .requestMicrophone: return "Ask again"
        case .openShortcuts: return "Open Shortcuts"
        case .getOutlook: return "Get Outlook"
        case .openDictationHelp: return "Open iPhone settings"
        }
    }

    private func apply(_ fix: SelfTestFix) {
        switch fix {
        case .none:
            break
        case .openAppSettings, .openDictationHelp:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .requestSpeech:
            Task {
                _ = await SegmentTranscriber.requestAuthorisation()
                await test.runAll()
            }
        case .requestMicrophone:
            Task {
                _ = await recorder.requestMicrophone()
                await test.runAll()
            }
        case .openShortcuts:
            if let url = URL(string: "shortcuts://") {
                UIApplication.shared.open(url)
            }
        case .getOutlook:
            // itms-apps hands straight to the App Store app. No networking code
            // is involved and the string carries no web scheme.
            if let url = URL(string: "itms-apps://apps.apple.com/app/id951937596") {
                UIApplication.shared.open(url)
            }
        }
    }
}
