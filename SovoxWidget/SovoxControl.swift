import WidgetKit
import SwiftUI
import AppIntents

/// Control Centre control. The intent conforms to LiveActivityIntent so the
/// system performs it inside the app process, which is the only process that can
/// own an audio session.
struct SovoxControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.sovox.control.toggle") {
            ControlWidgetButton(action: ToggleSovoxIntent()) {
                Label("Sovox", systemImage: "record.circle")
            }
        }
        .displayName("Sovox Notes")
        .description("Start or stop a meeting recording.")
    }
}
