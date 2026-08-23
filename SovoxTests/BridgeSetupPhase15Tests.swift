import XCTest
@testable import Sovox

/// Phase 15. A real setup attempt on device produced four defects, every one of
/// them caused by how the instructions were presented. These pin the fixes.
@MainActor
final class BridgeFilePersistenceTests: XCTestCase {

    // MARK: E50, the Documents root, not a subfolder

    func testBothBridgeFilesSitInTheDocumentsRoot() {
        XCTAssertEqual(RecordingPaths.pendingPromptFile.deletingLastPathComponent().standardizedFileURL,
                       RecordingPaths.documents.standardizedFileURL,
                       "a subfolder is not what surfaces as the app's folder in Files")
        XCTAssertEqual(RecordingPaths.resultFile.deletingLastPathComponent().standardizedFileURL,
                       RecordingPaths.documents.standardizedFileURL)
    }

    func testEnsureBridgeFilesCreatesBothWithTheRightContents() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: RecordingPaths.pendingPromptFile)
        try? fm.removeItem(at: RecordingPaths.resultFile)

        XCTAssertTrue(RecordingPaths.ensureBridgeFiles())
        XCTAssertTrue(fm.fileExists(atPath: RecordingPaths.pendingPromptFile.path))
        XCTAssertTrue(fm.fileExists(atPath: RecordingPaths.resultFile.path))
        XCTAssertEqual(try String(contentsOf: RecordingPaths.pendingPromptFile, encoding: .utf8),
                       RecordingPaths.pendingPlaceholder)
        XCTAssertEqual(try String(contentsOf: RecordingPaths.resultFile, encoding: .utf8), "")
    }

    func testEnsureDoesNotOverwriteRealContent() throws {
        try "Reply with exactly: OK".write(to: RecordingPaths.pendingPromptFile,
                                           atomically: true, encoding: .utf8)
        RecordingPaths.ensureBridgeFiles()
        XCTAssertEqual(try String(contentsOf: RecordingPaths.pendingPromptFile, encoding: .utf8),
                       "Reply with exactly: OK")
    }

    // MARK: E51, never deleted as cleanup

    func testTheProbeFileSurvivesTheEndOfARun() throws {
        try "a whole meeting transcript".write(to: RecordingPaths.pendingPromptFile,
                                               atomically: true, encoding: .utf8)
        HandoffCoordinator.shared.cancelInFlight()

        XCTAssertTrue(FileManager.default.fileExists(atPath: RecordingPaths.pendingPromptFile.path),
                      "its presence in Files is the only proof the app writes where the Shortcut reads")
        let contents = try String(contentsOf: RecordingPaths.pendingPromptFile, encoding: .utf8)
        XCTAssertEqual(contents, RecordingPaths.pendingPlaceholder)
        XCTAssertFalse(contents.contains("transcript"), "the transcript itself still has to go")
    }

    func testResetLeavesThePlaceholderNotAnEmptyFile() throws {
        try "junk".write(to: RecordingPaths.pendingPromptFile, atomically: true, encoding: .utf8)
        RecordingPaths.resetPendingPromptFile()
        XCTAssertEqual(try String(contentsOf: RecordingPaths.pendingPromptFile, encoding: .utf8),
                       RecordingPaths.pendingPlaceholder)
    }
}

/// E57. Running the Shortcut by hand is what separates a wrong Shortcut from an
/// app invoking it wrongly, and it only works if the app stays out of the way.
@MainActor
final class ManualBridgeTestTests: XCTestCase {

    func testPreparingWritesThePromptAndInvokesNothing() throws {
        let handoff = HandoffCoordinator.shared
        handoff.cancelInFlight()
        XCTAssertTrue(handoff.prepareManualTest())

        XCTAssertEqual(try String(contentsOf: RecordingPaths.pendingPromptFile, encoding: .utf8),
                       HandoffCoordinator.manualTestPrompt)
        XCTAssertTrue(handoff.manualTestArmed)
        XCTAssertFalse(handoff.isInFlight, "preparing must not take the bridge lock")
        XCTAssertNil(handoff.manualTestResult, "nothing has run yet")
        handoff.clearManualTest()
    }

    func testCheckingWithNothingWrittenSaysSoRatherThanFailing() throws {
        let handoff = HandoffCoordinator.shared
        handoff.prepareManualTest()
        let message = handoff.checkManualResult()
        XCTAssertTrue(message.contains(RecordingPaths.resultFile.lastPathComponent))
        XCTAssertTrue(message.lowercased().contains("run the shortcut"))
        handoff.clearManualTest()
    }

