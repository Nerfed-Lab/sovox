import SwiftUI

/// Phase 15h. Shown once to a user who already built a bridge under the old
/// names. Three edits fix it, so the card leads with those rather than sending
/// them back through the whole wizard.
struct BridgeMigrationView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showWizard = false
    @State private var copied: String?

    private var edits: [(String, String?)] {
        [
            ("Rename your Shortcut to", BridgeShortcutRecipe.name(for: settings.destination)),
            ("Delete the last action, the one that opens a URL. Sovox comes back on its own now.", nil),
            ("Check Action 2's prompt field holds only the blue File variable, with no typed text.", nil)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop(active: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("The bridge Shortcuts have changed")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Names are letters only now, and the fourth action is gone. Three edits in Shortcuts, not a rebuild.")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)

                        ForEach(Array(edits.enumerated()), id: \.offset) { index, edit in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). \(edit.0)")
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let value = edit.1 {
                                    Button {
                                        UIPasteboard.general.string = value
                                        copied = value
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(value)
                                                .font(.footnote.monospaced())
                                                .textSelection(.enabled)
                                            Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                                                .foregroundStyle(SovoxPalette.accent)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .glassCard(cornerRadius: 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 16)
                        }

                        GlassActionButton(title: "Show me the full steps instead",
                                          systemImage: "list.number",
                                          tint: nil) {
                            showWizard = true
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Bridge update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        settings.bridgeMigrationPending = false
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showWizard) { SetupWizardView() }
        }
    }
}
