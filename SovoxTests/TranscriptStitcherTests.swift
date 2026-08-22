import XCTest
@testable import Sovox

final class TranscriptStitcherTests: XCTestCase {

    func testSegmentsInOrder() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 1, text: "one"),
            SegmentTranscript(index: 2, text: "two"),
            SegmentTranscript(index: 3, text: "three")
        ])
        XCTAssertEqual(result, """
        one

        --- [segment 2 begins] ---

        two

        --- [segment 3 begins] ---

        three
        """)
    }

    func testOutOfOrderInputIsSortedByIndex() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 3, text: "three"),
            SegmentTranscript(index: 1, text: "one"),
            SegmentTranscript(index: 2, text: "two")
        ])
        XCTAssertTrue(result.hasPrefix("one"))
        XCTAssertTrue(result.hasSuffix("three"))
    }

    func testMissingMiddleSegmentKeepsTrueIndicesInTheMarkers() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 1, text: "one"),
            SegmentTranscript(index: 3, text: "three")
        ])
        XCTAssertTrue(result.contains("--- [segment 3 begins] ---"))
        XCTAssertFalse(result.contains("segment 2 begins"))
    }

    func testZeroLengthFinalSegmentProducesNoTrailingMarker() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 1, text: "one"),
            SegmentTranscript(index: 2, text: "two"),
            SegmentTranscript(index: 3, text: "")
        ])
        XCTAssertFalse(result.contains("segment 3 begins"))
        XCTAssertTrue(result.hasSuffix("two"))
    }

    func testWhitespaceOnlySegmentIsDropped() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 1, text: "one"),
            SegmentTranscript(index: 2, text: "   \n  ")
        ])
        XCTAssertEqual(result, "one")
    }

    func testEmptyInput() {
        XCTAssertEqual(TranscriptStitcher.stitch([]), "")
    }

    func testSingleSegmentHasNoMarker() {
        XCTAssertEqual(TranscriptStitcher.stitch([SegmentTranscript(index: 1, text: "only")]), "only")
    }

    func testFirstSurvivingSegmentNeverGetsAMarkerEvenIfItIsNotIndexOne() {
        let result = TranscriptStitcher.stitch([
            SegmentTranscript(index: 2, text: "two"),
            SegmentTranscript(index: 4, text: "four")
        ])
        XCTAssertTrue(result.hasPrefix("two"))
        XCTAssertFalse(result.contains("segment 2 begins"))
        XCTAssertTrue(result.contains("--- [segment 4 begins] ---"))
    }

    func testPreviewTakesFirstNonEmptyLine() {
        XCTAssertEqual(TranscriptStitcher.preview("\n\n  Hello there\nSecond"), "Hello there")
        XCTAssertEqual(TranscriptStitcher.preview(""), "")
    }
}

/// A transcript made only of gap placeholders is not a transcript.
final class SpokenContentTests: XCTestCase {

    private func session(_ states: [SegmentState], texts: [String]) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.segments = zip(states, texts).enumerated().map { index, pair in
            SegmentRecord(index: index + 1,
                          fileName: RecordingPaths.segmentFileName(index + 1),
                          duration: 60,
                          state: pair.0,
                          text: pair.1)
        }
        return s
    }

    func testPlaceholdersAndMarkersAreNotContent() {
        let s = session([.failed(reason: "x"), .failed(reason: "y")], texts: ["", ""])
        XCTAssertFalse(s.stitchedTranscript.isEmpty, "the holes are still shown to the user")
        XCTAssertFalse(s.hasTranscribedContent, "but there is nothing to summarise")
    }

    func testOneSurvivingSegmentIsEnough() {
        let s = session([.failed(reason: "x"), .done], texts: ["", "we agreed the budget"])
        XCTAssertTrue(s.hasTranscribedContent)
        XCTAssertTrue(TranscriptStitcher.spokenContent(s.stitchedTranscript)
            .contains("we agreed the budget"))
    }

    func testSpokenContentStripsTheSegmentMarkers() {
        let stitched = TranscriptStitcher.stitch(records: [
            SegmentRecord(index: 1, fileName: "seg-01.m4a", duration: 60, state: .done, text: "one"),
            SegmentRecord(index: 2, fileName: "seg-02.m4a", duration: 60, state: .done, text: "two")
        ])
        XCTAssertTrue(stitched.contains(TranscriptStitcher.marker(for: 2)))
        XCTAssertEqual(TranscriptStitcher.spokenContent(stitched), "one\ntwo")
    }

    func testAPastedTranscriptIsContent() {
        var s = RecordingSession(id: "s", startDate: Date(), source: .pasted)
        s.transcript = "pasted from an email"
        XCTAssertTrue(s.hasTranscribedContent)
    }

    func testAnEmptySessionHasNoContent() {
        XCTAssertFalse(RecordingSession(id: "s", startDate: Date()).hasTranscribedContent)
    }
}
