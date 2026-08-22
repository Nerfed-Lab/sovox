import SwiftUI

struct AskView: View {
    @Environment(RecordingStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffCoordinator.self) private var handoff
    @State private var ask = AskSession.shared
    @State private var question = ""
    @State private var showSources = false

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                VStack(spacing: 0) {
                    sourcesRow
                    guardBanner
                    thread
                    composer
                }
            }
            .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { ask.clear() }
                        .disabled(ask.turns.isEmpty)
                }
            }
            .sheet(isPresented: $showSources) {
                AskSourcesSheet(selected: $ask.selectedIDs)
            }
            .onChange(of: handoff.pendingAskAnswer) { _, _ in
                drainAnswer()
            }
            // Also drained on appear, so an answer that arrived while this tab
            // had never been created is still delivered after a relaunch.
            .task { drainAnswer() }
        }
    }

    // MARK: Sources

    private var selectedSessions: [RecordingSession] {
        store.sessions.filter { ask.selectedIDs.contains($0.id) && !$0.stitchedTranscript.isEmpty }
    }

    private var sources: [AskPromptBuilder.Source] {
        selectedSessions.map {
            AskPromptBuilder.Source(title: $0.displayTitle,
                                    date: $0.dateLine,
                                    transcript: $0.stitchedTranscript)
        }
    }

    private var characterCount: Int {
        AskPromptBuilder.combinedCharacterCount(sources)
    }

    private var verdict: AskContextGuard.Verdict {
        AskContextGuard.verdict(characterCount: characterCount)
    }

    private var sourcesRow: some View {
        Button {
            showSources = true
        } label: {
            HStack {
                Label("Sources", systemImage: "text.document")
                Spacer()
                Text("\(selectedSessions.count) selected")
                    .foregroundStyle(SovoxPalette.dim)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(SovoxPalette.dim)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var guardBanner: some View {
        switch verdict {
        case .ok:
            EmptyView()
        case .warn(let message):
            banner(message, systemImage: "exclamationmark.triangle.fill", tint: SovoxPalette.paused)
        case .block(let message):
            banner(message, systemImage: "hand.raised.fill", tint: SovoxPalette.destructive)
        }
    }

    private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if ask.turns.isEmpty {
                        Text("Pick some recordings, then ask a question about them.")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)
                            .padding(.top, 24)
                    }
                    ForEach(ask.turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.question)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(12)
                                .glassTinted(SovoxPalette.accent, cornerRadius: 16)
                            Text(turn.answer)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glassCard(cornerRadius: 16)
                        }
                        .id(turn.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: ask.turns.count) { _, _ in
                if let last = ask.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: Composer

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sources.isEmpty
            && !verdict.blocks
            && !handoff.isInFlight
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask a question", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .glassCard(cornerRadius: 18)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? SovoxPalette.accent : SovoxPalette.dim)
            }
            .disabled(!canSend)
        }
        .padding(16)
    }

    private func drainAnswer() {
        guard let result = handoff.consumeAskAnswer() else { return }
        ask.append(question: result.question, answer: result.answer)
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let prompt = AskPromptBuilder.build(question: text, sources: sources, history: ask.turns)
        handoff.ask(question: text, prompt: prompt, destination: settings.destination)
        question = ""
    }
}

/// Only recordings with a transcript can be selected. Selecting one without a
/// transcript would silently contribute nothing.
struct AskSourcesSheet: View {
    @Binding var selected: Set<String>
    @Environment(RecordingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var eligible: [RecordingSession] {
        store.sessions.filter { !$0.stitchedTranscript.isEmpty }
    }

    private var filtered: [RecordingSession] {
        guard !search.isEmpty else { return eligible }
        return eligible.filter { $0.displayTitle.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                List {
                    if eligible.isEmpty {
                        Text("No transcribed recordings yet.")
                            .foregroundStyle(SovoxPalette.dim)
                    }
                    ForEach(filtered) { session in
                        Button {
                            if selected.contains(session.id) { selected.remove(session.id) }
                            else { selected.insert(session.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(session.id) ? SovoxPalette.accent : SovoxPalette.dim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.displayTitle).foregroundStyle(SovoxPalette.ink)
                                    Text("\(session.dateLine), \(session.stitchedTranscript.count) characters")
                                        .font(.caption)
                                        .foregroundStyle(SovoxPalette.dim)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $search)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Select all") { selected = Set(eligible.map(\.id)) }
                        .disabled(eligible.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("None") { selected.removeAll() }
                        .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
