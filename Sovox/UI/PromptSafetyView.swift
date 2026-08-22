#if DEBUG
import SwiftUI

struct PromptSafetyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffCoordinator.self) private var handoff
    @State private var harness = PromptSafetyHarness()

    var body: some View {
        ZStack {
            SovoxBackdrop()
            List {
                Section {
                    Text("Runs the adversarial cases through the real bridge against a fixed sample transcript, then checks the reply still opens with SUBJECT then ATTENDEES. Layer 1 proves the prompt is built correctly, only this proves the model behaves. One round trip per case.")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.dim)
                }

                ForEach(PromptSafetyHarness.cases) { probe in
                    let outcome = harness.outcome(for: probe)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(probe.id)  \(probe.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(outcome.label)
                                .font(.caption.weight(.bold).monospaced())
                                .foregroundStyle(tint(outcome))
                        }
                        if let detail = outcome.detail {
                            Text(detail).font(.caption).foregroundStyle(SovoxPalette.dim)
                        }
                        Button("Run \(probe.id)") { run(probe) }
                            .font(.footnote.weight(.semibold))
                            .disabled(harness.running != nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Prompt safety")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: handoff.pendingSafetyResponse) { _, _ in
            guard let raw = handoff.consumeSafetyResponse(), let probe = harness.running else { return }
            harness.record(raw, for: probe)
        }
    }

    private func tint(_ outcome: PromptSafetyHarness.Outcome) -> Color {
        switch outcome {
        case .passed: return SovoxPalette.accent
        case .failed: return SovoxPalette.destructive
        case .running, .notRun: return SovoxPalette.dim
        }
    }

    private func run(_ probe: PromptSafetyHarness.Case) {
        guard let prompt = harness.prompt(for: probe) else {
            harness.results[probe.id] = .failed("The sanitiser rejected this case before it could be sent.")
            return
        }
        harness.begin(probe)
        handoff.runSafetyProbe(prompt: prompt, destination: settings.destination)
    }
}
#endif
