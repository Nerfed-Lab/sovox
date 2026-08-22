import XCTest
@testable import Sovox

/// Phase 8. E25 and E26.
final class AskTests: XCTestCase {

    private func source(_ title: String, _ chars: Int) -> AskPromptBuilder.Source {
        AskPromptBuilder.Source(title: title,
                                date: "21 Aug 2026",
                                transcript: String(repeating: "x", count: chars))
    }

    // MARK: E25, the guard blocks rather than truncating

    func testUnderFortyThousandProceeds() {
        XCTAssertEqual(AskContextGuard.verdict(characterCount: 0), .ok)
        XCTAssertEqual(AskContextGuard.verdict(characterCount: 39_999), .ok)
    }

    func testFortyToOneHundredThousandWarns() {
        for count in [40_000, 70_000, 100_000] {
            guard case .warn = AskContextGuard.verdict(characterCount: count) else {
                return XCTFail("\(count) should warn")
            }
        }
    }

    func testAboveOneHundredThousandBlocks() {
        let verdict = AskContextGuard.verdict(characterCount: 100_001)
        XCTAssertTrue(verdict.blocks)
        guard case .block(let message) = verdict else { return XCTFail("expected block") }
        XCTAssertTrue(message.contains("Deselect"))
    }

    func testBoundariesAreExact() {
        XCTAssertFalse(AskContextGuard.verdict(characterCount: 100_000).blocks)
        XCTAssertTrue(AskContextGuard.verdict(characterCount: 100_001).blocks)
    }

    func testCombinedCountSumsEverySelectedSource() {
        let sources = [source("A", 1000), source("B", 2500)]
        XCTAssertEqual(AskPromptBuilder.combinedCharacterCount(sources), 3500)
    }

    // MARK: E26, grounding and attribution

    func testPromptDemandsAttributionAndRefusesToSpeculate() {
        let text = AskPromptBuilder.build(question: "What was agreed?",
                                          sources: [source("Budget call", 10)],
                                          history: [])
        XCTAssertTrue(text.contains("Answer only from the transcripts provided."))
        XCTAssertTrue(text.contains("Not covered in the selected recordings"))
        XCTAssertTrue(text.contains("(Source: <recording title>)"))
        XCTAssertTrue(text.contains("Never speculate"))
        XCTAssertTrue(text.contains("Plain text. No markdown."))
    }

    func testEachSourceIsDelimitedWithItsTitleAndDate() {
        let text = AskPromptBuilder.build(question: "q",
                                          sources: [source("Budget call", 5), source("Vendor sync", 5)],
                                          history: [])
        XCTAssertTrue(text.contains("=== Budget call (21 Aug 2026) ==="))
        XCTAssertTrue(text.contains("=== Vendor sync (21 Aug 2026) ==="))
    }

    /// The bridge is stateless, so a follow up only works if prior turns are
    /// resent.
    func testPriorTurnsAreResentSoFollowUpsWork() {
        let history = [AskTurn(question: "Who owns pricing?", answer: "Tom (Source: Budget call)")]
        let text = AskPromptBuilder.build(question: "And by when?",
                                          sources: [source("Budget call", 5)],
                                          history: history)
        XCTAssertTrue(text.contains("Q: Who owns pricing?"))
        XCTAssertTrue(text.contains("A: Tom (Source: Budget call)"))
        XCTAssertTrue(text.contains("QUESTION:\nAnd by when?"))
    }

    func testEmptyHistoryIsStatedAsNoneRatherThanLeftBlank() {
        let text = AskPromptBuilder.build(question: "q", sources: [source("A", 5)], history: [])
        XCTAssertTrue(text.contains("PREVIOUS Q&A IN THIS SESSION:\nnone"))
    }

    func testQuestionIsTheFinalSection() {
        let text = AskPromptBuilder.build(question: "the last thing", sources: [source("A", 5)], history: [])
        XCTAssertTrue(text.hasSuffix("QUESTION:\nthe last thing"))
    }
}

/// The bridge is stateless, so every prior turn is resent. Nothing bounded that,
/// and the context guard counted only the transcripts.
final class AskHistoryBudgetTests: XCTestCase {

    private func turn(_ size: Int, index: Int) -> AskTurn {
        AskTurn(question: "q\(index)", answer: String(repeating: "a", count: size))
    }

    private let source = AskPromptBuilder.Source(title: "T", date: "d", transcript: "transcript")

    func testOldTurnsAreDroppedOldestFirst() {
        let history = (1...10).map { turn(3_000, index: $0) }
        let kept = AskPromptBuilder.recentHistory(history)
        XCTAssertLessThanOrEqual(AskPromptBuilder.historyCharacterCount(kept),
                                 AskPromptBuilder.historyBudget)
        XCTAssertEqual(kept.last?.question, "q10", "the most recent turn always survives")
        XCTAssertFalse(kept.contains { $0.question == "q1" })
    }

    func testASingleOversizedTurnIsStillKept() {
        let history = [turn(50_000, index: 1)]
        XCTAssertEqual(AskPromptBuilder.recentHistory(history).count, 1,
                       "a follow up must not lose the question it follows")
    }

    func testTheGuardCountsTheHistoryItWillActuallySend() {
        let history = (1...5).map { turn(2_000, index: $0) }
        let counted = AskPromptBuilder.promptCharacterCount(sources: [source], history: history)
        XCTAssertGreaterThan(counted, AskPromptBuilder.combinedCharacterCount([source]),
                             "counting transcripts alone shows green while the prompt is far bigger")
    }

    func testAnElidedThreadSaysSo() {
        let history = (1...10).map { turn(3_000, index: $0) }
        let prompt = AskPromptBuilder.build(question: "next", sources: [source], history: history)
        XCTAssertTrue(prompt.contains("earlier exchanges not included"))
        XCTAssertFalse(prompt.contains("q1\n"), "the dropped turns are really gone")
    }

    func testAShortThreadIsSentWholeWithNoNotice() {
        let history = [turn(10, index: 1), turn(10, index: 2)]
        let prompt = AskPromptBuilder.build(question: "next", sources: [source], history: history)
        XCTAssertFalse(prompt.contains("earlier exchanges not included"))
        XCTAssertTrue(prompt.contains("q1"))
        XCTAssertTrue(prompt.contains("q2"))
    }
}
