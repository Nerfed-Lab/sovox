import Foundation

/// Everything lives inside Documents so the recordings and the hand off files
/// are visible in Files. No app group container is
/// used anywhere, which keeps the project installable with a free Apple ID.
enum RecordingPaths {
    /// The folder name Files actually shows under On My iPhone. iOS derives it
    /// from CFBundleDisplayName, so hardcoding it means every rename silently
    /// sends the user hunting for a folder that does not exist. It has already
    /// happened once.
    static var filesFolderName: String {
        let info = Bundle.main.infoDictionary
        if let display = info?["CFBundleDisplayName"] as? String, !display.isEmpty { return display }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty { return name }
        return "Sovox"
    }

    /// Ready to drop into instruction text.
    static var filesLocation: String { "On My iPhone, \(filesFolderName)" }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var recordingsRoot: URL {
        documents.appendingPathComponent("Recordings", isDirectory: true)
    }

    static var pendingPromptFile: URL {
        documents.appendingPathComponent("sovox-pending.txt")
    }

    static var resultFile: URL {
        documents.appendingPathComponent("sovox-result.txt")
    }

    static func notesFile(for date: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return documents.appendingPathComponent("meeting-notes-\(f.string(from: date)).md")
    }

    static func sessionID(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return "sovox-\(f.string(from: date))"
    }

    static func sessionDirectory(_ id: String) -> URL {
        recordingsRoot.appendingPathComponent(id, isDirectory: true)
    }

    static func segmentFileName(_ index: Int) -> String {
        String(format: "seg-%02d.m4a", index)
    }

    static func segmentURL(sessionID: String, index: Int) -> URL {
        sessionDirectory(sessionID).appendingPathComponent(segmentFileName(index))
    }

    static func manifestURL(sessionID: String) -> URL {
        sessionDirectory(sessionID).appendingPathComponent("session.json")
    }

    @discardableResult
    static func ensureDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// A unique session id even if two recordings begin inside the same minute.
    /// A session id nothing else is using.
    ///
    /// The trailing part matters: uniqueness has to be checked on the whole id,
    /// not on the timestamp alone. Pasted transcripts carry a -pasted suffix, so
    /// checking the bare timestamp said "free" for two pastes in the same minute
    /// and the second one overwrote the first.
    static func uniqueSessionID(for date: Date,
                                trailing: String = "",
                                isTaken: (String) -> Bool = { FileManager.default.fileExists(atPath: sessionDirectory($0).path) }) -> String {
        let base = sessionID(for: date) + trailing
        var candidate = base
        var suffix = 2
        while isTaken(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}
