import Foundation

/// Builds the Outlook subject line.
/// Shape with names:    dd MMM yyyy | HH:mm | topic | names
/// Shape without names: dd MMM yyyy | HH:mm | topic
/// Empty components are dropped before joining, so a trailing or doubled
/// separator is structurally impossible.
enum SubjectBuilder {
    static let separator = " | "
    static let maxAttendees = 3

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
        let cleanTopic = sanitise(topic)
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
            .map(sanitise)
            .filter { !$0.isEmpty }
            .filter { own.isEmpty || $0.lowercased() != own }
            .prefix(maxAttendees)
            .joined(separator: ", ")
    }

    /// Strips the separator character so a value can never forge a new column,
    /// and collapses runs of whitespace so an empty looking value becomes "".
    static func sanitise(_ value: String) -> String {
        ResponseParser.collapseWhitespace(value.replacingOccurrences(of: "|", with: " "))
    }
}
