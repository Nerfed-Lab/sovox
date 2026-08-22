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
