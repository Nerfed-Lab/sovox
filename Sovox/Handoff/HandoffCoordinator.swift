import Foundation
import Observation
import UIKit

/// Which flow is in flight. The bridge mechanism is shared, so sovox://done has
/// to know whether the answer belongs to the Outlook draft or to the Ask thread.
enum BridgePurpose: String, Codable, Sendable {
    case notes
    case ask
    case todos
    case verify
    case safety
}

/// Phase 10 Verify. The three failure modes are distinguished, because "it did
/// not work" sends the user round the same four steps with no idea which one is
/// wrong.
enum BridgeVerifyOutcome: Equatable, Sendable {
    /// x-success, and the reply says OK.
    case success
    /// x-error, and the result file was never touched. Shortcuts returns
    /// x-error both when no shortcut carries the name AND when one does and
    /// fails partway, so this cannot claim the shortcut is missing.
    case notFoundOrFailedEarly
    /// x-error, but the result file is newer than the request: it ran, got as
    /// far as saving something, and failed after that.
    case ranButFailedLater(String)
    /// x-success, but the reply is not OK. Almost always guidance text pasted
    /// into the prompt field, so the model answered a different question.
    case unexpectedContent(String)
    /// x-success, and nothing was written at all.
    case noResultFile
    /// Neither callback arrived inside a minute.
    case noResponse

    var isSuccess: Bool { self == .success }

    /// Never a raw error code. Every one of these says what to check next.
    var message: String {
        switch self {
        case .success:
            return "Round trip worked."
        case .notFoundOrFailedEarly:
            return "The Shortcut either does not exist under this exact name, or it failed before saving a result."
        case .ranButFailedLater(let got):
            return "The Shortcut ran and saved something, then failed. It wrote: \(BridgeVerifyOutcome.excerpt(got))"
        case .unexpectedContent(let got):
            return "The reply came back, but it is not OK. It says: \(BridgeVerifyOutcome.excerpt(got))"
        case .noResultFile:
            return "The Shortcut finished but never wrote the result file."
        case .noResponse:
            return "No response from Shortcuts inside a minute."
        }
    }

    /// What to try next, listed rather than left to the user to guess.
    var causes: [String] {
        switch self {
        case .success:
            return []
        case .notFoundOrFailedEarly:
            return ["The name does not match character for character.",
                    "Action 1 is pointing at the wrong file.",
                    "Action 3 is missing its Subpath."]
        case .ranButFailedLater:
            return ["Action 3 saved, then something after it failed.",
                    "Check nothing was added after Save File."]
        case .unexpectedContent:
            return ["Action 2's prompt field contains typed text as well as the File variable.",
                    "Action 1 is reading a different file."]
        case .noResultFile:
            return ["Action 3's Subpath is empty.",
                    "Action 3 is saving to a different folder."]
        case .noResponse:
            return ["The shortcut name is not exactly right.",
                    "Shortcuts did not open at all."]
        }
    }

    /// The probe asks for exactly OK, so the reply must be exactly OK.
    ///
    /// A substring test passed on any conversational answer that happens to
    /// contain those two letters, and ordinary ones do: "Okay, here is what I
    /// found", "It looks like you want me to use the file from action 1". That
    /// is defect 1 from the field report, the case this check exists to catch,
    /// and it was being reported as a working bridge and then persisted as
    /// verified. Punctuation and quoting around the word are tolerated because
    /// a model will add them; a sentence is not.
    static func isProbeSuccess(_ raw: String) -> Bool {
        let noise = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".!?,;:\"'`*_-"))
        return raw.trimmingCharacters(in: noise).uppercased() == "OK"
    }

    static func excerpt(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 200 ? trimmed : String(trimmed.prefix(200)) + "..."
    }
}

enum HandoffPhase: Equatable, Sendable {
    case idle
    case waitingForBridge
    case collectingResult
    case composed(subject: String)
    case needsShortcutSetup(AIDestination)
    case failed(String)
}

/// Drives the round trip: write the prompt to Documents, run the bridge
/// Shortcut through x-callback-url, read the answer back, open Outlook.
@MainActor
@Observable
final class HandoffCoordinator {
    static let shared = HandoffCoordinator()

