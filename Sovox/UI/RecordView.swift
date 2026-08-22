import SwiftUI

struct RecordView: View {
    @Environment(RecorderController.self) private var recorder
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingStore.self) private var store
    @Environment(HandoffCoordinator.self) private var handoff

    @State private var showConsent = false
    @State private var showWizard = false
    @Namespace private var glass

    var body: some View {
        @Bindable var recorder = recorder

        ZStack {
            SovoxBackdrop(accent: accent, active: recorder.state != .idle)

            switch recorder.state {
            case .idle:
                idle
            case .recording, .paused:
                live
            case .transcribing:
                transcribing
            case .ready:
                ready
            }
        }
        .sheet(isPresented: $showWizard) { SetupWizardView() }
        .fullScreenCover(isPresented: $showConsent) {
            ConsentView(onStart: {
                showConsent = false
                Task { await recorder.start() }
            }, onCancel: { showConsent = false })
        }
        .alert("Sovox", isPresented: Binding(get: { recorder.alertMessage != nil },
                                               set: { if !$0 { recorder.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.alertMessage ?? "")
        }
    }

    private var accent: Color {
        switch recorder.state {
        case .paused: return SovoxPalette.paused
        case .recording: return SovoxPalette.recording
        default: return SovoxPalette.recording
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 26) {
            if settings.needsBridgeSetup {
                Button {
                    showWizard = true
                } label: {
                    Label("Bridge not set up, notes cannot be generated. Finish setup.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SovoxPalette.pauseAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .glassTinted(SovoxPalette.pauseAmber, cornerRadius: 16)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Spacer()

            GlassEffectContainer(spacing: 0) {
                Button {
                    if settings.announceConsent {
                        showConsent = true
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [SovoxPalette.recordHighlight,
                                                          SovoxPalette.recording],
                                                 center: UnitPoint(x: 0.5, y: 0.3),
                                                 startRadius: 4,
                                                 endRadius: 140))
                            .overlay(Circle().strokeBorder(.white.opacity(0.24), lineWidth: 1))
                            .frame(width: 168, height: 168)
                            .shadow(color: SovoxPalette.recording.opacity(0.5), radius: 32, y: 12)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(22)
                }
                .buttonStyle(.plain)
                .glassRing(SovoxPalette.recording)
                .accessibilityLabel("Start recording")
            }

            if let last = store.latest {
                Text("\(last.dateLine), \(last.displayTime), \(DurationFormat.compact(last.duration))")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.dim)
            } else {
                Text("No recordings yet")
                    .font(.footnote)
                    .foregroundStyle(SovoxPalette.dim)
            }

            if handoff.isInFlight {
                VStack(spacing: 6) {
                    Label("Waiting on \(settings.destination.title)", systemImage: "hourglass")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SovoxPalette.pauseAmber)
                    Button("Cancel and unlock") { handoff.cancelInFlight() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 16)
                .padding(.horizontal, 20)
            }

            if let notice = recorder.liveActivityNotice {
                Text(notice)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SovoxPalette.paused)
                    .padding(14)
                    .glassCard(cornerRadius: 18)
                    .padding(.horizontal, 28)
            }

            Spacer()
        }
    }

    // MARK: Live

    private var live: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(DurationFormat.clock(recorder.clock.elapsed(at: context.date)))
                    .heroNumerals(68)
                    .foregroundStyle(SovoxPalette.ink)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.state == .paused ? SovoxPalette.paused : SovoxPalette.recording)
                    .frame(width: 9, height: 9)
                Text(recorder.state == .paused ? "Paused" : "Recording")
                    .font(.subheadline.weight(.semibold))
                if let roll = recorder.nextRollDate, recorder.state == .recording {
                    Text("rolls \(roll.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(SovoxPalette.dim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassPill()

            LevelMeter(level: recorder.state == .paused ? 0 : recorder.level,
                       tint: recorder.state == .paused ? SovoxPalette.paused : SovoxPalette.recording)
                .padding(.horizontal, 24)

            SegmentChips(segments: recorder.currentSession?.segments ?? [],
                         activeIndex: recorder.segmentIndex)
                .padding(.horizontal, 20)

            Spacer()

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    if recorder.state == .recording {
                        GlassActionButton(title: "Pause", systemImage: "pause.fill", tint: SovoxPalette.paused) {
                            recorder.pause()
                        }
                    } else {
                        GlassActionButton(title: "Resume", systemImage: "play.fill", tint: SovoxPalette.ok) {
                            recorder.resume()
                        }
                    }
                    GlassProminentButton(title: "Stop", systemImage: "stop.fill", tint: SovoxPalette.recording) {
                        recorder.stop()
                    }
                }
            }
            .padding(.horizontal, 22)

            if let notice = recorder.liveActivityNotice {
                Text(notice)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SovoxPalette.paused)
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                    .padding(.horizontal, 24)
            } else if settings.showsBackgroundHint {
                VStack(spacing: 4) {
                    Text("You can leave the app, recording continues.")
                    Text("Works best flat on the table, centre of the group.")
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(SovoxPalette.dim)
            }

            if recorder.remainingMinutes > 0 {
                Text(DurationFormat.spaceRemaining(minutes: recorder.remainingMinutes))
                    .font(.caption)
                    .foregroundStyle(SovoxPalette.dim)
            }

            Spacer(minLength: 18)
        }
    }

    // MARK: Transcribing

    private var transcribing: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Transcribing")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            ProgressView(value: recorder.transcriptionProgress)
                .progressViewStyle(.linear)
                .tint(SovoxPalette.accent)
                .padding(.horizontal, 40)

            if isThermallyDeferred {
                Label("Transcription paused (device warm)", systemImage: "thermometer.medium")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SovoxPalette.paused)
                    .padding(10)
                    .glassCard(cornerRadius: 14)
            }

            Text("\(doneCount) of \(totalCount) segments")
                .font(.subheadline)
                .foregroundStyle(SovoxPalette.dim)

            SegmentChips(segments: recorder.currentSession?.segments ?? [],
                         activeIndex: recorder.segmentIndex)
                .padding(.horizontal, 20)

            GlassActionButton(title: "Leave this running", systemImage: "arrow.down.right.and.arrow.up.left", tint: nil) {
                recorder.dismissTranscribingScreen()
            }
            .padding(.horizontal, 40)

            Text("Transcription continues and notifies you when it is ready.")
                .font(.caption)
                .foregroundStyle(SovoxPalette.dim)

            Spacer()
        }
    }

    private var isThermallyDeferred: Bool {
        (recorder.currentSession?.segments ?? []).contains { if case .deferred = $0.state { return true } else { return false } }
    }

    private var doneCount: Int {
        (recorder.currentSession?.segments ?? []).filter { $0.state.isTerminal }.count
    }

    private var totalCount: Int {
        max(1, (recorder.currentSession?.segments ?? []).count)
    }

    // MARK: Ready

    @ViewBuilder
    private var ready: some View {
        if let session = recorder.currentSession {
            OutputSelectionView(session: session, onDone: { recorder.returnToIdle() })
        } else {
            idle
        }
    }
}
