import XCTest
@testable import Sovox

final class HandoffTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_787_322_600)

    func testPromptCarriesTheHeaderContract() {
        let prompt = PromptBuilder.build(transcript: "hello",
                                         modes: [.actionsAndDecisions],
                                         ownName: "Rishabh Sinha",
                                         date: date,
                                         timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(prompt.contains("SUBJECT:"))
        XCTAssertTrue(prompt.contains("ATTENDEES:"))
        XCTAssertTrue(prompt.contains("Never list them under ATTENDEES"))
        XCTAssertTrue(prompt.contains("--- TRANSCRIPT BEGINS ---"))
        XCTAssertTrue(prompt.contains("hello"))
    }

    func testPromptOnlyIncludesSelectedSections() {
        let prompt = PromptBuilder.build(transcript: "t",
                                         modes: [.taskPrompts],
                                         ownName: "",
                                         date: date)
        XCTAssertTrue(prompt.contains("## Task prompts"))
        XCTAssertFalse(prompt.contains("## Cleaned transcript"))
        XCTAssertFalse(prompt.contains("## Actions & decision logs"))
    }

    func testPromptSectionsKeepACanonicalOrder() throws {
        let prompt = PromptBuilder.build(transcript: "t",
                                         modes: Set(OutputMode.allCases),
                                         ownName: "",
                                         date: date)
        let cleaned = try XCTUnwrap(prompt.range(of: "## Cleaned transcript")).lowerBound
        let summary = try XCTUnwrap(prompt.range(of: "TRANSCRIPT SUMMARY")).lowerBound
        let actions = try XCTUnwrap(prompt.range(of: "## Actions & decision logs")).lowerBound
        let tasks = try XCTUnwrap(prompt.range(of: "## Task prompts")).lowerBound
        XCTAssertTrue(cleaned < summary, "cleaned transcript must come before the summary")
        XCTAssertTrue(summary < actions, "summary must come before actions")
        XCTAssertTrue(actions < tasks, "actions must come before task prompts")
    }

    func testShortBodyGoesStraightIntoTheURL() {
        let draft = OutlookComposer.draft(to: "a@b.com", subject: "S", body: "short body", date: date)
        let unwrapped = try! XCTUnwrap(draft)
        XCTAssertNil(unwrapped.attachmentFile)
        XCTAssertTrue(unwrapped.url.absoluteString.hasPrefix("ms-outlook://compose?"))
        XCTAssertTrue(unwrapped.url.absoluteString.contains("to=a%40b.com"))
    }

    func testEmptyRecipientOmitsTheToParameter() {
        let draft = try! XCTUnwrap(OutlookComposer.draft(to: "  ", subject: "S", body: "b", date: date))
        XCTAssertFalse(draft.url.absoluteString.contains("to="))
        XCTAssertTrue(draft.url.absoluteString.contains("subject=S"))
    }

    func testOversizeBodyIsWrittenToAFileAndReplacedWithAPointer() {
        let long = String(repeating: "word ", count: 2000)
        XCTAssertGreaterThan(URLEncoding.encode(long).count, OutlookComposer.encodedBodyLimit)
        let draft = try! XCTUnwrap(OutlookComposer.draft(to: "a@b.com", subject: "S", body: long, date: date))
        let file = try! XCTUnwrap(draft.attachmentFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), long)
        XCTAssertTrue(draft.url.absoluteString.contains(URLEncoding.encode(file.lastPathComponent)))
        try? FileManager.default.removeItem(at: file)
    }

    func testEndToEndResponseToSubject() {
        let response = """
        SUBJECT: Q3 Budget Reforecast
        ATTENDEES: Priya Sharma, Tom Weber

        Decisions
        Hold the hiring plan & revisit in October #q4
        """
        let parsed = ResponseParser.parse(response)
        let subject = SubjectBuilder.subject(date: date,
                                             topic: parsed.topic,
                                             attendees: parsed.attendees,
                                             excluding: "Rishabh Sinha",
                                             timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(subject, "Sovox | 21 Aug 2026 | 14:30 | Q3 Budget Reforecast | Priya Sharma, Tom Weber")

        let draft = try! XCTUnwrap(OutlookComposer.draft(to: "me@work.com", subject: subject, body: parsed.body, date: date))
        let string = draft.url.absoluteString
        let bodyPart = String(string.split(separator: "body=").last!)
        XCTAssertEqual(URLEncoding.decode(bodyPart), parsed.body)
        XCTAssertTrue(parsed.body.contains("&"))
        XCTAssertTrue(parsed.body.contains("#q4"))
    }

    func testBridgeRecipeHasExactlyFourActions() {
        XCTAssertEqual(BridgeShortcutRecipe.steps(for: .chatgpt).count, 4)
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .chatgpt), "Sovox Bridge - ChatGPT")
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .claude), "Sovox Bridge - Claude")
    }
}
