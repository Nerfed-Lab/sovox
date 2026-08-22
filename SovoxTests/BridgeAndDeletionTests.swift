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
