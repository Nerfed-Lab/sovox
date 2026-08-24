import WidgetKit
import SwiftUI
import AppIntents

/// Control Centre control.
///
/// The intent conforms to AudioRecordingIntent, which is both a SystemIntent, so
/// the system performs it inside the app process, the only process that can own
/// an audio session, and the declaration that earns a recording started from the
/// background. It used to be LiveActivityIntent, which bought the first of those
/// and not the second.
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
