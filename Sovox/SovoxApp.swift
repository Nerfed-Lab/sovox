import SwiftUI

enum AppTab: Hashable {
    case record
    case history
    case ask
    case todos
    case settings
}

@main
struct SovoxApp: App {
    @State private var recorder = RecorderController.shared
    @State private var store = RecordingStore.shared
    @State private var settings = AppSettings.shared
    @State private var handoff = HandoffCoordinator.shared
    @State private var tab: AppTab = .record
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RecorderController.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView(tab: $tab)
                .environment(recorder)
                .environment(store)
                .environment(settings)
                .environment(handoff)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(SovoxPalette.accent)
                .onOpenURL { handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        recorder.setForeground(true)
                        // A draft that iOS refused to open while the scene was
                        // settling gets its second chance here.
                        Task { await handoff.openPendingDraft() }
                        // A result can be sitting in the file with nobody
                        // reading it: the callback is the last action of a
                        // hand built Shortcut, and it can be missing.
                        Task { await handoff.collectIfResultWaiting(settings: settings, store: store) }
                        // iOS will not let a background process open another app,
                        // so a hand off that became ready while backgrounded is
                        // performed here instead.
                        if recorder.pendingHandoffSessionID != nil {
                            tab = .record
                            recorder.clearPendingHandoff()
                        }
                    case .background, .inactive:
                        recorder.setForeground(false)
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func handle(_ url: URL) {
        switch SovoxURL.route(for: url, isInFlight: handoff.isInFlight) {
        case .collectResult:
            tab = .record
            Task { await handoff.collectResult(settings: settings, store: store) }
        case .reportFailure:
            tab = .record
            handoff.handleFailure()
        case .openRecording:
            tab = .record
        case .ignore:
            break
        }
    }
}
