import SwiftUI

struct HistoryDetailView: View {
    var sessionID: String

    @Environment(RecordingStore.self) private var store
    @Environment(RecorderController.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var showGenerate = false
    @State private var copied = false
    @State private var confirmDeleteAll = false

    private var session: RecordingSession? { store.session(id: sessionID) }

    var body: some View {
        ZStack {
            SovoxBackdrop(active: false)
            if let session {
                content(session)
            } else {
                Text("Recording not found").foregroundStyle(SovoxPalette.dim)
            }
        }
        .navigationTitle(session?.displayTitle ?? "Recording")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGenerate) {
            if let session {
                OutputSelectionView(session: session) { showGenerate = false }
            }
        }
    }

    /// Every segment shows its state, and a failure shows why. A transcription
    /// error is never swallowed.
    @ViewBuilder
    private func segmentRow(_ segment: SegmentRecord, in session: RecordingSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: segment.state))
                .font(.footnote)
                .foregroundStyle(tint(for: segment.state))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Segment \(segment.index)").font(.subheadline.weight(.medium))
                    Spacer()
                    Text(segment.state.label)
                        .font(.caption)
                        .foregroundStyle(tint(for: segment.state))
                }
                if let reason = segment.state.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(SovoxPalette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if segment.state.isFailure, session.audioExists(for: segment) {
                Button("Retry") {
                    recorder.retrySegment(sessionID: session.id, index: segment.index)
                }
                .font(.caption.weight(.semibold))
                .tint(SovoxPalette.ok)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }

    /// Names the actual blocker. "Available once transcription finishes" was
    /// wrong when the blocker is a segment that failed and will not finish on
    /// its own.
    private func deleteAudioCaption(_ session: RecordingSession) -> String {
        if session.canDeleteAudio {
            return "Keeps the transcript, notes, title and any to-dos linked to this recording."
        }
        if !session.failedSegments.isEmpty {
            return "One or more segments failed. The audio is still the only copy of those minutes, so retry them first."
        }
        return "Available once transcription finishes. The audio is still the only copy of the untranscribed part."
    }

    private func icon(for state: SegmentState) -> String {
        switch state {
        case .pending: return "clock"
        case .running: return "waveform"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .deferred: return "thermometer.medium"
        }
    }

    private func tint(for state: SegmentState) -> Color {
        switch state {
        case .done: return SovoxPalette.ok
        case .failed: return SovoxPalette.destructive
        case .deferred: return SovoxPalette.paused
        case .pending, .running: return SovoxPalette.dim
        }
    }

    private func content(_ session: RecordingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(session.displayTime)
                    Text(DurationFormat.compact(session.duration))
                    if session.source == .recorded {
                        Text("\(session.segments.count) segments")
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(SovoxPalette.dim)

                if !session.isTranscribed && session.source == .recorded {
                    GlassActionButton(title: "Transcribe now", systemImage: "waveform.badge.magnifyingglass", tint: SovoxPalette.ok) {
                        recorder.retryAllFailed(sessionID: session.id)
                        for segment in session.segments where segment.state != .done {
                            recorder.retrySegment(sessionID: session.id, index: segment.index)
                        }
                    }
                }

                if session.source == .recorded, !session.segments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Segments").font(.headline)
                            Spacer()
                            if !session.failedSegments.isEmpty, session.hasAudio {
                                Button("Retry all failed") {
                                    recorder.retryAllFailed(sessionID: session.id)
                                }
                                .font(.footnote.weight(.semibold))
                                .tint(SovoxPalette.ok)
                            }
                        }
                        ForEach(session.segments) { segment in
                            segmentRow(segment, in: session)
                        }
                    }
                }

                Text(session.stitchedTranscript.isEmpty ? "No transcript yet." : session.stitchedTranscript)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(cornerRadius: 22)

                GlassActionButton(title: copied ? "Copied" : "Copy transcript", systemImage: "doc.on.doc", tint: nil) {
                    UIPasteboard.general.string = session.stitchedTranscript
                    copied = true
                }

                GlassProminentButton(title: "Generate notes", systemImage: "sparkles", tint: SovoxPalette.accent) {
                    showGenerate = true
                }

                if session.audioRemoved {
                    Label("Audio removed, transcript kept", systemImage: "waveform.slash")
                        .font(.footnote)
                        .foregroundStyle(SovoxPalette.dim)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 16)
                }

                let shareable = session.shareableAudioURLs(isRecording: !store.canDelete(session.id))
                if !shareable.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Audio").font(.headline)
                        ForEach(Array(shareable.enumerated()), id: \.offset) { index, url in
                            ShareLink(item: url) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(url.lastPathComponent).font(.subheadline.monospaced())
                                    Spacer()
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            .glassCard(cornerRadius: 18)
                        }
                    }
                }

                VStack(spacing: 10) {
                    if session.hasAudio {
                        GlassActionButton(title: "Delete audio only, frees \(StorageGuard.formatted(bytes: store.audioBytes(of: session)))",
                                          systemImage: "waveform.slash",
                                          tint: nil) {
                            store.deleteAudio(session)
                        }
                        .disabled(!session.canDeleteAudio)
                        .opacity(session.canDeleteAudio ? 1 : 0.5)

                        Text(deleteAudioCaption(session))
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.dim)
                    }

                    if store.canDelete(session.id) {
                        GlassActionButton(title: "Delete everything", systemImage: "trash", tint: SovoxPalette.destructive) {
                            confirmDeleteAll = true
                        }
                    } else {
                        Text("This recording is still running. Stop it before deleting.")
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.dim)
                    }
                }
                .confirmationDialog("Delete everything?",
                                    isPresented: $confirmDeleteAll,
                                    titleVisibility: .visible) {
                    Button("Delete everything", role: .destructive) {
                        store.delete(session)
                        dismiss()
                    }
                    Button("Keep", role: .cancel) {}
                } message: {
                    Text("The audio, the transcript and the title all go. This cannot be undone.")
                }
            }
            .padding(20)
        }
    }
}
