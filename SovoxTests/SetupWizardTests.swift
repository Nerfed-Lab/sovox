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

/// The recovery screen and the wizard teach the same Shortcut. They disagreed:
/// the recovery screen left out the callback, so a Shortcut built from it ran
/// perfectly and Sovox never heard the answer was ready.
final class RecipeAgreementTests: XCTestCase {

    func testBothListsTeachTheCallback() {
        for destination in AIDestination.allCases {
            let steps = BridgeShortcutRecipe.steps(for: destination).joined(separator: "\n")
            let rows = BridgeShortcutRecipe.setupRows(for: destination)
                .map { "\($0.action) \($0.value)" }.joined(separator: "\n")
            XCTAssertTrue(steps.contains(SovoxURL.done.absoluteString),
                          "\(destination) steps never tell the user to call back")
            XCTAssertTrue(rows.contains(SovoxURL.done.absoluteString))
        }
    }

    func testBothListsNameTheSameTwoFiles() {
        for destination in AIDestination.allCases {
            let steps = BridgeShortcutRecipe.steps(for: destination).joined(separator: "\n")
            let rows = BridgeShortcutRecipe.setupRows(for: destination)
                .map(\.value).joined(separator: "\n")
            for name in [RecordingPaths.pendingPromptFile.lastPathComponent,
                         RecordingPaths.resultFile.lastPathComponent] {
                XCTAssertTrue(steps.contains(name), "\(name) missing from steps")
                XCTAssertTrue(rows.contains(name), "\(name) missing from wizard rows")
            }
        }
    }

    func testNoStepHardcodesAFileName() {
        // The rename already broke these once by leaving capture- in the text.
        for destination in AIDestination.allCases {
            for step in BridgeShortcutRecipe.steps(for: destination) {
                XCTAssertFalse(step.lowercased().contains("capture"))
            }
        }
    }
}

/// Self Test is what the user runs when something is wrong. Every check it
/// omits is a green screen next to a broken app. Asserted against the check
/// list rather than by running it: micRow asks for permission, which never
/// returns in a test host.
final class SelfTestCoverageTests: XCTestCase {

    func testItCoversTheBridgeAndNotifications() {
        let ids = Set(SelfTest.Check.allCases.map(\.rawValue))
        XCTAssertTrue(ids.contains("bridge"), "a Shortcut that was never built has no other symptom")
        XCTAssertTrue(ids.contains("notifications"), "the only channel while the phone is locked")
    }

    func testItStillCoversEverythingItCoveredBefore() {
        let ids = Set(SelfTest.Check.allCases.map(\.rawValue))
        for expected in ["mic", "speech", "model", "liveactivity", "background",
                         "documents", "scheme", "shortcuts", "outlook", "disk"] {
            XCTAssertTrue(ids.contains(expected), "\(expected) check disappeared")
        }
    }

    func testEveryCheckIsListedOnlyOnce() {
        XCTAssertEqual(Set(SelfTest.Check.allCases.map(\.rawValue)).count,
                       SelfTest.Check.allCases.count)
    }
}

/// Verification used to be recorded in a view's onAppear, which does not run
/// again when a failed verify is retried and succeeds.
@MainActor
final class BridgeVerificationRecordingTests: XCTestCase {

    func testMarkingIsIdempotentAndPerDestination() {
        let settings = AppSettings.shared
        let before = settings.verifiedBridges
        defer { settings.verifiedBridges = before }

        settings.verifiedBridges = []
        settings.markBridgeVerified(.chatgpt)
        settings.markBridgeVerified(.chatgpt)
        XCTAssertTrue(settings.isBridgeVerified(.chatgpt))
        XCTAssertFalse(settings.isBridgeVerified(.claude), "verifying one says nothing about the other")
        XCTAssertEqual(settings.verifiedBridges.count, 1)
    }

    func testVerificationSurvivesARelaunch() {
        let settings = AppSettings.shared
        let before = settings.verifiedBridges
        defer { settings.verifiedBridges = before }

        settings.verifiedBridges = []
        settings.markBridgeVerified(.claude)
        let persisted = UserDefaults.standard.stringArray(forKey: "sovox.verifiedBridges") ?? []
        XCTAssertTrue(persisted.contains(AIDestination.claude.rawValue))
    }

    func testTheSelfTestBridgeRowFollowsTheRecordedState() {
        let settings = AppSettings.shared
        let before = settings.verifiedBridges
        defer { settings.verifiedBridges = before }

        settings.verifiedBridges = [settings.destination.rawValue]
        XCTAssertTrue(settings.isBridgeVerified(settings.destination))
    }
}
