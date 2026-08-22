import Foundation

/// Builds the Outlook subject line.
/// Shape with names:    dd MMM yyyy | HH:mm | topic | names
/// Shape without names: dd MMM yyyy | HH:mm | topic
/// Empty components are dropped before joining, so a trailing or doubled
/// separator is structurally impossible.
enum SubjectBuilder {
    static let separator = " | "
    static let maxAttendees = 3
    /// The model is asked for three to five words and will sometimes return a
    /// paragraph anyway. An uncapped topic makes an unreadable subject line and
    /// pushes the whole ms-outlook URL toward the length where Outlook starts
    /// dropping the tail, taking the body with it.
    static let maxTopicCharacters = 80
    static let maxNameCharacters = 40

    /// Always present, and derived from CFBundleDisplayName rather than a
    /// literal, so a future rename stays in sync automatically. The model is
    /// never asked for it and must never put it in its own SUBJECT line.
    static var appPrefix: String {
        let info = Bundle.main.infoDictionary
        if let display = info?["CFBundleDisplayName"] as? String, !display.isEmpty { return display }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty { return name }
        return "Sovox"
    }

    static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "dd MMM yyyy"
        return f
    }

    static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f
    }

    static func subject(date: Date,
                        topic: String,
                        attendees: [String],
                        excluding ownName: String = "",
                        timeZone: TimeZone = .current) -> String {
        let day = dateFormatter(timeZone: timeZone).string(from: date)
        let time = timeFormatter(timeZone: timeZone).string(from: date)
        let cleanTopic = clip(sanitise(topic), to: maxTopicCharacters)
        let names = cleanNames(attendees, excluding: ownName)

        // The attendee segment and its preceding separator collapse together
        // when no names were found, so a trailing or doubled separator is
        // structurally impossible.
        return [sanitise(appPrefix), day, time, cleanTopic, names]
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    static func cleanNames(_ attendees: [String], excluding ownName: String) -> String {
        let own = sanitise(ownName).lowercased()
        return attendees
            .map { clip(sanitise($0), to: maxNameCharacters) }
            .filter { !$0.isEmpty }
            .filter { own.isEmpty || $0.lowercased() != own }
            .prefix(maxAttendees)
            .joined(separator: ", ")
    }

    /// Cuts at the last word boundary that fits, so a long value ends on a word
    /// rather than mid syllable. Falls back to a hard cut when the first word is
    /// itself longer than the limit.
    static func clip(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        let head = String(value.prefix(limit))
        if let space = head.lastIndex(of: " ") {
            let trimmed = String(head[head.startIndex..<space])
                .trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// Strips the separator character so a value can never forge a new column,
    /// and collapses runs of whitespace so an empty looking value becomes "".
    static func sanitise(_ value: String) -> String {
        ResponseParser.collapseWhitespace(value.replacingOccurrences(of: "|", with: " "))
    }
}
