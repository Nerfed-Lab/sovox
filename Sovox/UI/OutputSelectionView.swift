import SwiftUI

struct OutputSelectionView: View {
    var session: RecordingSession
    var onDone: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(HandoffCoordinator.self) private var handoff
    @Environment(RecordingStore.self) private var store

    @State private var modes: Set<OutputMode> = []
    @State private var destination: AIDestination = .chatgpt
    @State private var loaded = false
    @State private var title = ""
    @State private var selectedCustom: Set<UUID> = []
    @State private var conversationType: ConversationType = .auto

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name (optional)")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.dim)
                    TextField("Leave blank, AI will name it", text: $title)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(14)
                        .glassCard(cornerRadius: 18)
                        .onChange(of: title) { _, new in
                            store.rename(sessionID: session.id, to: new)
                        }
                }

                VStack(spacing: 10) {
                    ForEach(OutputMode.allCases) { mode in
                        checkbox(mode)
                    }
                }

                if !settings.customActions.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(settings.customActions) { action in
                            customCheckbox(action)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Conversation type")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.dim)
                    Picker("Conversation type", selection: $conversationType) {
                        ForEach(ConversationType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: conversationType) { _, new in
                        store.setConversationType(sessionID: session.id, to: new)
                    }
                }

                Picker("Destination", selection: $destination) {
                    ForEach(AIDestination.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                statusLine

                GlassProminentButton(title: "Generate",
                                     systemImage: "sparkles",
                                     tint: SovoxPalette.accent) {
                    settings.defaultOutputs = modes
                    settings.destination = destination
                    handoff.generate(session: store.session(id: session.id) ?? session,
                                     modes: modes,
                                     customActions: settings.customActions.filter { selectedCustom.contains($0.id) },
                                     conversationType: conversationType,
                                     destination: destination,
                                     settings: settings)
                }
                .disabled((modes.isEmpty && selectedCustom.isEmpty) || handoff.isInFlight)
                .opacity(modes.isEmpty && selectedCustom.isEmpty ? 0.5 : 1)

                if handoff.pendingDraft != nil {
                    GlassProminentButton(title: "Open draft in Outlook",
                                         systemImage: "envelope",
                                         tint: SovoxPalette.ok) {
                        Task { await handoff.openPendingDraft() }
                    }
                }

                GlassActionButton(title: "Done", systemImage: "checkmark", tint: nil) {
                    handoff.reset()
                    onDone()
                }
            }
            .padding(20)
        }
        .background(SovoxBackdrop(active: false))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            modes = settings.defaultOutputs
            destination = settings.destination
            title = session.userTitle ?? ""
            selectedCustom = settings.defaultCustomActionIDs
            conversationType = session.conversationType
        }
        .sheet(isPresented: Binding(get: { isSetupNeeded }, set: { if !$0 { handoff.reset() } })) {
            ShortcutSetupView(destination: destination) { handoff.reset() }
        }
    }

    private var isSetupNeeded: Bool {
        if case .needsShortcutSetup = handoff.phase { return true }
        return false
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.hasTitle ? session.displayTitle : "Transcript ready")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("\(DurationFormat.compact(session.duration)), \(session.stitchedTranscript.count) characters")
                .font(.footnote)
                .foregroundStyle(SovoxPalette.dim)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch handoff.phase {
        case .idle:
            EmptyView()
        case .waitingForBridge:
            label("Handing off to \(destination.title)", "arrow.up.forward.app", SovoxPalette.dim)
        case .collectingResult:
            label("Reading the reply", "arrow.down.doc", SovoxPalette.dim)
        case .composed(let subject):
            label(subject, "checkmark.circle.fill", SovoxPalette.ok)
        case .needsShortcutSetup:
            EmptyView()
        case .failed(let message):
            label(message, "exclamationmark.triangle.fill", SovoxPalette.paused)
        }
    }

    private func label(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    private func customCheckbox(_ action: CustomAction) -> some View {
        Button {
            if selectedCustom.contains(action.id) {
                selectedCustom.remove(action.id)
            } else {
                selectedCustom.insert(action.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedCustom.contains(action.id) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selectedCustom.contains(action.id) ? SovoxPalette.accent : SovoxPalette.dim)
                Text(action.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SovoxPalette.ink)
                Spacer()
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
    }

    private func checkbox(_ mode: OutputMode) -> some View {
        Button {
            if modes.contains(mode) {
                if modes.count > 1 { modes.remove(mode) }
            } else {
                modes.insert(mode)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: modes.contains(mode) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(modes.contains(mode) ? SovoxPalette.accent : SovoxPalette.dim)
                Text(mode.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SovoxPalette.ink)
                Spacer()
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
    }
}