    private(set) var phase: HandoffPhase = .idle
    /// Held until Outlook actually opens. iOS can refuse an open while the
    /// scene is still settling, and losing the draft would cost another whole
    /// round trip through the model.
    private(set) var pendingDraft: OutlookDraft?
    private var requestStartedAt = Date.distantPast
    /// Modification date of the result file at the moment the bridge was
    /// invoked. A reply is only this run's reply if the file is newer.
    private var resultBaseline = Date.distantPast
    /// Identifies the current verify run, so a timeout from an earlier one
    /// cannot overwrite the outcome of a later one.
    private var verifyToken = UUID()
    /// Phase 15f. Set when a manual test prompt has been written and the user
    /// has been told to run the Shortcut themselves.
    private(set) var manualTestArmed = false
    private(set) var manualTestResult: String?
    private var destination: AIDestination = .chatgpt
    private var sessionID: String?
    private var purpose: BridgePurpose = .notes

    /// The bridge is one channel: one pending file, one result file, one
    /// callback. Five flows share it. Without a lock a second request overwrites
    /// the first one's purpose and sessionID, and the first reply is then
    /// delivered to the wrong flow. That has been observed to put meeting notes
    /// into the Ask thread and to-do operation lines into an Outlook draft
    /// addressed to the user's real work email.
    /// A request recorded on disk, which survives the process dying. Distinct
    /// from isInFlight, which only knows what this process has seen.
    var hasPersistedRequest: Bool { requestStartedAt != .distantPast }

    /// Reads the persisted record the way a fresh process does. Exposed so the
    /// relaunch path can be asserted rather than reasoned about.
    func restoreForTesting() { restoreInFlightRequest() }

    var isInFlight: Bool {
        phase == .waitingForBridge || phase == .collectingResult
    }
    /// Set when an Ask answer comes back, consumed by the Ask screen.
    private(set) var pendingAskAnswer: String?
    private(set) var askQuestion: String?
    /// Set when a start is refused because another request owns the bridge.
    /// Read through busyNotice, which stops reporting it once that flight ends,
    /// so a refusal cannot sit on screen after the thing it refers to is gone.
    private var busyNoticeText: String?
    var busyNotice: String? { isInFlight ? busyNoticeText : nil }

    /// Which app the current flight went to. Not settings.destination: that is
    /// only the default and every flow can be overridden per recording.
    var inFlightDestination: AIDestination { destination }
    /// Raw operation lines from a to-do refresh, awaiting review. Nothing is
    /// applied until the user accepts it.
    private(set) var pendingTodoResponse: String?
    private(set) var pendingSafetyResponse: String?
    private(set) var verifyOutcome: BridgeVerifyOutcome?
    private(set) var verifyingDestination: AIDestination?

    private enum Keys {
        static let sessionID = "sovox.handoff.sessionID"
        static let destination = "sovox.handoff.destination"
        static let startedAt = "sovox.handoff.startedAt"
        static let purpose = "sovox.handoff.purpose"
        static let question = "sovox.handoff.question"
        static let strandedAnswer = "sovox.handoff.strandedAnswer"
        static let strandedQuestion = "sovox.handoff.strandedQuestion"
        static let strandedTodos = "sovox.handoff.strandedTodos"
        static let todoSources = "sovox.handoff.todoSources"
    }

    private init() {
        restoreInFlightRequest()
    }

    /// The Shortcuts round trip leaves this process eligible for jetsam. Without
    /// this, a kill mid run comes back with no sessionID, which used to mean a
    /// wrong dated subject, the model body on the clipboard instead of the
    /// transcript, and a stale result file accepted as fresh.
    private func persistInFlightRequest() {
        let defaults = UserDefaults.standard
        defaults.set(sessionID, forKey: Keys.sessionID)
        defaults.set(destination.rawValue, forKey: Keys.destination)
        defaults.set(requestStartedAt.timeIntervalSince1970, forKey: Keys.startedAt)
        defaults.set(purpose.rawValue, forKey: Keys.purpose)
        defaults.set(askQuestion, forKey: Keys.question)
    }

