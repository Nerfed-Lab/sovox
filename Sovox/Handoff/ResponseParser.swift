import Foundation

struct ParsedResponse: Equatable, Sendable {
    var topic: String
    var attendees: [String]
    var body: String
}

/// Pulls the two contract header lines out of whatever the model returned and
/// removes them from the body. Tolerates lowercase headers, stray whitespace
/// and markdown emphasis, because a model will eventually produce all three.
enum ResponseParser {
    private static let searchDepth = 12
    private static let maxAttendees = 3

    static func parse(_ raw: String) -> ParsedResponse {
        let lines = raw.components(separatedBy: .newlines)
        var topic = ""
        var attendees: [String] = []
        var dropped = Set<Int>()

        for (index, line) in lines.enumerated() {
            if index >= searchDepth { break }
            let stripped = stripDecoration(line)
            if topic.isEmpty, let value = value(of: "subject", in: stripped) {
                topic = value
                dropped.insert(index)
                continue
            }
            if attendees.isEmpty, let value = value(of: "attendees", in: stripped) {
                attendees = splitNames(value)
                dropped.insert(index)
            }
        }

        let bodyLines = lines.enumerated()
            .filter { !dropped.contains($0.offset) }
            .map(\.element)

        return ParsedResponse(topic: topic,
                              attendees: attendees,
                              body: trimBlankEdges(bodyLines))
    }

    /// Removes leading markdown emphasis or list markers and trailing emphasis.
    private static func stripDecoration(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while let first = s.first, first == "#" || first == "*" || first == ">" || first == "-" {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        while let last = s.last, last == "*" {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Returns the value after "key:" when the line is that header, else nil.
    private static func value(of key: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[line.startIndex..<colon]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "*", with: "")
            .lowercased()
        guard head == key else { return nil }
        var tail = String(line[line.index(after: colon)...])
        tail = tail.replacingOccurrences(of: "*", with: "")
        return collapseWhitespace(tail)
    }

    private static func splitNames(_ value: String) -> [String] {
        let cleaned: [String] = value
            .components(separatedBy: ",")
            .map { collapseWhitespace($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'.")) }
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty && $0.lowercased() != "none" && $0.lowercased() != "n/a" }
        return Array(cleaned.prefix(maxAttendees))
    }

    static func collapseWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimBlankEdges(_ lines: [String]) -> String {
        var slice = lines[...]
        while let first = slice.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropFirst()
        }
        while let last = slice.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropLast()
        }
        return slice.joined(separator: "\n")
    }
}
