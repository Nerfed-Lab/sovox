import XCTest
@testable import Sovox

final class SubjectBuilderTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    // 21 Aug 2026, 14:30 UTC
    private let date = Date(timeIntervalSince1970: 1_787_322_600)

    private func subject(_ topic: String, _ names: [String], own: String = "") -> String {
        SubjectBuilder.subject(date: date, topic: topic, attendees: names, excluding: own, timeZone: utc)
    }

    func testDateAndTimeStampFormat() {
        XCTAssertTrue(subject("Q3 Budget Reforecast", []).hasPrefix("Sovox | 21 Aug 2026 | 14:30 | "))
    }

    func testNamesPresent() {
        let result = subject("Q3 Budget Reforecast", ["Priya Sharma", "Tom Weber"])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Q3 Budget Reforecast | Priya Sharma, Tom Weber")
    }

    func testNamesAbsent() {
        let result = subject("Q3 Budget Reforecast", [])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Q3 Budget Reforecast")
        XCTAssertFalse(result.hasSuffix("|"))
        XCTAssertFalse(result.hasSuffix(" | "))
    }

    func testSingleName() {
        XCTAssertEqual(subject("Pricing", ["Tom Weber"]),
                       "Sovox | 21 Aug 2026 | 14:30 | Pricing | Tom Weber")
    }

    func testThreeNames() {
        XCTAssertEqual(subject("Pricing", ["A One", "B Two", "C Three"]),
                       "Sovox | 21 Aug 2026 | 14:30 | Pricing | A One, B Two, C Three")
    }

    func testMoreThanThreeNamesAreTruncated() {
        let result = subject("Pricing", ["A One", "B Two", "C Three", "D Four"])
        XCTAssertFalse(result.contains("D Four"))
        XCTAssertTrue(result.hasSuffix("A One, B Two, C Three"))
    }

    func testNameContainingCommaIsPreservedAndDoesNotBreakTheJoin() {
        let result = subject("Legal review", ["Sharma, Priya"])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Legal review | Sharma, Priya")
        XCTAssertEqual(result.components(separatedBy: " | ").count, 5)
    }

    func testEmptyTopicDropsThatColumnEntirely() {
        let result = subject("", ["Tom Weber"])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Tom Weber")
        XCTAssertFalse(result.contains("|  |"))
        XCTAssertFalse(result.contains(" |  | "))
    }

    func testWhitespaceOnlyTopicAndNoNames() {
        let result = subject("   ", [])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30")
        XCTAssertFalse(result.hasSuffix("|"))
    }

    func testEmptyNamesInArrayAreDropped() {
        let result = subject("Pricing", ["", "   ", "Tom Weber"])
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Pricing | Tom Weber")
    }

    func testOwnNameIsExcluded() {
        let result = subject("Pricing", ["Rishabh Sinha", "Tom Weber"], own: "Rishabh Sinha")
        XCTAssertEqual(result, "Sovox | 21 Aug 2026 | 14:30 | Pricing | Tom Weber")
    }

    func testPipeInsideAValueCannotForgeAColumn() {
        let result = subject("Budget | Secret", ["Tom | Weber"])
        XCTAssertEqual(result.components(separatedBy: " | ").count, 5)
    }

    func testNeverEmitsATrailingOrDoubledSeparatorAcrossAMatrixOfInputs() {
        let topics = ["", "  ", "Topic", "A | B"]
        let nameSets: [[String]] = [[], [""], ["  "], ["One"], ["One", ""], ["One", "Two", "Three", "Four"]]
        for topic in topics {
            for names in nameSets {
                let result = subject(topic, names)
                XCTAssertFalse(result.hasSuffix(SubjectBuilder.separator), result)
                XCTAssertFalse(result.hasSuffix("|"), result)
                XCTAssertFalse(result.hasPrefix("|"), result)
                XCTAssertFalse(result.contains("|  |"), result)
                XCTAssertFalse(result.contains("||"), result)
            }
        }
    }
}
