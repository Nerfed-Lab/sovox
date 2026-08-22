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

    static let truncationNotice = "\n\n[Cut short here. The notes were too long for a draft and could not be saved to a file. The full raw transcript is on your clipboard.]"

    /// Longest prefix of the notes whose percent encoded form, plus the notice,
    /// still fits. Percent encoding expands by up to three characters per byte,
    /// so the length has to be measured after encoding rather than guessed.
    static func truncatedBody(_ body: String, limit: Int = encodedBodyLimit) -> String {
        let budget = limit - URLEncoding.encode(truncationNotice).count
        guard budget > 0 else { return truncationNotice }
        var low = 0
        var high = body.count
        while low < high {
            let mid = (low + high + 1) / 2
            if URLEncoding.encode(String(body.prefix(mid))).count <= budget {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(body.prefix(low)) + truncationNotice
    }

    static func draft(to recipient: String,
                      subject: String,
                      body: String,
                      date: Date = Date()) -> OutlookDraft? {
        var finalBody = body
        var attachment: URL?

        if URLEncoding.encode(body).count > encodedBodyLimit {
            let file = RecordingPaths.notesFile(for: date)
            do {
                try body.write(to: file, atomically: true, encoding: .utf8)
                attachment = file
                finalBody = """
                The full notes were too long to prefill here.

                They are saved as \(file.lastPathComponent) in Files, under \(RecordingPaths.filesLocation).

                Tap the paperclip in this draft, choose Files, and attach it. The raw transcript is also on your clipboard.
                """
            } catch {
                // The write can fail on a full disk, which is exactly when the
                // notes are most worth keeping. Telling the user to attach a
                // file that was never written would lose them entirely, so send
                // what fits and say plainly that it is cut short.
                finalBody = truncatedBody(body)
            }
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
