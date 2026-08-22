import XCTest
@testable import Sovox

final class ResponseParserTests: XCTestCase {

    func testHeadersExtractedAndStripped() {
        let raw = """
        SUBJECT: Q3 Budget Reforecast
        ATTENDEES: Priya Sharma, Tom Weber

        ## Actions
        Ship the deck.
        """
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "Q3 Budget Reforecast")
        XCTAssertEqual(parsed.attendees, ["Priya Sharma", "Tom Weber"])
        XCTAssertFalse(parsed.body.contains("SUBJECT:"))
        XCTAssertFalse(parsed.body.contains("ATTENDEES:"))
        XCTAssertTrue(parsed.body.hasPrefix("## Actions"))
    }

    func testAttendeesLineWithNothingAfterIt() {
        let raw = """
        SUBJECT: Standup
        ATTENDEES:

        Body text.
        """
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "Standup")
        XCTAssertTrue(parsed.attendees.isEmpty)
        XCTAssertEqual(parsed.body, "Body text.")
    }

    func testHeaderLinesAbsentEntirely() {
        let raw = "Just a body with no headers at all.\nSecond line."
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "")
        XCTAssertTrue(parsed.attendees.isEmpty)
        XCTAssertEqual(parsed.body, raw)
    }

    func testLowercaseHeadersWithExtraWhitespace() {
        let raw = "   subject:    weekly    sync   \n  attendees:   Tom Weber ,  Priya Sharma \n\nBody."
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "weekly sync")
        XCTAssertEqual(parsed.attendees, ["Tom Weber", "Priya Sharma"])
        XCTAssertEqual(parsed.body, "Body.")
    }

    func testMarkdownDecoratedHeaders() {
        let raw = "**SUBJECT:** Pricing Review\n**ATTENDEES:** Tom Weber\n\nBody."
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "Pricing Review")
        XCTAssertEqual(parsed.attendees, ["Tom Weber"])
        XCTAssertEqual(parsed.body, "Body.")
    }

    func testAttendeesCappedAtThree() {
        let raw = "SUBJECT: X\nATTENDEES: A, B, C, D, E\n\nBody."
        XCTAssertEqual(ResponseParser.parse(raw).attendees, ["A", "B", "C"])
    }

    func testNoneAndNotApplicableAreTreatedAsEmpty() {
        XCTAssertTrue(ResponseParser.parse("SUBJECT: X\nATTENDEES: none\n\nBody.").attendees.isEmpty)
        XCTAssertTrue(ResponseParser.parse("SUBJECT: X\nATTENDEES: N/A\n\nBody.").attendees.isEmpty)
    }

    func testBodyContainingTheWordSubjectIsNotEaten() {
        let raw = "SUBJECT: X\n\nWe discussed the subject: pricing.\nMore body."
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "X")
        XCTAssertTrue(parsed.body.contains("We discussed the subject: pricing."))
    }

    func testHeadersDeepInTheDocumentAreIgnored() {
        let filler = Array(repeating: "line", count: 20).joined(separator: "\n")
        let parsed = ResponseParser.parse(filler + "\nSUBJECT: Too Late")
        XCTAssertEqual(parsed.topic, "")
        XCTAssertTrue(parsed.body.contains("SUBJECT: Too Late"))
    }

    func testCarriageReturnLineEndings() {
        let raw = "SUBJECT: CRLF Topic\r\nATTENDEES: Tom Weber\r\n\r\nBody."
        let parsed = ResponseParser.parse(raw)
        XCTAssertEqual(parsed.topic, "CRLF Topic")
        XCTAssertEqual(parsed.attendees, ["Tom Weber"])
    }
}