    private func restoreInFlightRequest() {
        let defaults = UserDefaults.standard
        purpose = BridgePurpose(rawValue: defaults.string(forKey: Keys.purpose) ?? "") ?? .notes
        askQuestion = defaults.string(forKey: Keys.question)
        destination = AIDestination(rawValue: defaults.string(forKey: Keys.destination) ?? "") ?? .chatgpt
        // Only the notes flow stores a sessionID. Gating the whole restore on it
        // meant requestStartedAt stayed distantPast for ask, todos, verify and
        // safety, isFresh then rejected every result, and the answer was lost on
        // exactly the relaunch path the durability work was written for.
        sessionID = defaults.string(forKey: Keys.sessionID)
        let stamp = defaults.double(forKey: Keys.startedAt)
        requestStartedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : .distantPast
    }

    /// Empties the result file rather than removing it, and records the
    /// baseline the next reply is compared against. Both files must survive:
    /// their presence in Files is what tells the user the app writes where the
    /// Shortcut reads.
    private func clearResultFile() {
        RecordingPaths.ensureBridgeFiles()
        try? "".write(to: RecordingPaths.resultFile, atomically: true, encoding: .utf8)
        resultBaseline = RecordingPaths.modificationDate(of: RecordingPaths.resultFile) ?? Date()
    }

    /// Phase 15d fallback and 15g diagnostics: whether the result file has been
    /// touched since the bridge was invoked.
    var resultFileIsNewerThanRequest: Bool {
        guard let modified = RecordingPaths.modificationDate(of: RecordingPaths.resultFile) else { return false }
        // After a relaunch there is no in memory baseline, so fall back to the
        // persisted start of the request. Comparing against distantPast would
        // call every stale file on disk this run's answer.
        let reference = resultBaseline == .distantPast ? requestStartedAt : resultBaseline
        guard reference != .distantPast else { return false }
        return modified > reference.addingTimeInterval(0.5)
    }

