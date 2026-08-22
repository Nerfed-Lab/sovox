import Foundation
import Observation

/// Disk backed list of sessions. The manifest for a session is rewritten on
/// every segment boundary, so a force quit at minute one hundred and fifty
/// leaves a manifest describing every completed segment, ready to transcribe on
/// the next launch.
@MainActor
@Observable
final class RecordingStore {
    static let shared = RecordingStore()

    private(set) var sessions: [RecordingSession] = []

    /// The recording currently being written. Deleting it would pull the
    /// directory out from under a live AVAudioFile: the write handle stays
    /// valid on an unlinked file, so the audio would go nowhere and nothing
    /// would report an error until the session was already lost.
    var protectedSessionID: String?
    /// Cached, because SettingsView reads it from a view body and walking the
    /// recordings tree on every body evaluation would be a real cost once there
    /// are a few hours of audio on disk.
    private(set) var storageBytes: Int64 = 0

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        RecordingPaths.ensureDirectory(RecordingPaths.recordingsRoot)
        reload()
    }

    func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: RecordingPaths.recordingsRoot,
                                                        includingPropertiesForKeys: nil) else {
            sessions = []
            return
        }
        var loaded: [RecordingSession] = []
        for entry in entries where entry.hasDirectoryPath {
            let manifest = entry.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: manifest),
                  var session = try? decoder.decode(RecordingSession.self, from: data) else { continue }
            session = reconcile(session)
            loaded.append(session)
        }
        sessions = loaded.sorted { $0.startDate > $1.startDate }
        recomputeStorage()
    }

    /// Reconciles a manifest against what is actually on disk, and picks up
    /// segments that exist on disk but never made it into the manifest, which is
    /// exactly the state a force quit produces.
    private func reconcile(_ session: RecordingSession) -> RecordingSession {
        guard session.source == .recorded else { return session }
        // Audio deleted on purpose is not a corrupt session. Keeping the segment
        // records is what preserves the transcript, the title and the to-do links.
        guard !session.audioRemoved else { return session }
        let fm = FileManager.default
        var updated = RecordingStore.pruneSegments(session) {
            fm.fileExists(atPath: session.directory.appendingPathComponent($0).path)
        }
        let known = Set(updated.segments.map(\.fileName))
        if let files = try? fm.contentsOfDirectory(at: session.directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "m4a" && !known.contains(file.lastPathComponent) {
                let index = Int(file.lastPathComponent
                    .replacingOccurrences(of: "seg-", with: "")
                    .replacingOccurrences(of: ".m4a", with: "")) ?? (updated.segments.count + 1)
                updated.segments.append(SegmentRecord(index: index,
                                                      fileName: file.lastPathComponent,
                                                      duration: 0,
                                                      state: .pending,
                                                      text: ""))
            }
        }
        updated.segments.sort { $0.index < $1.index }
        return updated
    }

    /// Documents is visible in Files, so a user can delete a .m4a without the
    /// app ever hearing about it. A segment that already produced text is kept
    /// even when its audio is gone: dropping the record would take the
    /// transcript with it, and the next persist would make that permanent.
    /// Only a segment with no audio and no text is discarded, which is the
    /// force quit leftover this was written for.
    ///
    /// Pure so it can be tested without touching the file system.
    nonisolated static func pruneSegments(_ session: RecordingSession,
                                          audioExists: (String) -> Bool) -> RecordingSession {
        var updated = session
        var anyAudioLeft = false
        updated.segments = session.segments.filter { segment in
            if audioExists(segment.fileName) {
                anyAudioLeft = true
                return true
            }
            return !segment.text.isEmpty
        }
        // Nothing playable is left, so stop claiming otherwise. This is what
        // takes away share, retry and the delete audio row.
        if !anyAudioLeft, !updated.segments.isEmpty {
            updated.audioRemoved = true
        }
        return updated
    }

    var latest: RecordingSession? { sessions.first }

    /// Sessions that were interrupted by a force quit and still have untranscribed audio.
    var unfinished: [RecordingSession] {
        sessions.filter { $0.source == .recorded && !$0.segments.isEmpty && !$0.isTranscribed }
    }

    func session(id: String) -> RecordingSession? {
        sessions.first { $0.id == id }
    }

    func upsert(_ session: RecordingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.startDate > $1.startDate }
        persist(session)
        recomputeStorage()
    }

    func persist(_ session: RecordingSession) {
        RecordingPaths.ensureDirectory(session.directory)
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: RecordingPaths.manifestURL(sessionID: session.id), options: .atomic)
    }

    /// Mutates one field on the live record. Writing back a captured snapshot
    /// would resurrect whatever that snapshot held, which silently erased a
    /// title the user had just typed.
    func setConversationType(sessionID: String, to type: ConversationType) {
        guard var session = session(id: sessionID) else { return }
        session.conversationType = type
        upsert(session)
    }

    /// A rename is sticky and never re-triggers generation.
    func rename(sessionID: String, to title: String) {
        guard var session = session(id: sessionID) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.userTitle = trimmed.isEmpty ? nil : trimmed
        upsert(session)
    }

    /// Bytes the .m4a files occupy, so the user is told what they will free.
    func audioBytes(of session: RecordingSession) -> Int64 {
        guard session.hasAudio else { return 0 }
        var total: Int64 = 0
        for url in session.segmentURLs {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    var totalAudioBytes: Int64 {
        sessions.reduce(0) { $0 + audioBytes(of: $1) }
    }

    /// Removes the audio and keeps everything else.
    ///
    /// Refuses while any segment is still queued or transcribing, because the
    /// audio is the only copy of that text and deleting it would silently break
    /// the promise the button makes on screen.
    ///
    /// The manifest is written BEFORE the files are removed. In the other order
    /// a kill mid delete left files gone with audioRemoved still false, and
    /// reconcile would then strip the segment records and take the transcript
    /// with them.
    @discardableResult
    func deleteAudio(_ session: RecordingSession) -> Bool {
        guard canDelete(session.id),
              var updated = self.session(id: session.id), updated.canDeleteAudio else { return false }
        updated.audioRemoved = true
        upsert(updated)
        for url in session.segmentURLs {
            try? FileManager.default.removeItem(at: url)
        }
        return true
    }

    func deleteAllAudio() {
        for session in sessions where session.canDeleteAudio {
            deleteAudio(session)
        }
    }

    /// Total the "delete all audio" confirmation quotes, counting only what it
    /// will actually delete.
    var deletableAudioBytes: Int64 {
        sessions.filter(\.canDeleteAudio).reduce(0) { $0 + audioBytes(of: $1) }
    }

    @discardableResult
    func delete(_ session: RecordingSession) -> Bool {
        guard canDelete(session.id) else { return false }
        try? FileManager.default.removeItem(at: session.directory)
        sessions.removeAll { $0.id == session.id }
        recomputeStorage()
        return true
    }

    func canDelete(_ sessionID: String) -> Bool { sessionID != protectedSessionID }

    func deleteAll() {
        let survivors = sessions.filter { !canDelete($0.id) }
        for session in sessions where canDelete(session.id) {
            try? FileManager.default.removeItem(at: session.directory)
        }
        sessions = survivors
        RecordingPaths.ensureDirectory(RecordingPaths.recordingsRoot)
        recomputeStorage()
    }

    func addPasted(text: String, date: Date = Date()) -> RecordingSession {
        let id = RecordingPaths.uniqueSessionID(for: date) + "-pasted"
        var session = RecordingSession(id: id, startDate: date, source: .pasted)
        session.transcript = text
        session.isComplete = true
        upsert(session)
        return session
    }

    private func recomputeStorage() {
        var total: Int64 = 0
        let fm = FileManager.default
        if let walker = fm.enumerator(at: RecordingPaths.recordingsRoot,
                                      includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
        storageBytes = total
    }
}