    func testCheckingReportsAWorkingShortcut() throws {
        let handoff = HandoffCoordinator.shared
        handoff.prepareManualTest()
        try "OK".write(to: RecordingPaths.resultFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(handoff.checkManualResult().contains("works"))
        handoff.clearManualTest()
    }

    func testCheckingQuotesAWrongAnswerBack() throws {
        let handoff = HandoffCoordinator.shared
        handoff.prepareManualTest()
        try "Sure, here is a summary of the meeting".write(to: RecordingPaths.resultFile,
                                                           atomically: true, encoding: .utf8)
        let message = handoff.checkManualResult()
        XCTAssertTrue(message.contains("summary of the meeting"))
        handoff.clearManualTest()
    }

    // MARK: E53, the modification date fallback

    func testAResultWrittenAfterTheRequestIsSeenAsNew() throws {
        let handoff = HandoffCoordinator.shared
        handoff.prepareManualTest()
        XCTAssertFalse(handoff.resultFileIsNewerThanRequest, "nothing has been written yet")

        Thread.sleep(forTimeInterval: 1.1)
        try "OK".write(to: RecordingPaths.resultFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(handoff.resultFileIsNewerThanRequest,
                      "x-success may never fire, so the file's date has to be enough")
        handoff.clearManualTest()
    }
}

/// E59. A user who already built the old bridge needs three edits, not a rebuild.
@MainActor
final class BridgeMigrationTests: XCTestCase {

    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAUserWithAnOldVerifiedBridgeIsMigratedOnce() {
        let name = "sovox.test.\(UUID().uuidString)"
        let defaults = suite(name)
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: AppSettings.Keys.setupCompleted)
        defaults.set(["claude"], forKey: AppSettings.Keys.verifiedBridges)

        XCTAssertTrue(AppSettings.migrateBridgeNames(defaults))
        XCTAssertEqual(defaults.stringArray(forKey: AppSettings.Keys.verifiedBridges), [],
                       "a round trip through a name that no longer exists proves nothing")
        XCTAssertTrue(defaults.bool(forKey: AppSettings.Keys.bridgeMigrationPending))

        XCTAssertFalse(AppSettings.migrateBridgeNames(defaults), "runs once, not every launch")
    }

    func testAFreshInstallHasNothingToMigrate() {
        let name = "sovox.test.\(UUID().uuidString)"
        let defaults = suite(name)
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(AppSettings.migrateBridgeNames(defaults))
        XCTAssertFalse(defaults.bool(forKey: AppSettings.Keys.bridgeMigrationPending),
                       "no card for someone who never had the old bridge")
    }

    func testSetupCompletedAloneIsEnoughToWarrantTheCard() {
        let name = "sovox.test.\(UUID().uuidString)"
        let defaults = suite(name)
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: AppSettings.Keys.setupCompleted)
        XCTAssertTrue(AppSettings.migrateBridgeNames(defaults))
        XCTAssertTrue(defaults.bool(forKey: AppSettings.Keys.bridgeMigrationPending))
    }
}

/// The adversarial audit of Phase 15 confirmed two defects. These pin both.
@MainActor
final class VerifyStrictnessTests: XCTestCase {

    // MARK: A substring test called a broken bridge working

    func testOnlyAnExactOKCounts() {
        XCTAssertTrue(BridgeVerifyOutcome.isProbeSuccess("OK"))
        XCTAssertTrue(BridgeVerifyOutcome.isProbeSuccess("ok"))
        XCTAssertTrue(BridgeVerifyOutcome.isProbeSuccess("  OK.\n"))
        XCTAssertTrue(BridgeVerifyOutcome.isProbeSuccess("\"OK\""))
    }

    func testAChattyReplyContainingThoseLettersIsNotSuccess() {
        // This is defect 1 from the field report: guidance text pasted into the
        // prompt field, so the model answers a different question. Every one of
        // these contains the letters o and k together.
        for reply in ["Okay, here is what I found",
                      "It looks like you want me to use the file from action 1",
                      "I took a look at the notes and here is a summary",
                      "That seems broken, let me know what you meant"] {
            XCTAssertFalse(BridgeVerifyOutcome.isProbeSuccess(reply),
                           "a bridge that returns this is not working: \(reply)")
        }
    }

    func testAnEmptyOrGarbageReplyIsNotSuccess() {
        XCTAssertFalse(BridgeVerifyOutcome.isProbeSuccess(""))
        XCTAssertFalse(BridgeVerifyOutcome.isProbeSuccess("   "))
        XCTAssertFalse(BridgeVerifyOutcome.isProbeSuccess("OKAY"))
        XCTAssertFalse(BridgeVerifyOutcome.isProbeSuccess("OK OK"))
    }

    func testTheManualCheckUsesTheSameStandard() throws {
        let handoff = HandoffCoordinator.shared
        handoff.prepareManualTest()
        try "Okay, here is what I found".write(to: RecordingPaths.resultFile,
                                               atomically: true, encoding: .utf8)
        let message = handoff.checkManualResult()
        XCTAssertFalse(message.contains("works"), "the same loose test lived here too")
        XCTAssertTrue(message.contains("something else"))
        handoff.clearManualTest()
    }

    // MARK: The fallback died in the process it exists for

    func testAPersistedRequestSurvivesWhatPhaseCannot() {
        let handoff = HandoffCoordinator.shared
        handoff.cancelInFlight()
        XCTAssertFalse(handoff.hasPersistedRequest)
        XCTAssertFalse(handoff.isInFlight)

        // What a relaunch mid round trip leaves: the record on disk, phase idle.
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: "sovox.handoff.startedAt")
        defaults.set(BridgePurpose.notes.rawValue, forKey: "sovox.handoff.purpose")
        defer { handoff.cancelInFlight() }

        handoff.restoreForTesting()
        XCTAssertTrue(handoff.hasPersistedRequest,
                      "the fallback has to key off this, not off in memory phase")
        XCTAssertFalse(handoff.isInFlight, "phase is idle in a fresh process, which is the whole point")
    }
}
