import Foundation

struct CustomAction: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var instruction: String
    var includeByDefault: Bool

    init(id: UUID = UUID(), name: String, instruction: String, includeByDefault: Bool = false) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.includeByDefault = includeByDefault
    }
}

/// What the sanitiser removed, so the user can be told rather than having their
/// text altered silently.
struct SanitisationReport: Equatable, Sendable {
    var notes: [String] = []
    var isEmpty: Bool { notes.isEmpty }
}

enum CustomActionError: LocalizedError, Equatable {
    case emptyName
    case emptyInstruction
    case limitReached(Int)

    var errorDescription: String? {
        switch self {
        case .emptyName: return "The name is empty once quotes and line breaks are removed."
        case .emptyInstruction: return "The instruction is empty once forbidden lines are removed."
        case .limitReached(let max): return "You already have \(max) custom actions. Delete one first."
        }
    }
}

/// Custom actions are the only place free user text enters the master prompt,
/// and the SUBJECT and ATTENDEES parsing that drives every email subject sits
/// directly downstream. Sanitisation happens once, on save, never at prompt
/// assembly time, so what is stored is already safe and the user is shown what
/// changed while they can still react to it.
enum CustomActionSanitiser {
    static let maxActions = 8
    static let maxNameLength = 40
    static let maxInstructionLength = 1500

    struct Result: Equatable {
        var action: CustomAction
        var report: SanitisationReport
    }

    static func sanitise(id: UUID = UUID(),
                         name rawName: String,
                         instruction rawInstruction: String,
                         includeByDefault: Bool) throws -> Result {
        var report = SanitisationReport()

        // Name: a double quote would let the value close the wrapper's own
        // quoting, and a newline would let it forge a second line entirely.
        var name = rawName
        if name.contains("\"") {
            name = name.replacingOccurrences(of: "\"", with: "")
            report.notes.append("Removed double quotes from the name.")
        }
        if name.contains("\n") || name.contains("\r") {
            name = name.replacingOccurrences(of: "\r", with: " ")
                       .replacingOccurrences(of: "\n", with: " ")
            report.notes.append("Removed line breaks from the name.")
        }
        // The wrapper's own opening line is --- IF "name" REQUESTED ---, so a
        // dash run inside the name could close it.
        if name.contains("--") {
            while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
            report.notes.append("Flattened runs of dashes in the name, which could have closed the section header.")
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > maxNameLength {
            name = String(name.prefix(maxNameLength))
            report.notes.append("Shortened the name to \(maxNameLength) characters.")
        }
        guard !name.isEmpty else { throw CustomActionError.emptyName }

        // Instruction: strip carriage returns, then any line that could close
        // the wrapper block or forge one of the two contract header lines.
        var instruction = rawInstruction.replacingOccurrences(of: "\r", with: "")
        var kept: [String] = []
        var droppedFence = 0
        var droppedHeader = 0
        for line in instruction.components(separatedBy: "\n") {
            if line.range(of: #"^\s*---"#, options: .regularExpression) != nil {
                droppedFence += 1
                continue
            }
            if line.range(of: #"^\s*(SUBJECT|ATTENDEES)\s*:"#, options: [.regularExpression]) != nil {
                droppedHeader += 1
                continue
            }
            kept.append(line)
        }
        if droppedFence > 0 {
            report.notes.append("Removed \(droppedFence) line\(droppedFence == 1 ? "" : "s") starting with --- which would have closed the section.")
        }
        if droppedHeader > 0 {
            report.notes.append("Removed \(droppedHeader) line\(droppedHeader == 1 ? "" : "s") starting with SUBJECT: or ATTENDEES: which would have forged a header.")
        }
        instruction = kept.joined(separator: "\n")

        // Dropping lines that start with --- is not enough. A marker sitting
        // mid line is still a marker to a model, and a forged
        // --- TRANSCRIPT BEGINS --- after the real transcript would make
        // everything below it, the precedence reassertion included, look like
        // transcript rather than instruction.
        if instruction.contains("---") {
            while instruction.contains("---") {
                instruction = instruction.replacingOccurrences(of: "---", with: "-")
            }
            report.notes.append("Flattened runs of dashes inside the instruction, which could have opened or closed a section.")
        }

        if instruction.count > maxInstructionLength {
            instruction = String(instruction.prefix(maxInstructionLength))
            report.notes.append("Shortened the instruction to \(maxInstructionLength) characters.")
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CustomActionError.emptyInstruction
        }

        return Result(action: CustomAction(id: id,
                                           name: name,
                                           instruction: instruction,
                                           includeByDefault: includeByDefault),
                      report: report)
    }
}

/// One-tap starters. Added as real, editable actions rather than presets, so
/// nothing behaves differently from something the user typed themselves.
enum CustomActionTemplate {
    static let all: [CustomAction] = [
        CustomAction(name: "Client follow-up draft",
                     instruction: "Draft a short follow-up email to the client covering what was agreed and what happens next. Professional, under 150 words, no pleasantries beyond one opening line."),
        CustomAction(name: "Questions I should have asked",
                     instruction: "List up to 5 questions that would have materially improved this conversation but were not asked."),
        CustomAction(name: "Verbatim insights",
                     instruction: "Extract the most substantive things each participant said, close to their original wording. For expert or client interviews.")
    ]
}
