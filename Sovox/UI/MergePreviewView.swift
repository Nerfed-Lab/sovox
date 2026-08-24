import SwiftUI

/// Phase 19f debug view. Proves the windowing works, and produces the real size
/// figures the two stage threshold depends on rather than an estimate.
struct MergePreviewView: View {
    @Environment(RecordingStore.self) private var store
    @State private var sessionID: String?

    private var session: RecordingSession? {
        guard let sessionID else { return store.sessions.first { $0.hasMergedReading } }
        return store.session(id: sessionID)
    }

    var body: some View {
        ZStack {
            SovoxBackdrop(active: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Recording", selection: Binding(get: { sessionID ?? session?.id ?? "" },
                                                           set: { sessionID = $0 })) {
                        ForEach(store.sessions.filter(\.hasMergedReading)) { candidate in
                            Text(candidate.displayTitle).tag(candidate.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let session {
                        let merged = session.mergedTranscript
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(session.mergedWindowCount) windows")
                            Text("\(merged.count) merged characters")
                            Text("single reading is \(session.stitchedTranscript.count) characters")
                            Text(merged.count > StagedGeneration.threshold
                                 ? "over the \(StagedGeneration.threshold) threshold, generation runs in two stages"
                                 : "under the \(StagedGeneration.threshold) threshold, one call")
                                .foregroundStyle(merged.count > StagedGeneration.threshold
                                                 ? SovoxPalette.pauseAmber : SovoxPalette.ok)
                        }
                        .font(.footnote.monospaced())
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 16)

                        ForEach(session.segments.sorted(by: { $0.index < $1.index })) { segment in
                            if segment.secondaryFailed == true {
                                Label("Segment \(segment.index): second pass did not run, primary only",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(SovoxPalette.pauseAmber)
                            }
                            ForEach(segment.mergedWindows) { window in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(TranscriptMerge.timestamp(window.start)) to \(TranscriptMerge.timestamp(window.end))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(SovoxPalette.dim)
                                    Text("EN: \(window.primary)").font(.footnote)
                                    Text("HI: \(window.secondary)").font(.footnote)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glassCard(cornerRadius: 14)
                            }
                        }
                    } else {
                        Text("No recording has two readings yet. Turn on Also transcribe in, then record something.")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Merge preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
