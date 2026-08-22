import XCTest
@testable import Sovox

/// Phase 4. Title precedence and the subject prefix, including E15 through E19.
final class TitleAndSubjectTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_787_322_600) // 21 Aug 2026, 14:30 UTC

    private func session(userTitle: String? = nil, aiSubject: String? = nil) -> RecordingSession {
        RecordingSession(id: "s", startDate: date, userTitle: userTitle, aiSubject: aiSubject)
    }

    private func subject(_ topic: String, _ names: [String], own: String = "") -> String {
        SubjectBuilder.subject(date: date, topic: topic, attendees: names, excluding: own, timeZone: utc)
    }

    // MARK: E14, precedence

    func testUserTitleOutranksAISubject() {
        XCTAssertEqual(session(userTitle: "My name", aiSubject: "AI name").displayTitle, "My name")
    }

    func testAISubjectUsedWhenNoUserTitle() {
        XCTAssertEqual(session(aiSubject: "AI name").displayTitle, "AI name")
    }

    func testDateUsedWhenNeitherIsSet() {
        let s = session()
        XCTAssertEqual(s.displayTitle, s.dateLine)
        XCTAssertFalse(s.hasTitle)
        XCTAssertEqual(s.subjectTopic, "")
    }

    func testWhitespaceOnlyTitlesDoNotCount() {
        let s = session(userTitle: "   ", aiSubject: "  ")
        XCTAssertEqual(s.displayTitle, s.dateLine)
        XCTAssertFalse(s.hasTitle)
    }

    func testWhitespaceOnlyUserTitleFallsThroughToAISubject() {
        XCTAssertEqual(session(userTitle: " ", aiSubject: "AI name").displayTitle, "AI name")
    }

    // MARK: E18, E19, prefix

    func testPrefixIsDerivedFromTheDisplayNameNotHardcoded() {
        let display = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        XCTAssertEqual(SubjectBuilder.appPrefix, display)
        XCTAssertEqual(SubjectBuilder.appPrefix, "Sovox")
    }

    func testSubjectAlwaysCarriesThePrefix() {
        let cases: [(String, [String])] = [
            ("Topic", ["A One", "B Two", "C Three"]),
            ("Topic", ["A One"]),
            ("Topic", []),
            ("", []),
            ("", ["A One"]),
            ("   ", ["  "]),
        ]
        for (topic, names) in cases {
            XCTAssertTrue(subject(topic, names).hasPrefix("Sovox | "), "\(topic) \(names)")
        }
    }

    func testExampleSubjectsMatchTheSpecExactly() {
        XCTAssertEqual(subject("Q3 Budget Reforecast", ["Priya Sharma", "Tom Weber"]),
                       "Sovox | 21 Aug 2026 | 14:30 | Q3 Budget Reforecast | Priya Sharma, Tom Weber")
        XCTAssertEqual(subject("Vendor Contract Renewal", []),
                       "Sovox | 21 Aug 2026 | 14:30 | Vendor Contract Renewal")
    }

    // MARK: E16, separators

    func testAttendeeSegmentAndItsSeparatorCollapseTogether() {
        let out = subject("Topic", [])
        XCTAssertEqual(out, "Sovox | 21 Aug 2026 | 14:30 | Topic")
        XCTAssertFalse(out.hasSuffix(" | "))
        XCTAssertFalse(out.contains(" |  | "))
    }

    func testNeverEmitsATrailingOrDoubledSeparatorAcrossAMatrix() {
        let topics = ["", "  ", "Topic", "A | B"]
        let nameSets: [[String]] = [[], [""], ["  "], ["One"], ["One", "Two", "Three", "Four"]]
        for topic in topics {
            for names in nameSets {
                let out = subject(topic, names)
                XCTAssertFalse(out.hasSuffix(SubjectBuilder.separator), out)
                XCTAssertFalse(out.hasSuffix("|"), out)
                XCTAssertFalse(out.contains(" |  | "), out)
                XCTAssertFalse(out.contains("||"), out)
                XCTAssertTrue(out.hasPrefix("Sovox | "), out)
            }
        }
    }

    // MARK: E15, stickiness

    func testSubjectUsesUserTitleOverAISubject() {
        let s = session(userTitle: "My name", aiSubject: "AI name")
        XCTAssertEqual(subject(s.subjectTopic, []),
                       "Sovox | 21 Aug 2026 | 14:30 | My name")
    }

    func testStoringANewAISubjectDoesNotDisturbAUserTitle() {
        var s = session(userTitle: "My name")
        s.aiSubject = "Regenerated"
        XCTAssertEqual(s.userTitle, "My name")
        XCTAssertEqual(s.displayTitle, "My name")
        XCTAssertEqual(s.subjectTopic, "My name")
    }

    func testClearingAUserTitleFallsBackToTheStoredAISubject() {
        var s = session(userTitle: "My name", aiSubject: "AI name")
        s.userTitle = nil
        XCTAssertEqual(s.displayTitle, "AI name")
    }
}
