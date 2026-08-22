import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingStore.self) private var store
    @Environment(RecorderController.self) private var recorder
    @State private var confirmBulkDelete = false
    @State private var confirmAudioDelete = false
    @State private var showWizard = false

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
                        Picker("Default AI", selection: $settings.destination) {
                            ForEach(AIDestination.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Transcription") {
                        Picker("Language", selection: $settings.transcriptionLocale) {
                            ForEach(TranscriptionLocale.supported(), id: \.identifier) { locale in
                                Text(TranscriptionLocale.displayName(locale))
                                    .tag(TranscriptionLocale.normalise(locale.identifier))
                            }
                        }
                        if !TranscriptionLocale.isOnDeviceReady(settings.transcriptionLocale) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("On device model not installed for this language",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(SovoxPalette.pauseAmber)
                                Text("Turn on Settings, General, Keyboard, Enable Dictation and pick this language. iOS downloads the model then. Sovox will not silently fall back to another language.")
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
