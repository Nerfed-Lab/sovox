import SwiftUI
import AVFoundation
import Speech
import ActivityKit
import UserNotifications

/// Phase 10.
///
/// Shortcuts cannot be created programmatically, no iOS API allows it. The goal
/// here is to eliminate typing and typos: every value the user must reproduce
/// exactly has its own Copy button, and Verify proves the round trip rather
/// than leaving them to find out during a real meeting.
struct SetupWizardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffCoordinator.self) private var handoff
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var copied: String?
    /// Notification status is async, so it is resolved into state rather than
    /// awaited inside the view builder.
    @State private var notificationsOn = false
    @State private var permissionsTick = 0

    private let lastStep = 4

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ZStack {
                SovoxBackdrop()
                TabView(selection: $step) {
                    detailsStep(settings: settings).tag(0)
                    permissionsStep.tag(1)
                    bridgeStep(for: .chatgpt).tag(2)
                    bridgeStep(for: .claude).tag(3)
                    actionButtonStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(step == lastStep ? "Done" : "Skip") {
                        if step == lastStep {
                            settings.setupCompleted = true
                            dismiss()
                        } else {
                            step += 1
                        }
                    }
                }
            }
        }
    }

    // MARK: Step 1

    private func detailsStep(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return stepScaffold(title: "About you",
                            blurb: "Your name is excluded from the attendees the AI infers. Your work email prefills the Outlook draft.") {
            VStack(spacing: 12) {
                TextField("Full name", text: $settings.fullName)
                    .textContentType(.name)
                    .padding(14)
                    .glassCard(cornerRadius: 16)
                TextField("Work email", text: $settings.workEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .glassCard(cornerRadius: 16)
            }
        }
    }

    // MARK: Step 2

    private var permissionsStep: some View {
        stepScaffold(title: "Permissions",
                     blurb: "Sovox needs all four. Nothing leaves your phone.") {
            VStack(spacing: 10) {
                PermissionRow(title: "Microphone",
                              granted: AVAudioApplication.shared.recordPermission == .granted) {
                    _ = await RecorderController.shared.requestMicrophone()
                    permissionsTick += 1
                }
                PermissionRow(title: "Speech recognition",
                              granted: SFSpeechRecognizer.authorizationStatus() == .authorized) {
                    _ = await SegmentTranscriber.requestAuthorisation()
                    permissionsTick += 1
                }
                PermissionRow(title: "Notifications", granted: notificationsOn) {
                    _ = await Notifier.requestAuthorisation()
                    notificationsOn = await Notifier.settingsAuthorised()
                }
                PermissionRow(title: "Live Activities",
                              granted: ActivityAuthorizationInfo().areActivitiesEnabled,
                              openSettingsInstead: true) {}
            }
            .id(permissionsTick)
            .task { notificationsOn = await Notifier.settingsAuthorised() }
        }
    }


    // MARK: Steps 3 and 4

    private func bridgeStep(for destination: AIDestination) -> some View {
        stepScaffold(title: "\(destination.title) bridge",
                     blurb: "Open Shortcuts, build these four actions, and name it exactly. Copy each value rather than typing it.") {
            VStack(spacing: 10) {
                copyRow(label: "Name", value: BridgeShortcutRecipe.name(for: destination))
                ForEach(Array(BridgeShortcutRecipe.setupRows(for: destination).enumerated()), id: \.offset) { index, row in
                    copyRow(label: "Action \(index + 1), \(row.action)", value: row.value)
                }

                GlassActionButton(title: "Open Shortcuts", systemImage: "arrow.up.forward.app", tint: nil) {
                    // create-shortcut lands the user on a new empty shortcut.
                    if let url = URL(string: "shortcuts://create-shortcut") {
                        UIApplication.shared.open(url)
                    }
                }

                verifyRow(for: destination)
            }
        }
    }

    @ViewBuilder
    private func verifyRow(for destination: AIDestination) -> some View {
        @Bindable var settings = settings
        VStack(spacing: 8) {
            GlassProminentButton(title: "Verify \(destination.title) bridge",
                                 systemImage: "checkmark.seal",
                                 tint: SovoxPalette.accent) {
                handoff.verifyBridge(destination: destination)
            }

            if settings.isBridgeVerified(destination) {
                Label("Verified", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.accent)
            }

            if handoff.verifyingDestination == destination, let outcome = handoff.verifyOutcome {
                Label(outcome.message,
                      systemImage: outcome == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(outcome == .success ? SovoxPalette.accent : SovoxPalette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(cornerRadius: 14)
            }
        }
    }

    // MARK: Step 5

    private var actionButtonStep: some View {
        stepScaffold(title: "Action Button",
                     blurb: "Optional. There is no public API to deep link into this screen, so it has to be done by hand.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings, Action Button, Shortcuts, then pick Sovox: Toggle Sovox.")
                    .font(.callout)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 16)

                GlassActionButton(title: "Opens Settings, navigate to Action Button from there",
                                  systemImage: "gearshape",
                                  tint: nil) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: Scaffolding

    private func stepScaffold<Content: View>(title: String,
                                             blurb: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(blurb).font(.footnote).foregroundStyle(SovoxPalette.dim)
                content()
            }
            .padding(20)
            .padding(.bottom, 60)
        }
    }

    private func copyRow(label: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = value
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(SovoxPalette.dim)
                    Text(value).font(.footnote.monospaced()).foregroundStyle(SovoxPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(SovoxPalette.accent)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }
}

struct PermissionRow: View {
    var title: String
    var granted: Bool
    var openSettingsInstead: Bool = false
    var grant: () async -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? SovoxPalette.accent : SovoxPalette.dim)
            Text(title).foregroundStyle(SovoxPalette.ink)
            Spacer()
            if !granted {
                Button(openSettingsInstead ? "Settings" : "Grant") {
                    if openSettingsInstead {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task { await grant() }
                    }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }
}
