import Foundation

/// Phase 15. What each sub step of the bridge Shortcut actually is.
///
/// The kind is what decides whether a Copy button is offered, rather than the
/// view deciding per row. A real setup attempt failed because guidance text
/// carried a Copy button identical to a literal value, so the sentence
/// "prompt is the file from action 1" was pasted into the model's prompt field.
/// Only `.copyValue` can be copied, and that is enforced here rather than in
/// the view.
enum BridgeSubstepKind: Equatable, Sendable {
    /// A literal string the user must reproduce exactly.
    case copyValue(String)
    case toggleOff(String)
    case toggleOn(String)
    /// A folder to navigate into. Never a file: Shortcuts greys files out here.
    case picker(String)
    /// A variable chip to tap. Nothing is typed and nothing is pasted.
    case variable
    /// Plain guidance. Never copyable.
    case instruction
}

struct BridgeSubstep: Identifiable, Equatable, Sendable {
    /// 1 based, continuous across the whole recipe, so a user can say "I am
    /// stuck on 11" and both ends mean the same step.
    let number: Int
    let group: String
    let text: String
    /// Where the control sits. Field labels move between iOS versions, so every
    /// named field is also described by position.
    let position: String?
    let kind: BridgeSubstepKind

    var id: Int { number }

    /// The only thing a Copy button may ever be attached to.
    var copyValue: String? {
        if case .copyValue(let value) = kind { return value }
        return nil
    }
}

/// The exact Shortcut the bridge needs, as sub steps rather than as a row per
/// action. Three actions, not four: the callback is carried by x-success in the
/// URL the app opens, and the fourth action was the single most error prone
/// step in the old recipe.
enum BridgeShortcutRecipe {

    static func name(for destination: AIDestination) -> String {
        destination.shortcutName
    }

    static func askActionName(for destination: AIDestination) -> String {
        "Ask \(destination.title)"
    }

    /// Where the two bridge files live, spelled the way Files shows it.
    static var folderPath: String { RecordingPaths.filesLocation }

    static func substeps(for destination: AIDestination) -> [BridgeSubstep] {
        let ask = askActionName(for: destination)
        return [
            BridgeSubstep(number: 1, group: "Action 1",
                          text: "In Shortcuts, search for",
                          position: nil,
                          kind: .copyValue("Get File")),
            BridgeSubstep(number: 2, group: "Action 1",
                          text: "Turn OFF the toggle",
                          position: "the first row inside the Get File action",
                          kind: .toggleOff("Show Document Picker")),
            BridgeSubstep(number: 3, group: "Action 1",
                          text: "Tap the folder chip, navigate INTO the folder, then tap Open",
                          position: "the chip on the Folder row, under the toggle",
                          kind: .picker(folderPath)),
            BridgeSubstep(number: 4, group: "Action 1",
                          text: "In the path field, paste",
                          position: "the field directly beneath the Folder row",
                          kind: .copyValue(RecordingPaths.pendingPromptFile.lastPathComponent)),

            BridgeSubstep(number: 5, group: "Action 2",
                          text: "Search for",
                          position: nil,
                          kind: .copyValue(ask)),
            BridgeSubstep(number: 6, group: "Action 2",
                          text: "Tap the Prompt field and delete anything already in it",
                          position: "the large text field inside the \(ask) action",
                          kind: .instruction),
            BridgeSubstep(number: 7, group: "Action 2",
                          text: "Tap the blue File variable from Action 1",
                          position: "on the suggestion bar above the keyboard, or under Shortcut Input",
                          kind: .variable),

            BridgeSubstep(number: 8, group: "Action 3",
                          text: "Search for",
                          position: nil,
                          kind: .copyValue("Save File")),
            BridgeSubstep(number: 9, group: "Action 3",
                          text: "Tap the arrow to expand the action's options",
                          position: "the > at the right hand end of the Save File row",
                          kind: .instruction),
            BridgeSubstep(number: 10, group: "Action 3",
                          text: "Turn OFF the toggle",
                          position: "inside the expanded Save File options",
                          kind: .toggleOff("Ask Where To Save")),
            BridgeSubstep(number: 11, group: "Action 3",
                          text: "Tap the folder chip, navigate INTO the folder, then tap Open",
                          position: "the chip on the Folder row",
                          kind: .picker(folderPath)),
            BridgeSubstep(number: 12, group: "Action 3",
                          text: "In the field labelled Subpath, paste",
                          position: "directly beneath the Ask Where To Save toggle",
                          kind: .copyValue(RecordingPaths.resultFile.lastPathComponent)),
            BridgeSubstep(number: 13, group: "Action 3",
                          text: "Turn ON the toggle",
                          position: "the last row of the expanded Save File options",
                          kind: .toggleOn("Overwrite If File Exists")),

            BridgeSubstep(number: 14, group: "Name",
                          text: "Tap the shortcut name at the top and set it to",
                          position: "the title at the top of the shortcut editor",
                          kind: .copyValue(name(for: destination)))
        ]
    }

    /// Two things that look like faults and are not. Both have already cost a
    /// user a long time.
    static let pickerClarification =
        "In steps 3 and 11 the picker is selecting a FOLDER. Files inside it appear greyed out and cannot be tapped. That is correct, not a sign that anything is missing."

    static let pathFieldClarification =
        "In steps 4 and 12 the path field is typed text, not a picker. The file does not have to exist for the action to be configured."

    static let nameClarification =
        "Letters only. No spaces, no hyphens, no dashes. Shortcuts matches this name character for character."

    /// How Shortcuts renders the finished thing, so the user can compare.
    static func finishedPreview(for destination: AIDestination) -> [String] {
        let ask = askActionName(for: destination)
        return [
            "Get file from \(RecordingPaths.filesFolderName) at path \(RecordingPaths.pendingPromptFile.lastPathComponent)",
            "\(ask)  [File]",
            "Save \(ask) to \(RecordingPaths.filesFolderName)"
        ]
    }

    /// Flat text form, for the screen shown when the Shortcut is missing.
    /// Derived from the same sub steps, so the two screens cannot drift apart
    /// the way they did when one of them omitted an action.
    static func steps(for destination: AIDestination) -> [String] {
        substeps(for: destination).map { step in
            switch step.kind {
            case .copyValue(let value): return "\(step.number). \(step.text): \(value)"
            case .toggleOff(let label): return "\(step.number). \(step.text): \(label), OFF"
            case .toggleOn(let label): return "\(step.number). \(step.text): \(label), ON"
            case .picker(let path): return "\(step.number). \(step.text): \(path)"
            case .variable: return "\(step.number). \(step.text). Do not type anything here."
            case .instruction: return "\(step.number). \(step.text)."
            }
        }
    }
}
