import XCTest
@testable import Sovox

/// Regression cover for the second audit round, which found that two of the
/// previous round's fixes were incomplete.
final class FixAuditRegressionTests: XCTestCase {

    private func session(_ states: [SegmentState], complete: Bool = true) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = complete
        s.segments = states.enumerated().map { index, state in
            SegmentRecord(index: index + 1,
                          fileName: RecordingPaths.segmentFileName(index + 1),
                          duration: 60,
                          state: state,
                          text: state == .done ? "text" : "")
        }
        return s
    }

    // MARK: The delete gate counted a failed segment as transcribed

    func testAFailedSegmentIsTerminalButNotFullyTranscribed() {
        let s = session([.done, .failed(reason: "recogniser gave up")])
        XCTAssertTrue(s.isTranscribed, "terminal means nothing is still in flight")
        XCTAssertFalse(s.isFullyTranscribed, "but a failed segment produced no text")
    }

    func testAudioCannotBeDeletedWhileASegmentFailed() {
        XCTAssertFalse(session([.done, .failed(reason: "x")]).canDeleteAudio,
                       "the audio is the only copy of those minutes")
    }

    func testAudioCanBeDeletedOnceEverySegmentSucceeded() {
        XCTAssertTrue(session([.done, .done]).canDeleteAudio)
    }

    func testStillRunningOrQueuedSegmentsAlsoBlockDeletion() {
        XCTAssertFalse(session([.done, .running]).canDeleteAudio)
        XCTAssertFalse(session([.done, .pending]).canDeleteAudio)
        XCTAssertFalse(session([.done, .deferred(reason: "warm")]).canDeleteAudio)
    }

    func testAnIncompleteRecordingNeverQualifies() {
        XCTAssertFalse(session([.done], complete: false).canDeleteAudio)
    }

    func testEmptySegmentsAreNotFullyTranscribed() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        XCTAssertFalse(s.isFullyTranscribed)
        XCTAssertFalse(s.canDeleteAudio)
    }

    // MARK: To-do source binding

    func testAToDoBindsToTheRecordingIdNotItsTitle() {
        let item = TodoItem(text: "do the thing",
                            sourceRecordingId: "sovox-20260822-1400",
                            sourceRecordingTitle: "Budget call",
                            origin: .ai)
        XCTAssertEqual(item.sourceRecordingId, "sovox-20260822-1400")
    }

    @MainActor
    func testApplyRecordsTheSourceIdWhenTheSessionIsKnown() {
        let store = TodoStore.shared
        var source = RecordingSession(id: "src-\(UUID().uuidString)", startDate: Date(), source: .pasted)
        source.transcript = "text"
        source.userTitle = "Budget call"

        let before = Set(store.items.map(\.id))
        store.apply([.add(text: "finalise pricing", priority: .high,
                          sourceTitle: "Budget call", context: "ctx")],
                    sources: [source])
        defer { store.items.filter { !before.contains($0.id) }.forEach { store.delete($0.id) } }

        let added = store.items.first { !before.contains($0.id) }
        XCTAssertEqual(added?.sourceRecordingId, source.id,
                       "binding by title alone lets a deleted recording rebind the link")
        XCTAssertEqual(added?.origin, .ai)
    }

    @MainActor
    func testApplyLeavesTheSourceIdNilWhenNoSessionMatches() {
        let store = TodoStore.shared
        let before = Set(store.items.map(\.id))
        store.apply([.add(text: "orphan", priority: .low,
                          sourceTitle: "A meeting that does not exist", context: "ctx")],
                    sources: [])
        defer { store.items.filter { !before.contains($0.id) }.forEach { store.delete($0.id) } }
        let added = store.items.first { !before.contains($0.id) }
        XCTAssertNil(added?.sourceRecordingId)
        XCTAssertEqual(added?.sourceRecordingTitle, "A meeting that does not exist")
    }
}

/// The refusal notice and the cancel affordance are only useful if they track
/// the flight they describe.
@MainActor
final class BridgeBusyNoticeTests: XCTestCase {

    func testABusyNoticeIsNotShownWhenNothingIsInFlight() {
        let handoff = HandoffCoordinator.shared
        XCTAssertFalse(handoff.isInFlight)
        XCTAssertNil(handoff.busyNotice, "a refusal about a finished flight is noise")
    }

    func testCancellingReleasesTheLockAndTheNotice() {
        let handoff = HandoffCoordinator.shared
        handoff.cancelInFlight()
        XCTAssertFalse(handoff.isInFlight)
        XCTAssertNil(handoff.busyNotice)
        XCTAssertNil(handoff.pendingAskAnswer)
        XCTAssertNil(handoff.pendingTodoResponse)
    }
}

/// To-dos written before the source id existed carry only a title.
final class TodoSourceResolutionTests: XCTestCase {

    private func recording(_ id: String, _ title: String) -> RecordingSession {
        var s = RecordingSession(id: id, startDate: Date(), source: .pasted)
        s.userTitle = title
        return s
    }

    private func todo(id: String?, title: String?) -> TodoItem {
        TodoItem(text: "t", sourceRecordingId: id, sourceRecordingTitle: title, origin: .ai)
    }

    func testTheIdWinsEvenWhenAnotherRecordingSharesTheTitle() {
        let sessions = [recording("a", "Budget call"), recording("b", "Budget call")]
        XCTAssertEqual(todo(id: "b", title: "Budget call").source(in: sessions)?.id, "b")
    }

    func testALegacyToDoStillResolvesByTitle() {
        let sessions = [recording("a", "Budget call")]
        XCTAssertEqual(todo(id: nil, title: "Budget call").source(in: sessions)?.id, "a",
                       "to-dos created before the id was stored must keep their link")
    }

    func testALegacyToDoDoesNotGuessBetweenTwoRecordingsOfTheSameName() {
        let sessions = [recording("a", "Budget call"), recording("b", "Budget call")]
        XCTAssertNil(todo(id: nil, title: "Budget call").source(in: sessions))
    }

    func testADeletedRecordingDoesNotRebindByTitle() {
        let sessions = [recording("b", "Budget call")]
        XCTAssertNil(todo(id: "gone", title: "Budget call").source(in: sessions),
                     "a set id that no longer resolves means the recording is gone")
    }

    func testNoTitleAndNoIdResolvesToNothing() {
        XCTAssertNil(todo(id: nil, title: nil).source(in: [recording("a", "x")]))
    }
}
