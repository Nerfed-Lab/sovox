import AppIntents

/// Siri and Spotlight phrases. Every phrase has to contain the application name
/// token, which for this app resolves to "Sovox", giving "Start Sovox",
/// "Stop Sovox" and "Toggle Sovox".
struct SovoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSovoxIntent(),
                    phrases: ["Start \(.applicationName)",
                              "Begin \(.applicationName)",
                              "New recording in \(.applicationName)"],
                    shortTitle: "Start Sovox",
                    systemImageName: "record.circle")

        AppShortcut(intent: StopSovoxIntent(),
                    phrases: ["Stop \(.applicationName)",
                              "End \(.applicationName)"],
                    shortTitle: "Stop Sovox",
                    systemImageName: "stop.circle")

        AppShortcut(intent: ToggleSovoxIntent(),
                    phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle Sovox",
                    systemImageName: "record.circle.fill")

        AppShortcut(intent: PauseSovoxIntent(),
                    phrases: ["Pause \(.applicationName)"],
                    shortTitle: "Pause Sovox",
                    systemImageName: "pause.circle")

        AppShortcut(intent: ResumeSovoxIntent(),
                    phrases: ["Resume \(.applicationName)"],
                    shortTitle: "Resume Sovox",
                    systemImageName: "play.circle")
    }
}
