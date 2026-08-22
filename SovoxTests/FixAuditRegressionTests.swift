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

/// Documents is user visible in Files. A .m4a can therefore disappear while the
/// transcript that came out of it is the only remaining copy of that meeting.
final class SegmentPruningTests: XCTestCase {

    private func session(_ segments: [(String, String)]) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.segments = segments.enumerated().map { index, pair in
            SegmentRecord(index: index + 1,
                          fileName: pair.0,
                          duration: 60,
                          state: pair.1.isEmpty ? .pending : .done,
                          text: pair.1)
        }
        return s
    }

    func testASegmentWithTextSurvivesItsAudioVanishing() {
        let s = session([("seg-01.m4a", "first half"), ("seg-02.m4a", "second half")])
        let pruned = RecordingStore.pruneSegments(s) { $0 == "seg-02.m4a" }
        XCTAssertEqual(pruned.segments.count, 2, "dropping it would erase the transcript")
        XCTAssertEqual(pruned.stitchedTranscript.contains("first half"), true)
    }

    func testAnEmptySegmentWithNoAudioIsDiscarded() {
        let s = session([("seg-01.m4a", "kept"), ("seg-02.m4a", "")])
        let pruned = RecordingStore.pruneSegments(s) { $0 == "seg-01.m4a" }
        XCTAssertEqual(pruned.segments.map(\.fileName), ["seg-01.m4a"])
    }

    func testLosingEveryFileMarksTheSessionAsAudioRemoved() {
        let s = session([("seg-01.m4a", "words"), ("seg-02.m4a", "more words")])
        let pruned = RecordingStore.pruneSegments(s) { _ in false }
        XCTAssertTrue(pruned.audioRemoved, "stop offering share and retry for audio that is gone")
        XCTAssertFalse(pruned.hasAudio)
        XCTAssertEqual(pruned.segments.count, 2)
    }

    func testKeepingOneFileLeavesTheSessionPlayable() {
        let s = session([("seg-01.m4a", "words"), ("seg-02.m4a", "more words")])
        let pruned = RecordingStore.pruneSegments(s) { $0 == "seg-01.m4a" }
        XCTAssertFalse(pruned.audioRemoved)
        XCTAssertTrue(pruned.hasAudio)
    }

    func testNothingIsMarkedRemovedWhenThereWereNoSegments() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        XCTAssertFalse(RecordingStore.pruneSegments(s) { _ in false }.audioRemoved)
    }

    func testAudioExistsIsFalseOnceTheSessionSaysTheAudioIsGone() {
        var s = session([("seg-01.m4a", "words")])
        s.audioRemoved = true
        XCTAssertFalse(s.audioExists(for: s.segments[0]))
    }
}

/// An unreadable volume must not be mistaken for a full one.
final class StorageProbeTests: XCTestCase {

    func testAMeasurableVolumeStillReturnsAFigure() {
        let temp = FileManager.default.temporaryDirectory
        guard let free = StorageGuard.freeBytes(at: temp) else {
            return XCTFail("the temporary directory is always measurable")
        }
        XCTAssertGreaterThan(free, 0)
    }

    func testAVolumeThatDoesNotExistReadsAsUnknownRatherThanZero() {
        let missing = URL(fileURLWithPath: "/dev/null/no/such/volume/\(UUID().uuidString)")
        let free = StorageGuard.freeBytes(at: missing)
        XCTAssertNil(free, "zero would read as a full disk and stop a live recording")
    }

    func testTheHardStopStillFiresOnARealShortage() {
        XCTAssertTrue(StorageGuard.mustStop(freeBytes: 314_572_799))
        XCTAssertFalse(StorageGuard.mustStop(freeBytes: StorageGuard.criticalBytes))
    }

    func testStartIsStillRefusedUnderAGigabyte() {
        XCTAssertFalse(StorageGuard.canStart(freeBytes: StorageGuard.minimumStartBytes - 1))
        XCTAssertTrue(StorageGuard.canStart(freeBytes: StorageGuard.minimumStartBytes))
    }
}
