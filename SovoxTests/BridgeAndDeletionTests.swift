import XCTest
@testable import Sovox

/// Regression cover for the five defects found by the feature audit.
final class BridgeAndDeletionTests: XCTestCase {

    private func settled(_ id: String, text: String = "hello") -> RecordingSession {
        var s = RecordingSession(id: id, startDate: Date())
        s.isComplete = true
        s.segments = [SegmentRecord(index: 1, fileName: "seg-01.m4a", duration: 60,
                                    state: .done, text: text)]
        return s
    }

    private func unsettled(_ id: String) -> RecordingSession {
        var s = RecordingSession(id: id, startDate: Date())
        s.isComplete = true
        s.segments = [
            SegmentRecord(index: 1, fileName: "seg-01.m4a", duration: 60, state: .done, text: "first"),
            SegmentRecord(index: 2, fileName: "seg-02.m4a", duration: 60, state: .running, text: "")
        ]
        return s
    }

    // MARK: Audio deletion

    func testAudioCannotBeDeletedWhileASegmentIsStillTranscribing() {
        XCTAssertFalse(unsettled("a").canDeleteAudio,
                       "the audio is the only copy of the untranscribed part")
        XCTAssertTrue(settled("b").canDeleteAudio)
    }

    func testAudioCannotBeDeletedWhileTheRecordingIsStillRunning() {
        var live = settled("c")
        live.isComplete = false
        XCTAssertFalse(live.canDeleteAudio)
    }

    func testAlreadyRemovedAudioCannotBeRemovedAgain() {
        var gone = settled("d")
        gone.audioRemoved = true
        XCTAssertFalse(gone.hasAudio)
        XCTAssertFalse(gone.canDeleteAudio)
    }

    /// If the segment records are ever lost, the last persisted transcript is
    /// still better than an empty document.
    func testStitchedTranscriptFallsBackToTheStoredTranscript() {
        var session = RecordingSession(id: "e", startDate: Date())
        session.transcript = "recovered text"
        session.segments = []
        XCTAssertEqual(session.stitchedTranscript, "recovered text")
    }

    func testSegmentsStillWinOverTheStoredTranscriptWhenPresent() {
        var session = settled("f", text: "from segments")
        session.transcript = "stale"
        XCTAssertEqual(session.stitchedTranscript, "from segments")
    }

    // MARK: To-do watermark eligibility

    @MainActor
    func testAPartiallyTranscribedRecordingIsNotEligibleForIngestion() {
        let store = TodoStore.shared
        let pending = store.pendingSources(from: [unsettled("partial-\(UUID().uuidString)")])
        XCTAssertTrue(pending.isEmpty,
                      "sending a fragment then watermarking it as consumed loses the rest for good")
    }

    @MainActor
    func testASettledRecordingIsEligible() {
        let store = TodoStore.shared
        let id = "settled-\(UUID().uuidString)"
        XCTAssertEqual(store.pendingSources(from: [settled(id)]).map(\.id), [id])
    }

    @MainActor
    func testAStillRecordingSessionIsNotEligible() {
        let store = TodoStore.shared
        var live = settled("live-\(UUID().uuidString)")
        live.isComplete = false
        XCTAssertTrue(store.pendingSources(from: [live]).isEmpty)
    }

    @MainActor
    func testPastedTranscriptsAreEligibleWithoutSegments() {
        let store = TodoStore.shared
        let id = "pasted-\(UUID().uuidString)"
        var pasted = RecordingSession(id: id, startDate: Date(), source: .pasted)
        pasted.transcript = "typed in by hand"
        XCTAssertEqual(store.pendingSources(from: [pasted]).map(\.id), [id])
    }
}

/// Deleting the recording that is being written pulls the directory out from
/// under a live AVAudioFile. The write handle survives on an unlinked file, so
/// nothing reports an error until the audio is already gone.
@MainActor
final class LiveSessionDeletionTests: XCTestCase {

    private func makeSession(_ store: RecordingStore) -> RecordingSession {
        var s = RecordingSession(id: "protect-\(UUID().uuidString)", startDate: Date(), source: .pasted)
        s.transcript = "text"
        s.isComplete = true
        store.upsert(s)
        return s
    }

    func testTheProtectedSessionCannotBeDeleted() {
        let store = RecordingStore.shared
        let session = makeSession(store)
        defer { store.protectedSessionID = nil; store.delete(session) }

        store.protectedSessionID = session.id
        XCTAssertFalse(store.canDelete(session.id))
        XCTAssertFalse(store.delete(session))
        XCTAssertNotNil(store.session(id: session.id), "it is still on disk and still being written")
    }

    func testDeleteAllSpareTheProtectedSession() {
        let store = RecordingStore.shared
        let session = makeSession(store)
        defer { store.protectedSessionID = nil; store.delete(session) }

        store.protectedSessionID = session.id
        store.deleteAll()
        XCTAssertNotNil(store.session(id: session.id))
    }

    func testTheProtectionLiftsOnceRecordingStops() {
        let store = RecordingStore.shared
        let session = makeSession(store)
        store.protectedSessionID = session.id
        store.protectedSessionID = nil
        XCTAssertTrue(store.canDelete(session.id))
        XCTAssertTrue(store.delete(session))
        XCTAssertNil(store.session(id: session.id))
    }

    func testAudioDeletionIsRefusedForTheProtectedSession() {
        let store = RecordingStore.shared
        let session = makeSession(store)
        defer { store.protectedSessionID = nil; store.delete(session) }

        store.protectedSessionID = session.id
        XCTAssertFalse(store.deleteAudio(session))
    }
}
