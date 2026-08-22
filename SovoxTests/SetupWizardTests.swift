import XCTest
@testable import Sovox

/// Phase 10. E31 and E33.
final class SetupWizardTests: XCTestCase {

    // MARK: E31, the three failure modes are distinguishable

    func testEveryVerifyOutcomeCarriesItsOwnDistinctExplanation() {
        let outcomes: [BridgeVerifyOutcome] = [
            .success, .shortcutNotFound, .noResultFile, .unexpectedContent("garbage")
        ]
        let messages = outcomes.map(\.message)
        XCTAssertEqual(Set(messages).count, outcomes.count, "two outcomes share a message")
        for message in messages {
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testShortcutNotFoundPointsAtTheName() {
        XCTAssertTrue(BridgeVerifyOutcome.shortcutNotFound.message.lowercased().contains("name"))
    }

    func testNoResultFilePointsAtTheSaveAction() {
        let message = BridgeVerifyOutcome.noResultFile.message.lowercased()
        XCTAssertTrue(message.contains("result file"))
        XCTAssertTrue(message.contains("overwrite"))
    }

    func testUnexpectedContentQuotesWhatCameBack() {
        XCTAssertTrue(BridgeVerifyOutcome.unexpectedContent("banana").message.contains("banana"))
    }

    // MARK: E33, wizard copy matches the live names and paths

    func testSetupRowsMatchTheRealFileNamesAndCallback() {
        for destination in AIDestination.allCases {
            let rows = BridgeShortcutRecipe.setupRows(for: destination)
            XCTAssertEqual(rows.count, 4, "the bridge is four actions")

            XCTAssertTrue(rows[0].value.contains(RecordingPaths.pendingPromptFile.lastPathComponent))
            XCTAssertTrue(rows[0].value.contains(RecordingPaths.filesLocation))

            XCTAssertTrue(rows[1].action.contains(destination.title))

            XCTAssertTrue(rows[2].value.contains(RecordingPaths.resultFile.lastPathComponent))
            XCTAssertTrue(rows[2].value.contains(RecordingPaths.filesLocation))

            XCTAssertEqual(rows[3].value, SovoxURL.done.absoluteString)
        }
    }

    func testSetupRowsCarryNoStaleCaptureEraStrings() {
        for destination in AIDestination.allCases {
            for row in BridgeShortcutRecipe.setupRows(for: destination) {
                XCTAssertFalse(row.value.lowercased().contains("capture-"), row.value)
                XCTAssertFalse(row.value.contains("capture://"), row.value)
            }
            XCTAssertTrue(BridgeShortcutRecipe.name(for: destination).hasPrefix("Sovox Bridge - "))
        }
    }

    func testCallbackInTheWizardIsTheOneTheAppActuallyListensFor() {
        let rows = BridgeShortcutRecipe.setupRows(for: .chatgpt)
        XCTAssertEqual(rows[3].value, "\(SovoxURL.scheme)://\(SovoxURL.Host.done)")
    }
}
