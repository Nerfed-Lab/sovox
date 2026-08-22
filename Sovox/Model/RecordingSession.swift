import Foundation

enum SessionSource: String, Codable, Sendable {
    case recorded
    case pasted
}

/// Per segment transcription state, persisted with the manifest so a failure is
/// still visible after a relaunch. Swift synthesises Codable for enums with
/// associated values, so the reason survives to disk.
enum SegmentState: Codable, Equatable, Sendable {
    case pending
    case running
    case done
    case failed(reason: String)
    /// Held back by the thermal guard. Not an error, and it retries itself.
    case deferred(reason: String)

    var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        case .pending, .running, .deferred: return false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var reason: String? {
        switch self {
        case .failed(let r), .deferred(let r): return r
        case .pending, .running, .done: return nil
        }
    }

    var label: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Transcribing"
        case .done: return "Done"
        case .failed: return "Failed"
        case .deferred: return "Paused, device warm"
        }
    }
}

struct SegmentRecord: Codable, Equatable, Sendable, Identifiable {
    var index: Int
    var fileName: String
    var duration: TimeInterval
    var state: SegmentState
    var text: String

    var id: Int { index }
}

/// Written to disk on every segment boundary. A force quit mid recording
/// therefore leaves a manifest listing every finished segment, which the store
/// picks up on next launch and offers to transcribe.
struct RecordingSession: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var startDate: Date
    var duration: TimeInterval
    var segments: [SegmentRecord]
    var transcript: String
    var isComplete: Bool
    var source: SessionSource
    /// Set by the user. Sticky: regeneration must never overwrite it.
    var userTitle: String?
    /// The SUBJECT line parsed out of the model response.
    var aiSubject: String?
    /// Phase 6. Stored per recording and editable on regeneration.
    var conversationType: ConversationType
    /// Set by "Delete audio only". The transcript, title, notes and to-do links
    /// all survive, so reconcile must not treat the absent files as corruption.
    var audioRemoved: Bool
    /// Phase 14a. Stored per recording so a transcript can be regenerated later
    /// with the setting that produced it.
    var localeIdentifier: String?

    init(id: String,
         startDate: Date,
         duration: TimeInterval = 0,
         segments: [SegmentRecord] = [],
         transcript: String = "",
         isComplete: Bool = false,
         source: SessionSource = .recorded,
         userTitle: String? = nil,
         aiSubject: String? = nil,
         conversationType: ConversationType = .auto,
         audioRemoved: Bool = false,
         localeIdentifier: String? = nil) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.segments = segments
        self.transcript = transcript
        self.isComplete = isComplete
        self.source = source
        self.userTitle = userTitle
        self.aiSubject = aiSubject
        self.conversationType = conversationType
        self.audioRemoved = audioRemoved
        self.localeIdentifier = localeIdentifier
    }

    var directory: URL { RecordingPaths.sessionDirectory(id) }

    var hasAudio: Bool { source == .recorded && !audioRemoved && !segments.isEmpty }

    /// Fills in a duration the app never had, for a segment adopted from disk
    /// after a force quit. Only ever writes over a zero: the engine's own figure
    /// is authoritative for anything it actually timed. Returns false when
    /// nothing changed.
    mutating func applyMeasuredDuration(index: Int, seconds: TimeInterval) -> Bool {
        guard seconds > 0,
              let slot = segments.firstIndex(where: { $0.index == index }),
              segments[slot].duration <= 0 else { return false }
        segments[slot].duration = seconds
        let summed = segments.reduce(0) { $0 + $1.duration }
        // A recorded session's own figure comes from the elapsed clock and
        // includes paused time, so it is never shortened here.
        if duration <= 0 || duration < summed { duration = summed }
        return true
    }

    /// Whether this one segment still has its .m4a. Checked per row because a
    /// session can lose some of its audio and keep the rest, and a retry that
    /// has no file to read can never succeed.
    func audioExists(for segment: SegmentRecord) -> Bool {
        guard hasAudio else { return false }
        return FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(segment.fileName).path)
    }

    /// Every segment actually produced text. Distinct from isTranscribed, which
    /// only means nothing is still in flight: a permanently failed segment is
    /// terminal but has no text.
    var isFullyTranscribed: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.state == .done }
    }

    /// Audio may only be discarded once every segment has actually succeeded.
    /// Gating on isTranscribed was wrong: a failed segment counts as terminal,
    /// so the audio, which is the only copy of those minutes, could be deleted
    /// while the transcript still had a hole in it.
    var canDeleteAudio: Bool { hasAudio && isComplete && isFullyTranscribed }

    var segmentURLs: [URL] {
        segments.sorted { $0.index < $1.index }.map { directory.appendingPathComponent($0.fileName) }
    }

    var transcriptionProgress: Double {
        guard !segments.isEmpty else { return 0 }
        let settled = segments.filter { $0.state.isTerminal }.count
        return Double(settled) / Double(segments.count)
    }

    var isTranscribed: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.state.isTerminal }
    }

    var failedSegments: [SegmentRecord] {
        segments.filter { $0.state.isFailure }
    }

    var stitchedTranscript: String {
        if source == .pasted { return transcript }
        let stitched = TranscriptStitcher.stitch(records: segments)
        // Defence in depth. If the segment records are ever lost, the last
        // persisted transcript is still better than an empty document.
        if stitched.isEmpty && !transcript.isEmpty { return transcript }
        return stitched
    }

    /// Title precedence, used everywhere including the email subject:
    /// the user's own name, then the AI subject, then the date.
    var displayTitle: String {
        if let userTitle, !userTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            return userTitle
        }
        if let aiSubject, !aiSubject.trimmingCharacters(in: .whitespaces).isEmpty {
            return aiSubject
        }
        return dateLine
    }

    /// True once the row should lead with a title rather than a date.
    var hasTitle: Bool {
        displayTitle != dateLine
    }

    /// The topic that goes into the email subject. Empty when neither the user
    /// nor the model has named it, which lets the subject collapse cleanly.
    var subjectTopic: String {
        hasTitle ? displayTitle : ""
    }

    var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: startDate)
    }

    var displayTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: startDate)
    }
}
