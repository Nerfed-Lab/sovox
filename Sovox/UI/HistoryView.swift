import SwiftUI

struct HistoryView: View {
    @Environment(RecordingStore.self) private var store
    @State private var pendingDelete: RecordingSession?
    @State private var renaming: RecordingSession?
    @State private var renameText = ""
    @State private var showPasteSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop(active: false)
                if store.sessions.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPasteSheet = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil },
                                                  set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let renaming { store.rename(sessionID: renaming.id, to: renameText) }
                    renaming = nil
                }
                Button("Clear", role: .destructive) {
                    if let renaming { store.rename(sessionID: renaming.id, to: "") }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Leave blank to let the AI name it.")
            }
            .sheet(isPresented: $showPasteSheet) {
                PasteTranscriptView { text in
                    _ = store.addPasted(text: text)
                    showPasteSheet = false
                }
            }
            .confirmationDialog("Delete this recording?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete { store.delete(pendingDelete) }
                    pendingDelete = nil
                }
                Button("Keep", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The audio and the transcript both go.")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(SovoxPalette.dim)
            Text("Nothing recorded yet")
                .foregroundStyle(SovoxPalette.dim)
        }
    }

    private var list: some View {
        List {
            ForEach(store.sessions) { session in
                NavigationLink {
                    HistoryDetailView(sessionID: session.id)
                } label: {
                    row(session)
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        renaming = session
                        renameText = session.userTitle ?? ""
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(SovoxPalette.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ session: RecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.hasTitle {
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("\(session.dateLine), \(session.displayTime)")
                    if session.source != .pasted {
                        Text(DurationFormat.compact(session.duration)).monospacedDigit()
                    }
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(SovoxPalette.dim)
            } else {
                HStack(spacing: 8) {
                    Text(session.dateLine)
                        .font(.headline)
                    Text(session.displayTime)
                        .font(.subheadline)
                        .foregroundStyle(SovoxPalette.dim)
                    Spacer()
                    if session.source == .pasted {
                        Image(systemName: "doc.on.clipboard").font(.caption)
                            .foregroundStyle(SovoxPalette.dim)
                    } else {
                        Text(DurationFormat.compact(session.duration))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(SovoxPalette.dim)
                    }
                }
            }
            if session.audioRemoved {
                Label("audio removed", systemImage: "waveform.slash")
                    .font(.caption2)
                    .foregroundStyle(SovoxPalette.dim)
            }
            let preview = TranscriptStitcher.preview(session.stitchedTranscript)
            Text(preview.isEmpty ? "Not transcribed yet" : preview)
                .font(.footnote)
                .foregroundStyle(SovoxPalette.dim)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct PasteTranscriptView: View {
    var onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop(active: false)
                VStack(spacing: 14) {
                    Text("Paste a transcript from anywhere, for example the Notes summary of a recorded call.")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .frame(minHeight: 240)
                        .padding(10)
                        .glassCard(cornerRadius: 20)

                    GlassActionButton(title: "Paste from clipboard", systemImage: "doc.on.clipboard", tint: nil) {
                        text = UIPasteboard.general.string ?? text
                    }

                    GlassProminentButton(title: "Save", systemImage: "checkmark", tint: SovoxPalette.accent) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Paste transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
