import XCTest
@testable import Sovox

/// Phase 10 and Phase 15. E31, E33, E48 to E58.
final class SetupWizardTests: XCTestCase {

    // MARK: E58, the five outcomes are distinguishable

    func testEveryVerifyOutcomeCarriesItsOwnDistinctExplanation() {
        let outcomes: [BridgeVerifyOutcome] = [
            .success, .notFoundOrFailedEarly, .ranButFailedLater("half"),
            .unexpectedContent("garbage"), .noResultFile, .noResponse
        ]
        let messages = outcomes.map(\.message)
        XCTAssertEqual(Set(messages).count, outcomes.count, "two outcomes share a message")
        for message in messages { XCTAssertFalse(message.isEmpty) }
    }

    func testAnErrorNeverAssertsTheShortcutIsMissing() {
        // Shortcuts returns x-error for a missing shortcut and for one that
        // exists and fails, so the message must not pick one.
        let message = BridgeVerifyOutcome.notFoundOrFailedEarly.message.lowercased()
        XCTAssertTrue(message.contains("either"))
        XCTAssertTrue(message.contains("failed before saving"))
    }

    func testEveryFailureListsWhatToCheckNext() {
        for outcome in [BridgeVerifyOutcome.notFoundOrFailedEarly,
                        .ranButFailedLater("x"), .unexpectedContent("x"),
                        .noResultFile, .noResponse] {
            XCTAssertFalse(outcome.causes.isEmpty, "\(outcome) leaves the user with nothing to try")
        }
        XCTAssertTrue(BridgeVerifyOutcome.success.causes.isEmpty)
    }

    func testNoOutcomeShowsARawErrorCode() {
        for outcome in [BridgeVerifyOutcome.success, .notFoundOrFailedEarly,
                        .ranButFailedLater("x"), .unexpectedContent("x"),
                        .noResultFile, .noResponse] {
            let message = outcome.message
            XCTAssertFalse(message.contains("Error Domain"), message)
            XCTAssertFalse(message.contains("NSError"), message)
            XCTAssertFalse(message.range(of: "-?[0-9]{4,}", options: .regularExpression) != nil, message)
        }
    }

    func testWhatCameBackIsQuotedAndCappedAtTwoHundred() {
        XCTAssertTrue(BridgeVerifyOutcome.unexpectedContent("banana").message.contains("banana"))
        let long = String(repeating: "z", count: 500)
        let quoted = BridgeVerifyOutcome.excerpt(long)
        XCTAssertEqual(quoted.count, 203, "200 characters plus the ellipsis")
    }

    // MARK: E48, letters only

