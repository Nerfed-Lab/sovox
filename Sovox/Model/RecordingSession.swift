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
    /// Phase 18a. Transcription SUCCEEDED and heard nothing. Not a failure:
    /// History was filling with rows reading "could not be transcribed" for
    /// recordings where nothing was ever said, which is a different thing from
    /// a recogniser that fell over.
    case empty
    case failed(reason: String)
    /// Held back by the thermal guard. Not an error, and it retries itself.
    case deferred(reason: String)

    var isTerminal: Bool {
        switch self {
        case .done, .empty, .failed: return true
        case .pending, .running, .deferred: return false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Heard nothing, and said so successfully.
    var isEmptyResult: Bool { self == .empty }

    var reason: String? {
        switch self {
        case .failed(let r), .deferred(let r): return r
        case .pending, .running, .done, .empty: return nil
        }
    }

    var label: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Transcribing"
        case .done: return "Done"
        case .empty: return "No speech"
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

    /// Whether anything is still worth handing to the transcriber: something
    /// unfinished, or something that failed and can be retried. False means the
    /// queue will never call back for this session, so nothing else may wait on
    /// a drain that is not coming.
    var needsTranscriptionWork: Bool {
        segments.contains { !$0.state.isTerminal || $0.state.isFailure }
    }

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

    /// Files a share sheet can actually be given.
    ///
    /// hasAudio is a session level flag, so on its own it happily offered a
    /// share for a segment whose file had been deleted in Files, and for the
    /// segment still being written, which is not a playable .m4a until the
    /// engine closes it.
    func shareableAudioURLs(isRecording: Bool,
                            exists: (SegmentRecord) -> Bool) -> [URL] {
        guard hasAudio else { return [] }
        let ordered = segments.sorted { $0.index < $1.index }
        let openIndex = isRecording ? ordered.last?.index : nil
        return ordered
            .filter { $0.index != openIndex && exists($0) }
            .map { directory.appendingPathComponent($0.fileName) }
    }

    func shareableAudioURLs(isRecording: Bool) -> [URL] {
        shareableAudioURLs(isRecording: isRecording) { audioExists(for: $0) }
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

    // MARK: Phase 18, what to do with a recording that produced nothing

    enum DiscardVerdict: Equatable, Sendable {
        case keep
        /// Deleted outright, audio and History row together.
        case discard(String)

        var discards: Bool { if case .discard = self { return true }; return false }
    }

    var hasFailedSegment: Bool { segments.contains { $0.state.isFailure } }

    /// Every segment finished and none of them heard anything.
    var isSilent: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.state.isEmptyResult }
    }

    /// Phase 18b and 18c.
    ///
    /// The asymmetry is deliberate. Discarding costs the user nothing when
    /// nothing was said, and costs them a meeting when something was: a failed
    /// segment can be retried and often succeeds, so it is never swept, and a
    /// long silent recording is kept because silence over a minute usually
    /// means a microphone problem the user needs to see.
    ///
    /// The under three seconds rule fires whatever the state, per 18b. At that
    /// length there is no meeting to lose, and it is what a mis-tap on the
    /// Action Button produces.
    var discardVerdict: DiscardVerdict {
        guard source == .recorded, isComplete else { return .keep }
        if duration < 3 { return .discard("under three seconds") }
        guard !hasFailedSegment else { return .keep }
        if isSilent && duration < 60 { return .discard("no speech, under a minute") }
        return .keep
    }

    /// What History says about a recording with no usable transcript.
    var emptyStateLabel: String? {
        guard source == .recorded, isComplete else { return nil }
        if hasFailedSegment { return "Transcription failed, tap to retry" }
        if isSilent { return "No speech detected" }
        return nil
    }

    /// True when the transcript holds something somebody actually said, rather
    /// than only the placeholders that stand in for segments which failed.
    /// Generating notes from placeholders alone means asking a model to
    /// summarise a meeting it never heard, and it will oblige.
    var hasTranscribedContent: Bool {
        !TranscriptStitcher.spokenContent(stitchedTranscript).isEmpty
    }

    /// Title precedence, used everywhere including the email subject:
    /// the user's own name, then the AI subject, then the date.
    /// A title has to survive three places: a list row, the Outlook subject, and
    /// the header line that sits outside the fenced transcript in the Ask and
    /// to-do prompts. A newline or a run of dashes there is at best a broken
    /// row and at worst something a model reads as the end of the fence.
    static func cleanTitle(_ raw: String) -> String {
        var cleaned = ResponseParser.collapseWhitespace(raw.replacingOccurrences(of: "|", with: " "))
        while cleaned.contains("--") {
            cleaned = cleaned.replacingOccurrences(of: "--", with: "-")
        }
        while cleaned.contains("==") {
            cleaned = cleaned.replacingOccurrences(of: "==", with: "=")
        }
        return SubjectBuilder.clip(cleaned, to: SubjectBuilder.maxTopicCharacters)
    }

    /// The title as it may appear next to untrusted text.
    var promptSafeTitle: String { RecordingSession.cleanTitle(displayTitle) }

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
