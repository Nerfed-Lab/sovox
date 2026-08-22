import Foundation

struct OutlookDraft: Sendable {
    var url: URL
    /// Set when the body was too long for a URL and was written to a file instead.
    var attachmentFile: URL?
    var subject: String
}

enum OutlookComposer {
    /// Measured against the percent encoded body, since that is what actually
    /// travels in the URL.
    static let encodedBodyLimit = 4000

    static func draft(to recipient: String,
                      subject: String,
                      body: String,
                      date: Date = Date()) -> OutlookDraft? {
        var finalBody = body
        var attachment: URL?

        if URLEncoding.encode(body).count > encodedBodyLimit {
            let file = RecordingPaths.notesFile(for: date)
            try? body.write(to: file, atomically: true, encoding: .utf8)
            attachment = file
            finalBody = """
            The full notes were too long to prefill here.

            They are saved as \(file.lastPathComponent) in Files, under \(RecordingPaths.filesLocation).

            Tap the paperclip in this draft, choose Files, and attach it. The raw transcript is also on your clipboard.
            """
        }

        var parameters: [(String, String)] = []
        if !recipient.trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append(("to", recipient))
        }
        parameters.append(("subject", subject))
        parameters.append(("body", finalBody))

        guard let url = URLEncoding.url(scheme: "ms-outlook", path: "compose", parameters: parameters) else {
            return nil
        }
        return OutlookDraft(url: url, attachmentFile: attachment, subject: subject)
    }
}
