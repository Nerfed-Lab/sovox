import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingStore.self) private var store
    @Environment(RecorderController.self) private var recorder
    @State private var confirmBulkDelete = false
    /// Re-probed on every appearance, per 15k.
    @State private var modelApps: Set<AIDestination> = []
    @State private var wizardBridge: AIDestination?
    /// Re-resolved on appearance: installing a dictation language does not tell
    /// the app anything.
    @State private var secondaryTier: SpeechTier = .three
    @State private var confirmAudioDelete = false
    @State private var showWizard = false

    /// Says exactly what will happen instead, because the alternative to a
    /// fallback is every segment of every recording failing permanently, and
    /// the alternative to saying so is a transcript quietly made by a different
    /// language model.
    private var localeFallbackNote: String {
        let asked = TranscriptionLocale.normalise(settings.transcriptionLocale)
        let used = TranscriptionLocale.usable(asked)
        let head = "Turn on Settings, General, Keyboard, Enable Dictation and pick this language. iOS downloads the model then."
        guard used != asked else {
            return head + " Until then transcription of new recordings will fail."
        }
        return head + " Until then Sovox transcribes with \(TranscriptionLocale.displayName(Locale(identifier: used))) instead, which is worse for accents this language handles better."
    }

    /// Phase 15k. Three states, re-probed on every appearance, because a
    /// segmented control that lets you pick a model you have not set up is a
    /// selection that fails later with nothing to act on.
    @ViewBuilder
    private func handoffRow(_ option: AIDestination, settings: AppSettings) -> some View {
        // Unknown counts as installed, per destination: never grey out a model
        // on the strength of a probe that has never been proven for it.
        let installed = modelApps.contains(option) || !ModelAppProbe.schemeConfirmed(option)
        let configured = installed && settings.isBridgeVerified(option)
        let selected = settings.destination == option

        Button {
            guard configured else {
                if installed { wizardBridge = option }
                return
            }
            settings.destination = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected && configured ? SovoxPalette.accent : SovoxPalette.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .foregroundStyle(installed ? SovoxPalette.ink : SovoxPalette.dim)
                    if !installed {
                        Text("Install the \(option.title) app to use this")
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.dim)
                    } else if !configured {
                        Text("Needs setup")
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.pauseAmber)
                    }
                }
                Spacer()
                if installed && !configured {
                    Text("Set up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SovoxPalette.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!installed)
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ZStack {
                SovoxBackdrop(active: false)
                Form {
                    Section("You") {
                        TextField("Full name", text: $settings.fullName)
                            .textContentType(.name)
                        TextField("Work email", text: $settings.workEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Section("Hand off") {
                        ForEach(AIDestination.allCases) { option in
                            handoffRow(option, settings: settings)
                        }
                    }

                    Section("Transcription") {
                        NavigationLink {
                            TranscriptionLanguageView()
                        } label: {
                            HStack {
                                Text("Language")
                                Spacer()
                                Text(TranscriptionLocale.displayName(Locale(identifier: settings.transcriptionLocale)))
                                    .foregroundStyle(SovoxPalette.dim)
                            }
                        }
                        // The one that bit: a language selected before this
                        // check existed, or installed and then found to be
                        // online only, still has to be recoverable in one tap.
                        if TranscriptionLocale.availability(settings.transcriptionLocale) == .notUsable {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("This language needs an internet connection",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(SovoxPalette.paused)
                                Text("Sovox only transcribes on the device, so recordings in this language come back with no text at all.")
                                    .font(.caption)
                                    .foregroundStyle(SovoxPalette.dim)
                                Button("Switch to \(TranscriptionLocale.displayName(Locale(identifier: TranscriptionLocale.usable(nil))))") {
                                    settings.transcriptionLocale = TranscriptionLocale.usable(nil)
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        }
                        Toggle("Also transcribe in", isOn: $settings.dualLanguage)
                            .disabled(secondaryTier == .three)
                        if settings.dualLanguage {
                            NavigationLink {
                                TranscriptionLanguageView(selecting: .secondary)
                            } label: {
                                HStack {
                                    Text("Secondary language")
                                    Spacer()
                                    Text(settings.secondaryLocale.isEmpty
                                         ? "None"
                                         : TranscriptionLocale.displayName(Locale(identifier: settings.secondaryLocale)))
                                        .foregroundStyle(SovoxPalette.dim)
                                }
                            }
                        }
                        Text(secondaryTier == .three
                             ? "Hindi transcription isn't available on this device."
                             : "Transcribes twice and lets the AI decide. Slower, and uses more of the model's context.")
                            .font(.caption)
                            .foregroundStyle(SovoxPalette.dim)

                        if !TranscriptionLocale.isOnDeviceReady(settings.transcriptionLocale) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("On device model not installed for this language",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(SovoxPalette.pauseAmber)
                                Text(localeFallbackNote)
                                    .font(.caption)
                                    .foregroundStyle(SovoxPalette.dim)
                                Button("Open iPhone Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        }
                    }

                    Section("Diagnostics") {
                        NavigationLink {
                            SpeechCapabilityView()
                        } label: {
                            Label("Speech capability", systemImage: "waveform.badge.magnifyingglass")
                        }
                    }

                    Section("Appearance") {
                        Picker("Theme", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Recording") {
                        Picker("Segment length", selection: $settings.segmentMinutes) {
                            ForEach(AppSettings.segmentOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Announce consent", isOn: $settings.announceConsent)

                        if recorder.isRecordingNow {
                            Text("Applies from the next segment roll.")
                                .font(.footnote)
                                .foregroundStyle(SovoxPalette.dim)
                        }
                    }

                    Section("Storage") {
                        LabeledContent("Used", value: StorageGuard.formatted(bytes: store.storageBytes))
                        LabeledContent("Audio", value: StorageGuard.formatted(bytes: store.totalAudioBytes))
                        LabeledContent("Recordings", value: "\(store.sessions.count)")
                        Button("Delete all audio, keep transcripts") {
                            confirmAudioDelete = true
                        }
                        .disabled(store.deletableAudioBytes == 0)
                        Button("Delete all recordings", role: .destructive) {
                            confirmBulkDelete = true
                        }
                    }

                    Section("Outputs") {
                        NavigationLink {
                            CustomActionsView()
                        } label: {
                            LabeledContent("Custom actions",
                                           value: "\(settings.customActions.count)")
                        }
                    }

                    Section("Setup") {
                        Button {
                            showWizard = true
                        } label: {
                            HStack {
                                Label("Setup", systemImage: "wand.and.stars")
                                Spacer()
                                if settings.needsBridgeSetup {
                                    Text("unverified").font(.caption).foregroundStyle(SovoxPalette.pauseAmber)
                                }
                            }
                        }
                        NavigationLink {
                            ShortcutSetupView(destination: settings.destination) {}
                        } label: {
                            Label("Bridge Shortcuts", systemImage: "link")
                        }
                    }

                    Section {
                        NavigationLink {
                            SelfTestView()
                        } label: {
                            Label("Self Test", systemImage: "checkmark.seal")
                        }
                    }

                    #if DEBUG
                    Section("Developer") {
                        NavigationLink {
                            PromptSafetyView()
                        } label: {
                            Label("Prompt safety test", systemImage: "shield.lefthalf.filled")
                        }
                        NavigationLink {
                            MergePreviewView()
                        } label: {
                            Label("Merge preview", systemImage: "square.split.2x1")
                        }
                    }
                    #endif

                    Section("About") {
                        LabeledContent("Version", value: AppVersion.display)
                    }

                    Section {
                        Text("Nothing leaves this phone. There is no networking code in this app.")
                            .font(.footnote)
                            .foregroundStyle(SovoxPalette.dim)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .onChange(of: settings.segmentMinutes) { _, _ in
                recorder.applySegmentLength()
            }
            .sheet(isPresented: $showWizard) { SetupWizardView() }
            .sheet(item: $wizardBridge) { bridge in SetupWizardView(startingBridge: bridge) }
            .onAppear {
                modelApps = Set(AIDestination.allCases.filter { ModelAppProbe.isInstalled($0) })
                Task { secondaryTier = await SpeechCapabilityProbe.run(primary: settings.transcriptionLocale,
                                                                       secondary: AppSettings.defaultSecondaryLocale).tier }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all audio?",
                                isPresented: $confirmAudioDelete,
                                titleVisibility: .visible) {
                Button("Delete audio, frees \(StorageGuard.formatted(bytes: store.deletableAudioBytes))") {
                    store.deleteAllAudio()
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Transcripts, titles and to-do links are all kept.")
            }
            .confirmationDialog("Delete every recording?",
                                isPresented: $confirmBulkDelete,
                                titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { store.deleteAll() }
                Button("Keep", role: .cancel) {}
            }
        }
    }
}
