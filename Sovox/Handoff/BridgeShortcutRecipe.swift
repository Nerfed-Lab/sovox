import Foundation

/// The exact four actions the bridge Shortcut needs. Shown verbatim on the setup
/// screen so the user never sees a generic failure.
enum BridgeShortcutRecipe {
    static func steps(for destination: AIDestination) -> [String] {
        [
            "Get File from Folder: choose \(RecordingPaths.filesLocation), sovox-pending.txt. Switch Show Document Picker off.",
            "Get Text from Input: pass the file from step one.",
            "\(destination.title): ask it the text from step two. Use the Ask ChatGPT action from the ChatGPT app, or the Ask Claude action from the Claude app.",
            "Save File: save the result to \(RecordingPaths.filesLocation), name it sovox-result.txt, Overwrite If File Exists on, Ask Where To Save off."
        ]
    }

    /// Phase 10 wizard rows. Each value is copyable on its own, so nothing has
    /// to be retyped.
    struct SetupRow: Equatable {
        var action: String
        var value: String
    }

    static func setupRows(for destination: AIDestination) -> [SetupRow] {
        [
            SetupRow(action: "Get File",
                     value: "\(RecordingPaths.filesLocation), \(RecordingPaths.pendingPromptFile.lastPathComponent)"),
            SetupRow(action: "Ask \(destination.title)",
                     value: "prompt is the file from action 1"),
            SetupRow(action: "Save File",
                     value: "\(RecordingPaths.filesLocation), \(RecordingPaths.resultFile.lastPathComponent), Overwrite ON, Ask Where To Save OFF"),
            SetupRow(action: "Open URL",
                     value: SovoxURL.done.absoluteString)
        ]
    }

    static func name(for destination: AIDestination) -> String {
        destination.shortcutName
    }
}
