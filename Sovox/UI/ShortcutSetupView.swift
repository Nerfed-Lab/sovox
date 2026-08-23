import SwiftUI

/// Shown when the bridge Shortcut did not run. Lists the exact sub steps rather
/// than a generic failure, and copies the required name to the clipboard.
struct ShortcutSetupView: View {
    var destination: AIDestination
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set up the bridge")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                // Phase 1c. The rename changed the Shortcut name, both file
                // names and the callback URL, so every bridge built before it
                // fails with x-error and would otherwise surface as a generic
                // "not found".
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(SovoxPalette.paused)
                    Text("The bridge Shortcuts changed names in this version. A Shortcut whose name contains a space or a dash no longer matches. Rename yours to the name below, and delete its last action if it opens a URL.")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.ink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassTinted(SovoxPalette.paused, cornerRadius: 18)

                Text("Open Shortcuts, make a new shortcut with these three actions, then name it exactly:")
                    .font(.subheadline)
                    .foregroundStyle(SovoxPalette.dim)

                Button {
                    UIPasteboard.general.string = BridgeShortcutRecipe.name(for: destination)
                    copied = true
                } label: {
                    HStack {
                        Text(BridgeShortcutRecipe.name(for: destination))
                            .font(.body.monospaced().weight(.semibold))
                        Spacer()
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .glassTinted(SovoxPalette.accent, cornerRadius: 18)

                ForEach(BridgeShortcutRecipe.steps(for: destination), id: \.self) { step in
                    HStack(alignment: .top, spacing: 12) {
                        // The step string already carries its own number, and it
                        // is the number the wizard uses. A pill here numbered
                        // them a second time.
                        Text(step)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SovoxPalette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 18)
                }

                Text("sovox-pending.txt is already written. Files, \(RecordingPaths.filesLocation).")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.dim)

                GlassProminentButton(title: "Open Shortcuts", systemImage: "arrow.up.forward.app", tint: SovoxPalette.accent) {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                }

                GlassActionButton(title: "Close", systemImage: "xmark", tint: nil, action: onClose)
            }
            .padding(20)
        }
        .background(SovoxBackdrop(active: false))
    }
}