    func testBridgeNamesAreLettersOnly() {
        for destination in AIDestination.allCases {
            let name = BridgeShortcutRecipe.name(for: destination)
            XCTAssertFalse(name.isEmpty)
            XCTAssertTrue(name.allSatisfy { $0.isLetter },
                          "\(name) contains something that is not a letter")
        }
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .chatgpt), "SovoxChatGPT")
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .claude), "SovoxClaude")
    }

    func testTheNameSurvivesPercentEncodingUnchanged() {
        for destination in AIDestination.allCases {
            let name = BridgeShortcutRecipe.name(for: destination)
            XCTAssertEqual(URLEncoding.encode(name), name,
                           "a name that needs encoding is a name that can be mistyped")
        }
    }

    // MARK: E49, no smart punctuation anywhere the user must reproduce a string

    func testNoDisplayedLiteralCarriesADashThatIsNotAHyphen() {
        var literals: [String] = []
        for destination in AIDestination.allCases {
            literals.append(BridgeShortcutRecipe.name(for: destination))
            literals.append(contentsOf: BridgeShortcutRecipe.substeps(for: destination).compactMap(\.copyValue))
            literals.append(contentsOf: BridgeShortcutRecipe.steps(for: destination))
            literals.append(contentsOf: BridgeShortcutRecipe.finishedPreview(for: destination))
            literals.append(BridgeShortcutRecipe.folderPath)
        }
        literals.append(contentsOf: [RecordingPaths.pendingPromptFile.lastPathComponent,
                                     RecordingPaths.resultFile.lastPathComponent,
                                     SovoxURL.done.absoluteString,
                                     SovoxURL.failed.absoluteString])
        for literal in literals {
            for scalar in literal.unicodeScalars {
                XCTAssertNotEqual(scalar, "\u{2013}", "en dash in \(literal)")
                XCTAssertNotEqual(scalar, "\u{2014}", "em dash in \(literal)")
                XCTAssertNotEqual(scalar, "\u{2018}", "smart quote in \(literal)")
                XCTAssertNotEqual(scalar, "\u{2019}", "smart quote in \(literal)")
                XCTAssertNotEqual(scalar, "\u{201C}", "smart quote in \(literal)")
                XCTAssertNotEqual(scalar, "\u{201D}", "smart quote in \(literal)")
            }
        }
    }

    func testEveryCopyableValueIsPlainASCII() {
        for destination in AIDestination.allCases {
            for value in BridgeShortcutRecipe.substeps(for: destination).compactMap(\.copyValue) {
                XCTAssertTrue(value.allSatisfy { $0.isASCII }, value)
            }
        }
    }

    // MARK: E54, copy buttons only on literal values

    func testOnlyLiteralValuesAreCopyable() {
        for destination in AIDestination.allCases {
            for substep in BridgeShortcutRecipe.substeps(for: destination) {
                switch substep.kind {
                case .copyValue(let value):
                    XCTAssertFalse(value.isEmpty)
                    XCTAssertFalse(value.contains(" the "), "guidance, not a value: \(value)")
                case .instruction, .variable, .toggleOn, .toggleOff, .picker:
                    XCTAssertNil(substep.copyValue,
                                 "step \(substep.number) is guidance and must not be copyable")
                }
            }
        }
    }

    func testTheVariableStepSaysNotToTypeAnything() {
        let step = BridgeShortcutRecipe.substeps(for: .claude).first { $0.kind == .variable }
        XCTAssertNotNil(step)
        XCTAssertTrue(step?.text.contains("blue File variable") ?? false)
        let flat = BridgeShortcutRecipe.steps(for: .claude).first { $0.contains("blue File variable") }
        XCTAssertTrue(flat?.contains("Do not type anything here") ?? false)
    }

    // MARK: E52, three actions and no callback action

    func testTheRecipeIsThreeActionsPlusTheName() {
        for destination in AIDestination.allCases {
            let groups = Set(BridgeShortcutRecipe.substeps(for: destination).map(\.group))
            XCTAssertEqual(groups, ["Action 1", "Action 2", "Action 3", "Name"])
        }
    }

    func testNoStepAsksForAnOpenURLAction() {
        for destination in AIDestination.allCases {
            let text = (BridgeShortcutRecipe.steps(for: destination)
                        + BridgeShortcutRecipe.substeps(for: destination).compactMap(\.copyValue))
                .joined(separator: "\n")
            XCTAssertFalse(text.contains(SovoxURL.done.absoluteString), "the callback is carried by x-success")
            XCTAssertFalse(text.lowercased().contains("open url"))
        }
    }

    // MARK: E33, E55, E56

    func testTheSubstepsNameTheRealFilesAndFolder() {
        for destination in AIDestination.allCases {
            let values = BridgeShortcutRecipe.substeps(for: destination).compactMap(\.copyValue)
            XCTAssertTrue(values.contains(RecordingPaths.pendingPromptFile.lastPathComponent))
            XCTAssertTrue(values.contains(RecordingPaths.resultFile.lastPathComponent))
            XCTAssertTrue(values.contains("Ask \(destination.title)"))
            let pickers = BridgeShortcutRecipe.substeps(for: destination).filter {
                if case .picker = $0.kind { return true }
                return false
            }
            XCTAssertEqual(pickers.count, 2)
            for picker in pickers {
                XCTAssertEqual(picker.kind, .picker(RecordingPaths.filesLocation))
            }
        }
    }

    func testEveryNamedFieldAlsoHasItsPositionDescribed() {
        for destination in AIDestination.allCases {
            for substep in BridgeShortcutRecipe.substeps(for: destination) {
                switch substep.kind {
                case .copyValue where substep.number == 1 || substep.number == 5 || substep.number == 8:
                    continue // search boxes, there is only one
                case .instruction, .variable, .toggleOn, .toggleOff, .picker, .copyValue:
                    XCTAssertNotNil(substep.position,
                                    "step \(substep.number) names a control with no position")
                }
            }
        }
    }

    func testTheClarificationsAreStatedNotImplied() {
        XCTAssertTrue(BridgeShortcutRecipe.pickerClarification.lowercased().contains("greyed out"))
        XCTAssertTrue(BridgeShortcutRecipe.pickerClarification.lowercased().contains("folder"))
        XCTAssertTrue(BridgeShortcutRecipe.pathFieldClarification.lowercased().contains("typed text"))
        XCTAssertTrue(BridgeShortcutRecipe.pathFieldClarification.lowercased().contains("does not have to exist"))
    }

    func testTheFinishedPreviewShowsThreeRows() {
        for destination in AIDestination.allCases {
            let rows = BridgeShortcutRecipe.finishedPreview(for: destination)
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(rows[0].contains(RecordingPaths.pendingPromptFile.lastPathComponent))
            XCTAssertTrue(rows[1].contains(destination.title))
            XCTAssertTrue(rows[2].contains(RecordingPaths.filesFolderName))
        }
    }

    func testNoStepCarriesStaleCaptureEraStrings() {
        for destination in AIDestination.allCases {
            for step in BridgeShortcutRecipe.steps(for: destination) {
                XCTAssertFalse(step.lowercased().contains("capture-"), step)
                XCTAssertFalse(step.contains("capture://"), step)
            }
        }
    }
}

