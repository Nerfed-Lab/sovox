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
    @State private var previewExpanded = false
    @State private var manualTestNote: String?
    /// Ticked sub steps, kept across launches so a user can stop halfway.
    @State private var checkedSteps: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "sovox.setupChecked") ?? [])

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
                     blurb: "Three actions in Shortcuts. Work down the list and tick each line off. Copy buttons appear only next to values you must reproduce exactly.") {
            VStack(alignment: .leading, spacing: 10) {
                GlassActionButton(title: "Open Shortcuts", systemImage: "arrow.up.forward.app", tint: nil) {
                    if let url = URL(string: "shortcuts://create-shortcut") {
                        UIApplication.shared.open(url)
                    }
                }

                ForEach(groupedSubsteps(for: destination), id: \.0) { group, steps in
                    Text(group.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SovoxPalette.dim)
                        .padding(.top, 6)
                    ForEach(steps) { substep in
                        substepRow(substep, destination: destination)
                    }
                }

                clarification(BridgeShortcutRecipe.pickerClarification)
                clarification(BridgeShortcutRecipe.pathFieldClarification)

                finishedPreview(for: destination)
                manualTestCard(for: destination)
                verifyRow(for: destination)
            }
        }
    }

    private func groupedSubsteps(for destination: AIDestination) -> [(String, [BridgeSubstep])] {
        let all = BridgeShortcutRecipe.substeps(for: destination)
        var order: [String] = []
        var buckets: [String: [BridgeSubstep]] = [:]
        for step in all {
            if buckets[step.group] == nil { order.append(step.group) }
            buckets[step.group, default: []].append(step)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: One control per sub step

    /// A Copy button is attached to `.copyValue` and to nothing else. Guidance
    /// text used to carry one, and a user pasted the sentence "prompt is the
    /// file from action 1" into the model's prompt field.
    private func substepRow(_ substep: BridgeSubstep, destination: AIDestination) -> some View {
        let key = "\(destination.rawValue)-\(substep.number)"
        let done = checkedSteps.contains(key)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if done { checkedSteps.remove(key) } else { checkedSteps.insert(key) }
                persistChecked()
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? SovoxPalette.accent : SovoxPalette.dim)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(substep.number). \(substep.text)")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                substepControl(substep)

                if let position = substep.position {
                    Text(position)
                        .font(.caption2)
                        .foregroundStyle(SovoxPalette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if substep.number == 14 {
                    Text(BridgeShortcutRecipe.nameClarification)
                        .font(.caption2)
                        .foregroundStyle(SovoxPalette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .opacity(done ? 0.55 : 1)
    }

    @ViewBuilder
    private func substepControl(_ substep: BridgeSubstep) -> some View {
        switch substep.kind {
        case .copyValue(let value):
            copyChip(value)
        case .toggleOff(let label):
            togglePill(label, on: false)
        case .toggleOn(let label):
            togglePill(label, on: true)
        case .picker(let path):
            literal(path)
        case .variable:
            Text("Do not type anything here. There is nothing to paste in this field.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SovoxPalette.pauseAmber)
                .fixedSize(horizontal: false, vertical: true)
        case .instruction:
            EmptyView()
        }
    }

    /// Monospaced so a hyphen cannot be mistaken for a dash, and selectable so
    /// the bytes can be checked by hand.
    private func literal(_ value: String) -> some View {
        Text(value)
            .font(.footnote.monospaced())
            .foregroundStyle(SovoxPalette.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyChip(_ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = value
        } label: {
            HStack(spacing: 8) {
                literal(value)
                Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassCard(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }

    private func togglePill(_ label: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            literal(label)
            Text(on ? "ON" : "OFF")
                .font(.caption.weight(.bold))
                .foregroundStyle(on ? SovoxPalette.ok : SovoxPalette.pauseAmber)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 10)
    }

    private func clarification(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(SovoxPalette.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard(cornerRadius: 14)
    }

    private func finishedPreview(for destination: AIDestination) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { previewExpanded },
                                            set: { previewExpanded = $0 })) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(BridgeShortcutRecipe.finishedPreview(for: destination), id: \.self) { row in
                    literal(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text("What this should look like when finished")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SovoxPalette.ink)
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    // MARK: Phase 15f

    private func manualTestCard(for destination: AIDestination) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassActionButton(title: "Prepare a manual test", systemImage: "hand.raised", tint: nil) {
                if handoff.prepareManualTest() {
                    manualTestNote = "Now open Shortcuts, run \(BridgeShortcutRecipe.name(for: destination)) yourself, then come back and tap Check result."
                } else {
                    manualTestNote = "Could not write \(RecordingPaths.pendingPromptFile.lastPathComponent)."
                }
            }
            if let note = manualTestNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(SovoxPalette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if handoff.manualTestArmed {
                GlassActionButton(title: "Check result", systemImage: "arrow.clockwise", tint: nil) {
                    _ = handoff.checkManualResult()
                }
            }
            if let result = handoff.manualTestResult {
                literal(result)
                    .font(.caption.monospaced())
            }
            Text("Running it by hand separates a Shortcut that is wrong from an app that is invoking it wrong.")
                .font(.caption2)
                .foregroundStyle(SovoxPalette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func verifyRow(for destination: AIDestination) -> some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Label(outcome.message,
                          systemImage: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(outcome.isSuccess ? SovoxPalette.accent : SovoxPalette.destructive)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(outcome.causes, id: \.self) { cause in
                        Text("\u{2022} " + cause)
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !outcome.isSuccess {
                        Button("Show me the steps again") {
                            checkedSteps = checkedSteps.filter { !$0.hasPrefix(destination.rawValue) }
                            persistChecked()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
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

    private func persistChecked() {
        UserDefaults.standard.set(Array(checkedSteps), forKey: "sovox.setupChecked")
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