    private func clearInFlightRequest() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.sessionID)
        defaults.removeObject(forKey: Keys.destination)
        defaults.removeObject(forKey: Keys.startedAt)
        defaults.removeObject(forKey: Keys.purpose)
        defaults.removeObject(forKey: Keys.question)
        sessionID = nil
        requestStartedAt = .distantPast
        // The transcript still has to go: this directory is deliberately visible
        // in Files. The file itself stays, holding its placeholder, because it
        // is the only visible proof the app writes where the Shortcut reads.
        RecordingPaths.resetPendingPromptFile()
    }

    var shortcutsInstalled: Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    var outlookInstalled: Bool {
        guard let url = URL(string: "ms-outlook://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    nonisolated static func hasRequestedOutput(modes: Set<OutputMode>, customActions: [CustomAction]) -> Bool {
        !modes.isEmpty || !customActions.isEmpty
    }

    /// Step one. Writes the prompt where the Shortcut can read it, then hands
    /// control to Shortcuts. Only ever called while the app is foreground.
    func generate(session: RecordingSession,
                  modes: Set<OutputMode>,
                  customActions: [CustomAction] = [],
                  conversationType: ConversationType = .auto,
                  destination: AIDestination,
                  settings: AppSettings) {
        guard !isInFlight else {
            busyNoticeText = "Another request is still running. Wait for it to come back, or cancel it."
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            phase = .failed("Sovox can only hand off while it is on screen.")
            return
        }
        // A custom action is an output. The Generate button has always enabled
        // itself for one, so refusing here made an enabled button that could
        // only ever fail.
        guard HandoffCoordinator.hasRequestedOutput(modes: modes, customActions: customActions) else {
            phase = .failed("Pick at least one output type.")
            return
        }
        // Phase 15k. An unverified bridge fails somewhere in the middle of a
        // round trip, with the user staring at Shortcuts wondering what broke.
        // Say it here, where it is actionable.
        guard settings.isBridgeVerified(destination) else {
            phase = .failed("\(destination.title) bridge isn't set up, open Settings to finish it.")
            return
        }
        // Placeholders are not a transcript. Handing them over produces notes
        // for a meeting nobody heard, in a draft addressed to a real work
        // address.
        guard session.hasTranscribedContent else {
            phase = .failed(session.failedSegments.isEmpty
                            ? "There is no transcript yet."
                            : "Every segment failed to transcribe, so there is nothing to send. Retry them from the recording first.")
            return
        }

        self.destination = destination
        self.sessionID = session.id
        self.purpose = .notes
        self.askQuestion = nil

        let transcript = session.stitchedTranscript
        let prompt = PromptBuilder.build(transcript: transcript,
                                         modes: modes,
                                         customActions: customActions,
                                         conversationType: conversationType,
                                         ownName: settings.fullName,
                                         date: session.startDate)

        do {
            try prompt.write(to: RecordingPaths.pendingPromptFile, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Could not write sovox-pending.txt. \(error.localizedDescription)")
            return
        }

        // Remove any answer from a previous run so a stale file cannot be read
        // back as this run's result.
        clearResultFile()

        guard shortcutsInstalled else {
            phase = .needsShortcutSetup(destination)
            return
        }

        // The Shortcut name contains spaces and a hyphen, so every parameter is
        // percent encoded with the RFC 3986 unreserved set. urlQueryAllowed
        // would leave the callback URLs intact and break the query.
        let callbackSuccess = SovoxURL.done.absoluteString
        let callbackError = SovoxURL.failed.absoluteString
        let callbackCancel = SovoxURL.failed.absoluteString
        guard let url = URLEncoding.url(scheme: "shortcuts",
                                        path: "x-callback-url/run-shortcut",
                                        parameters: [
                                            ("name", destination.shortcutName),
                                            ("x-success", callbackSuccess),
                                            ("x-error", callbackError),
                                            ("x-cancel", callbackCancel)
                                        ]) else {
            phase = .failed("Could not build the Shortcuts callback URL.")
            return
        }

        requestStartedAt = Date()
        persistInFlightRequest()
        phase = .waitingForBridge
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in self.phase = .needsShortcutSetup(destination) }
        }
    }

    /// Phase 8. Same bridge, same file in and file out, different destination
    /// for the answer.
    func ask(question: String, prompt: String, destination: AIDestination) {
        guard !isInFlight else {
            busyNoticeText = "Another request is still running. Wait for it to come back, or cancel it."
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            phase = .failed("Sovox can only hand off while it is on screen.")
            return
        }
        do {
            try prompt.write(to: RecordingPaths.pendingPromptFile, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Could not write \(RecordingPaths.pendingPromptFile.lastPathComponent). \(error.localizedDescription)")
            return
        }
        clearResultFile()

        guard shortcutsInstalled else {
            phase = .needsShortcutSetup(destination)
            return
        }
        self.destination = destination
        self.purpose = .ask
        self.sessionID = nil
        self.askQuestion = question
        self.pendingAskAnswer = nil
        requestStartedAt = Date()
        persistInFlightRequest()
        phase = .waitingForBridge
        guard let url = bridgeURL(for: destination) else {
            phase = .failed("Could not build the Shortcuts callback URL.")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in self.phase = .needsShortcutSetup(destination) }
        }
    }

    private func bridgeURL(for destination: AIDestination) -> URL? {
        // The Shortcut name contains spaces and a hyphen, so every parameter is
        // percent encoded with the RFC 3986 unreserved set.
        URLEncoding.url(scheme: "shortcuts",
                        path: "x-callback-url/run-shortcut",
                        parameters: [
                            ("name", destination.shortcutName),
                            ("x-success", SovoxURL.done.absoluteString),
                            ("x-error", SovoxURL.failed.absoluteString),
                            ("x-cancel", SovoxURL.failed.absoluteString)
                        ])
    }

    /// Phase 9. Same bridge again.
    func refreshTodos(prompt: String, destination: AIDestination, sourceIDs: [String] = []) {
        guard !isInFlight else {
            busyNoticeText = "Another request is still running. Wait for it to come back, or cancel it."
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            phase = .failed("Sovox can only hand off while it is on screen.")
            return
        }
        do {
            try prompt.write(to: RecordingPaths.pendingPromptFile, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Could not write \(RecordingPaths.pendingPromptFile.lastPathComponent). \(error.localizedDescription)")
            return
        }
        clearResultFile()
        guard shortcutsInstalled, let url = bridgeURL(for: destination) else {
            phase = .needsShortcutSetup(destination)
            return
        }
        self.destination = destination
        self.purpose = .todos
        self.sessionID = nil
        self.pendingTodoResponse = nil
        // Which recordings went into this prompt, on disk rather than in the
        // view. The round trip leaves the app entirely, and a view held list
        // comes back empty after a jetsam: the watermark would never advance
        // and every one of those recordings would be proposed again.
        UserDefaults.standard.set(sourceIDs, forKey: Keys.todoSources)
        requestStartedAt = Date()
        persistInFlightRequest()
        phase = .waitingForBridge
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in self.phase = .needsShortcutSetup(destination) }
        }
    }

    /// Safe to call from a freshly created view. Returns the reply together
    /// with the recordings that produced it, so the watermark advances against
    /// the right set even after a relaunch.
    func consumeTodoResponse() -> (raw: String, sourceIDs: [String])? {
        let defaults = UserDefaults.standard
        let raw = pendingTodoResponse ?? defaults.string(forKey: Keys.strandedTodos)
        guard let raw, !raw.isEmpty else { return nil }
        let sources = defaults.stringArray(forKey: Keys.todoSources) ?? []
        pendingTodoResponse = nil
        defaults.removeObject(forKey: Keys.strandedTodos)
        defaults.removeObject(forKey: Keys.todoSources)
        return (raw, sources)
    }

    /// Which flow a returning result belongs to, read from the persisted record
    /// so it survives a relaunch, and read before collecting because collecting
    /// clears it.
    ///
    /// Sending every callback to the Record tab meant a user who asked a
    /// question came back to a screen with no sign of an answer. The answer was
    /// never lost, it just sat there until they happened to open Ask.
    var returningPurpose: BridgePurpose {
        let stored = UserDefaults.standard.string(forKey: Keys.purpose)
            .flatMap(BridgePurpose.init(rawValue:))
        return stored ?? purpose
    }

    /// Safe to call from a freshly created view. Falls back to the persisted
    /// pair so an answer that arrived while the Ask tab did not exist is still
    /// delivered. Cleared only once the caller has committed it.
    func consumeAskAnswer() -> (question: String, answer: String)? {
        let defaults = UserDefaults.standard
        let answer = pendingAskAnswer ?? defaults.string(forKey: Keys.strandedAnswer)
        let question = askQuestion ?? defaults.string(forKey: Keys.strandedQuestion)
        guard let answer, let question, !answer.isEmpty else { return nil }
        pendingAskAnswer = nil
        askQuestion = nil
        defaults.removeObject(forKey: Keys.strandedAnswer)
        defaults.removeObject(forKey: Keys.strandedQuestion)
        return (question, answer)
    }

    /// Step two, entered from sovox://done.
    /// Picks up a result nobody told us about.
    ///
    /// The callback is the last action of a Shortcut the user builds by hand, so
    /// it can be missing or mistyped, and a Shortcut that finishes while Sovox
    /// is backgrounded has nothing to open either. Only runs when the file is
    /// already there and belongs to this request, so returning to the app while
    /// the model is still thinking cannot cancel a request that is still alive.
    func collectIfResultWaiting(settings: AppSettings, store: RecordingStore) async {
        restoreInFlightRequest()
        // Deliberately not gated on isInFlight. That reads `phase`, which lives
        // in memory only, so after the jetsam this fallback exists for it is
        // always false and the answer was dropped in silence. The persisted
        // request plus the file's own date is what makes a result this run's.
        guard hasPersistedRequest, isFresh(RecordingPaths.resultFile),
              let text = try? String(contentsOf: RecordingPaths.resultFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await collectResult(settings: settings, store: store)
    }

    func collectResult(settings: AppSettings, store: RecordingStore) async {
        restoreInFlightRequest()
        phase = .collectingResult

        guard let raw = await pollForResult() else {
            if purpose == .verify {
                verifyOutcome = resultFileIsNewerThanRequest
                    ? .unexpectedContent((try? String(contentsOf: RecordingPaths.resultFile, encoding: .utf8)) ?? "")
                    : .noResultFile
                clearInFlightRequest()
                phase = .idle
                return
            }
            // Releases the bridge and removes the pending prompt, which holds
            // the full plaintext transcript.
            clearInFlightRequest()
            phase = .needsShortcutSetup(destination)
            return
        }

        if purpose == .safety {
            pendingSafetyResponse = raw
            clearInFlightRequest()
            phase = .idle
            return
        }

        if purpose == .verify {
            if BridgeVerifyOutcome.isProbeSuccess(raw) {
                verifyOutcome = .success
                // Recorded here, at the moment it is actually true, rather than
                // from a view lifecycle. The wizard used to mark it in the
                // outcome label's onAppear, which does not run again when a
                // failed verify is retried and succeeds: the label is already on
                // screen, so a working bridge was never recorded as verified.
                settings.markBridgeVerified(verifyingDestination ?? destination)
            } else {
                verifyOutcome = .unexpectedContent(raw)
            }
            clearInFlightRequest()
            phase = .idle
            return
        }

        if purpose == .todos {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Persisted for the same reason as the Ask answer: the To-dos tab
            // may not exist yet when this arrives, and an onChange cannot fire
            // for a value that was set before the view was created.
            UserDefaults.standard.set(trimmed, forKey: Keys.strandedTodos)
            pendingTodoResponse = trimmed
            clearInFlightRequest()
            phase = .idle
            return
        }

        if purpose == .ask {
            let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Persisted before the in flight record is cleared. Delivery used to
            // depend on an onChange inside AskView, and after a jetsam the app
            // relaunches on the Record tab, so that view had never been created
            // and both the question and the answer were lost silently.
            let defaults = UserDefaults.standard
            defaults.set(answer, forKey: Keys.strandedAnswer)
            defaults.set(askQuestion, forKey: Keys.strandedQuestion)
            pendingAskAnswer = answer
            clearInFlightRequest()
            phase = .idle
            return
        }

        // Substituting today's date and the model's own body for a session we
        // cannot resolve produces a plausible looking but wrong email. Say so
        // instead.
        guard let id = sessionID, let session = store.session(id: id) else {
            phase = .failed("The reply arrived but Sovox lost track of which recording it belongs to. Open it from History and press Generate again.")
            clearInFlightRequest()
            return
        }

        let parsed = ResponseParser.parse(raw)

        // The model's SUBJECT is stored, but a user title outranks it and is
        // never overwritten by a regeneration.
        var updated = session
        // The topic is model output, shaped by whatever was said in the
        // meeting, and it becomes the recording's title everywhere.
        let topic = RecordingSession.cleanTitle(parsed.topic)
        if !topic.isEmpty {
            updated.aiSubject = topic
        }
        store.upsert(updated)

        let subject = SubjectBuilder.subject(date: updated.startDate,
                                             topic: updated.subjectTopic,
                                             attendees: parsed.attendees,
                                             excluding: settings.fullName)

        // The full raw transcript goes on the clipboard so the body can be
        // long pressed and pasted into Outlook if the user wants it verbatim.
        UIPasteboard.general.string = updated.stitchedTranscript

        guard let draft = OutlookComposer.draft(to: settings.workEmail,
                                                subject: subject,
                                                body: parsed.body,
                                                date: updated.startDate) else {
            phase = .failed("Could not build the Outlook draft URL.")
            clearInFlightRequest()
            return
        }
        pendingDraft = draft
        clearInFlightRequest()

        guard outlookInstalled else {
            phase = .failed("Outlook is not installed. The notes are on your clipboard and the draft is ready under Open draft.")
            return
        }

        // sovox://done arrives while the scene is still inactive, so a strict
        // check here would refuse the open every single time. Wait for the
        // transition rather than treating it as a failure.
        await waitForActiveScene()
        if await openPendingDraft() { return }
        phase = .failed("iOS did not open Outlook. Tap Open draft to try again, the notes are on your clipboard.")
    }

    private func waitForActiveScene(attempts: Int = 25) async {
        for _ in 0..<attempts {
            if UIApplication.shared.applicationState == .active { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Safe to call repeatedly and from more than one caller. The draft is taken
    /// out of pendingDraft before the open is issued, so a second entry inside
    /// the flight window finds nothing and cannot open a duplicate Outlook
    /// draft. It is put back if iOS refuses, which is what keeps the Open draft
    /// button honest.
    @discardableResult
    func openPendingDraft() async -> Bool {
        guard let draft = pendingDraft else {
            if case .composed = phase { return true }
            return false
        }
        guard outlookInstalled, UIApplication.shared.applicationState == .active else { return false }

        pendingDraft = nil
        let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(draft.url, options: [:]) { result in
                continuation.resume(returning: result)
            }
        }

        guard opened else {
            pendingDraft = draft
            return false
        }

        phase = .composed(subject: draft.subject)
        if let file = draft.attachmentFile {
            Notifier.post(title: "Notes saved as a file",
                          body: "\(file.lastPathComponent) is in Files under \(RecordingPaths.filesLocation). Attach it to the draft.")
        }
        return true
    }

    func handleFailure() {
        // The callback can arrive into a fresh process, after a jetsam during
        // the round trip. Without this the purpose reads as its default and a
        // failed verify would be reported as a broken notes hand off.
        restoreInFlightRequest()
        if purpose == .verify {
            // Shortcuts returns x-error for a missing shortcut and for one that
            // exists and fails partway. The result file's date is what tells
            // them apart, and the old code asserted the first without checking.
            if resultFileIsNewerThanRequest {
                let raw = (try? String(contentsOf: RecordingPaths.resultFile, encoding: .utf8)) ?? ""
                verifyOutcome = .ranButFailedLater(raw)
            } else {
                verifyOutcome = .notFoundOrFailedEarly
            }
            clearInFlightRequest()
            phase = .idle
            return
        }
        clearInFlightRequest()
        phase = .needsShortcutSetup(destination)
    }

    /// Phase 10. Writes a tiny prompt, runs the bridge, and reports which of the
    /// three failure modes occurred.
    func verifyBridge(destination: AIDestination) {
        guard !isInFlight else {
            busyNoticeText = "Another request is still running. Wait for it to come back, or cancel it."
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            phase = .failed("Sovox can only hand off while it is on screen.")
            return
        }
        verifyOutcome = nil
        verifyingDestination = destination
        do {
            try "Reply with exactly: OK".write(to: RecordingPaths.pendingPromptFile,
                                               atomically: true, encoding: .utf8)
        } catch {
            verifyOutcome = .noResultFile
            return
        }
        clearResultFile()
        guard shortcutsInstalled, let url = bridgeURL(for: destination) else {
            verifyOutcome = .notFoundOrFailedEarly
            return
        }
        self.destination = destination
        self.purpose = .verify
        self.sessionID = nil
        requestStartedAt = Date()
        persistInFlightRequest()
        phase = .waitingForBridge
        armVerifyTimeout()
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard let self, !opened else { return }
            Task { @MainActor in self.verifyOutcome = .notFoundOrFailedEarly }
        }
    }

    /// Neither callback is guaranteed to arrive. Without this the wizard sits on
    /// a spinner with no verdict, which is indistinguishable from the app being
    /// broken.
    private func armVerifyTimeout(seconds: UInt64 = 60) {
        let token = UUID()
        verifyToken = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, self.verifyToken == token, self.purpose == .verify,
                  self.isInFlight, self.verifyOutcome == nil else { return }
            // The Shortcut may still have finished without telling us.
            if self.resultFileIsNewerThanRequest {
                let raw = (try? String(contentsOf: RecordingPaths.resultFile, encoding: .utf8)) ?? ""
                self.verifyOutcome = BridgeVerifyOutcome.isProbeSuccess(raw) ? .success : .unexpectedContent(raw)
                if self.verifyOutcome == .success {
                    AppSettings.shared.markBridgeVerified(self.verifyingDestination ?? self.destination)
                }
            } else {
                self.verifyOutcome = .noResponse
            }
            self.clearInFlightRequest()
            self.phase = .idle
        }
    }

    // MARK: Phase 15f, manual test

    /// Writes the probe prompt and stops. Deliberately does not invoke the
    /// Shortcut: running it by hand is what separates "the Shortcut is wrong"
    /// from "the app is invoking it wrong", and a user cannot tell those apart
    /// otherwise.
    @discardableResult
    func prepareManualTest() -> Bool {
        RecordingPaths.ensureBridgeFiles()
        clearResultFile()
        manualTestResult = nil
        do {
            try HandoffCoordinator.manualTestPrompt.write(to: RecordingPaths.pendingPromptFile,
                                                          atomically: true, encoding: .utf8)
            manualTestArmed = true
            return true
        } catch {
            manualTestArmed = false
            return false
        }
    }

    static let manualTestPrompt = "Reply with exactly: OK"

    /// Reads whatever is in the result file now and reports it verbatim.
    @discardableResult
    func checkManualResult() -> String {
        let raw = (try? String(contentsOf: RecordingPaths.resultFile, encoding: .utf8)) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            manualTestResult = "Nothing in \(RecordingPaths.resultFile.lastPathComponent) yet. Run the Shortcut in the Shortcuts app, then check again."
        } else if BridgeVerifyOutcome.isProbeSuccess(trimmed) {
            manualTestResult = "The Shortcut works. It wrote: \(BridgeVerifyOutcome.excerpt(trimmed))"
        } else {
            manualTestResult = "The Shortcut ran but replied with something else: \(BridgeVerifyOutcome.excerpt(trimmed))"
        }
        return manualTestResult ?? ""
    }

    func clearManualTest() {
        manualTestArmed = false
        manualTestResult = nil
    }

    /// Phase 12 Layer 2. Sends an already assembled prompt straight through the
    /// real bridge and hands the raw reply back untouched, so the harness can
    /// assert on what the model actually produced.
    func runSafetyProbe(prompt: String, destination: AIDestination) {
        guard !isInFlight else {
            busyNoticeText = "Another request is still running. Wait for it to come back, or cancel it."
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            phase = .failed("Sovox can only hand off while it is on screen.")
            return
        }
        do {
            try prompt.write(to: RecordingPaths.pendingPromptFile, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed("Could not write the probe prompt. \(error.localizedDescription)")
            return
        }
        clearResultFile()
        guard shortcutsInstalled, let url = bridgeURL(for: destination) else {
            phase = .needsShortcutSetup(destination)
            return
        }
        self.destination = destination
        self.purpose = .safety
        self.sessionID = nil
        self.pendingSafetyResponse = nil
        requestStartedAt = Date()
        persistInFlightRequest()
        phase = .waitingForBridge
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func consumeSafetyResponse() -> String? {
        defer { pendingSafetyResponse = nil }
        return pendingSafetyResponse
    }

    func clearVerifyOutcome() {
        verifyOutcome = nil
        verifyingDestination = nil
    }

    func clearBusyNotice() { busyNoticeText = nil }

    /// Releases the channel when a round trip never comes back.
    func cancelInFlight() {
        clearInFlightRequest()
        busyNoticeText = nil
        pendingAskAnswer = nil
        pendingTodoResponse = nil
        pendingSafetyResponse = nil
        askQuestion = nil
        phase = .idle
    }

    func reset() {
        clearInFlightRequest()
        pendingDraft = nil
        phase = .idle
    }

    /// Shortcuts may not have flushed the file by the time iOS returns control,
    /// so the read is retried over a short window instead of once.
    private func pollForResult(attempts: Int = 16) async -> String? {
        let url = RecordingPaths.resultFile
        for _ in 0..<attempts {
            if let contents = try? String(contentsOf: url, encoding: .utf8),
               !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               isFresh(url) {
                return contents
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    private func isFresh(_ url: URL) -> Bool {
        // No recorded in flight request means nothing on disk can be trusted as
        // this run's answer.
        guard requestStartedAt != .distantPast else { return false }
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate else { return false }
        return modified >= requestStartedAt.addingTimeInterval(-2)
    }
}