/// The recovery screen and the wizard teach the same Shortcut. They disagreed
/// once, and a Shortcut built from the recovery screen could never call back.
/// Phase 15 removed the drift structurally: both render the same sub steps.
final class RecipeAgreementTests: XCTestCase {

    func testTheFlatListIsDerivedFromTheSameSubsteps() {
        for destination in AIDestination.allCases {
            let substeps = BridgeShortcutRecipe.substeps(for: destination)
            let flat = BridgeShortcutRecipe.steps(for: destination)
            XCTAssertEqual(flat.count, substeps.count)
            for (index, substep) in substeps.enumerated() {
                XCTAssertTrue(flat[index].hasPrefix("\(substep.number). "),
                              "numbering drifted at \(substep.number)")
            }
        }
    }

    func testBothListsNameTheSameTwoFiles() {
        for destination in AIDestination.allCases {
            let flat = BridgeShortcutRecipe.steps(for: destination).joined(separator: "\n")
            let values = BridgeShortcutRecipe.substeps(for: destination)
                .compactMap(\.copyValue).joined(separator: "\n")
            for name in [RecordingPaths.pendingPromptFile.lastPathComponent,
                         RecordingPaths.resultFile.lastPathComponent] {
                XCTAssertTrue(flat.contains(name), "\(name) missing from the flat list")
                XCTAssertTrue(values.contains(name), "\(name) missing from the copyable values")
            }
        }
    }

    func testBothListsCarryTheSameName() {
        for destination in AIDestination.allCases {
            let name = BridgeShortcutRecipe.name(for: destination)
            XCTAssertTrue(BridgeShortcutRecipe.steps(for: destination)
                .contains { $0.contains(name) })
            XCTAssertTrue(BridgeShortcutRecipe.substeps(for: destination)
                .compactMap(\.copyValue).contains(name))
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
