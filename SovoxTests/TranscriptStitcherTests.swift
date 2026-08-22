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
