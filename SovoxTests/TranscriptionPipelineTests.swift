import XCTest
@testable import Sovox

/// Phase 2. Stitching must never quietly shorten a transcript, and segment
/// state must survive a round trip to disk so a failure is still visible after
/// a relaunch.
final class TranscriptionPipelineTests: XCTestCase {

    private func record(_ index: Int, _ text: String, _ state: SegmentState) -> SegmentRecord {
        SegmentRecord(index: index,
                      fileName: RecordingPaths.segmentFileName(index),
                      duration: 60,
                      state: state,
                      text: text)
    }

    // MARK: Tolerant stitching

    func testAllSegmentsPresentStitchesInOrderWithMarkers() {
        let out = TranscriptStitcher.stitch(records: [
            record(1, "one", .done), record(2, "two", .done), record(3, "three", .done)
        ])
        XCTAssertTrue(out.hasPrefix("one"))
        XCTAssertTrue(out.contains(TranscriptStitcher.marker(for: 2)))
        XCTAssertTrue(out.hasSuffix("three"))
    }

    func testFailedMiddleSegmentLeavesAVisibleHole() {
        let out = TranscriptStitcher.stitch(records: [
            record(1, "one", .done),
            record(2, "", .failed(reason: "recogniser gave up")),
            record(3, "three", .done)
        ])
        XCTAssertTrue(out.contains(TranscriptStitcher.placeholder(for: 2)), out)
        XCTAssertTrue(out.contains("one"))
        XCTAssertTrue(out.contains("three"))
    }

    func testFailedFinalSegmentStillLeavesAHole() {
        let out = TranscriptStitcher.stitch(records: [
            record(1, "one", .done),
            record(2, "", .failed(reason: "file was never finalised"))
        ])
        XCTAssertTrue(out.hasSuffix(TranscriptStitcher.placeholder(for: 2)), out)
    }

    /// A segment still queued has not failed, it simply has not arrived, so it
    /// must not be branded as untranscribable.
    func testQueuedSegmentIsSkippedRatherThanMarkedFailed() {
        let out = TranscriptStitcher.stitch(records: [
            record(1, "one", .done), record(2, "", .pending)
        ])
        XCTAssertEqual(out, "one")
        XCTAssertFalse(out.contains("could not be transcribed"))
    }

    func testRunningAndDeferredSegmentsAreAlsoSkipped() {
        for state in [SegmentState.running, .deferred(reason: "warm")] {
            let out = TranscriptStitcher.stitch(records: [record(1, "one", .done), record(2, "", state)])
            XCTAssertEqual(out, "one", "\(state) should not produce a placeholder")
        }
    }

    func testEverySegmentFailedStillProducesAReadableDocument() {
        let out = TranscriptStitcher.stitch(records: [
            record(1, "", .failed(reason: "a")), record(2, "", .failed(reason: "b"))
        ])
        XCTAssertTrue(out.contains(TranscriptStitcher.placeholder(for: 1)))
        XCTAssertTrue(out.contains(TranscriptStitcher.placeholder(for: 2)))
        XCTAssertFalse(out.isEmpty)
    }

    func testNoRecordsProducesEmptyString() {
        XCTAssertEqual(TranscriptStitcher.stitch(records: []), "")
    }

    // MARK: State model

    func testStateRoundTripsThroughDiskWithItsReason() throws {
        let states: [SegmentState] = [.pending, .running, .done,
                                      .failed(reason: "boom"), .deferred(reason: "warm")]
        for state in states {
            let data = try JSONEncoder().encode(record(1, "", state))
            let back = try JSONDecoder().decode(SegmentRecord.self, from: data)
            XCTAssertEqual(back.state, state)
            XCTAssertEqual(back.state.reason, state.reason)
        }
    }

    func testOnlyDoneAndFailedAreTerminal() {
        XCTAssertTrue(SegmentState.done.isTerminal)
        XCTAssertTrue(SegmentState.failed(reason: "x").isTerminal)
        XCTAssertFalse(SegmentState.pending.isTerminal)
        XCTAssertFalse(SegmentState.running.isTerminal)
        XCTAssertFalse(SegmentState.deferred(reason: "x").isTerminal)
    }

    func testOnlyFailedCountsAsFailure() {
        XCTAssertTrue(SegmentState.failed(reason: "x").isFailure)
        for state in [SegmentState.pending, .running, .done, .deferred(reason: "x")] {
            XCTAssertFalse(state.isFailure)
        }
    }

    func testProgressCountsSettledSegmentsOnly() {
        var session = RecordingSession(id: "s", startDate: Date())
        session.segments = [record(1, "a", .done),
                            record(2, "", .failed(reason: "x")),
                            record(3, "", .running),
                            record(4, "", .pending)]
        XCTAssertEqual(session.transcriptionProgress, 0.5, accuracy: 0.001)
        XCTAssertFalse(session.isTranscribed)
        XCTAssertEqual(session.failedSegments.map(\.index), [2])
    }

    func testSessionIsTranscribedOnceEverySegmentSettles() {
        var session = RecordingSession(id: "s", startDate: Date())
        session.segments = [record(1, "a", .done), record(2, "", .failed(reason: "x"))]
        XCTAssertTrue(session.isTranscribed)
    }

    // MARK: Finalisation gate

    func testMissingFileIsRejectedBeforeItCanTranscribeToNothing() async {
        let url = RecordingPaths.documents.appendingPathComponent("does-not-exist.m4a")
        do {
            try await SegmentFinalisation.verify(url: url)
            XCTFail("a missing file must not reach the transcriber")
        } catch {
            XCTAssertEqual(error as? SegmentFinalisationError, .missing)
        }
    }

    func testZeroByteFileIsRejected() async throws {
        let url = RecordingPaths.documents.appendingPathComponent("empty-probe.m4a")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await SegmentFinalisation.verify(url: url)
            XCTFail("a zero byte file must not reach the transcriber")
        } catch {
            XCTAssertEqual(error as? SegmentFinalisationError, .emptyFile)
        }
    }

    /// The exact shape of the suspected original bug: bytes on disk, but no
    /// readable duration because the container was never finalised.
    func testFileWithBytesButNoReadableDurationIsRejected() async throws {
        let url = RecordingPaths.documents.appendingPathComponent("garbage-probe.m4a")
        try Data(repeating: 0x41, count: 4096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await SegmentFinalisation.verify(url: url)
            XCTFail("an unfinalised file must not reach the transcriber")
        } catch {
            let e = error as? SegmentFinalisationError
            XCTAssertTrue(e == .zeroDuration || e != nil, "expected a finalisation error, got \(error)")
        }
    }
}
