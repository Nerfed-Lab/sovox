import XCTest
import AppIntents
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

/// The Action Button opened the app every time it started a recording. iOS 18
/// added AudioRecordingIntent precisely so it does not have to.
final class BackgroundStartIntentTests: XCTestCase {

    func testStartingIntentsDoNotOpenTheApp() {
        XCTAssertFalse(StartSovoxIntent.openAppWhenRun,
                       "the Action Button should leave you where you were")
        XCTAssertFalse(ToggleSovoxIntent.openAppWhenRun)
    }

    func testTransportIntentsStillDoNotOpenTheApp() {
        // These never did, which is what makes the Lock Screen buttons usable
        // without unlocking.
        XCTAssertFalse(StopSovoxIntent.openAppWhenRun)
        XCTAssertFalse(PauseSovoxIntent.openAppWhenRun)
        XCTAssertFalse(ResumeSovoxIntent.openAppWhenRun)
    }

    func testAFailedBackgroundStartFallsBackToOpeningTheApp() {
        // Build 12 shipped with the button doing nothing when the background
        // start did not take. Anything that cannot be done from the background
        // must hand over to the foreground rather than end there.
        XCTAssertTrue(SovoxCommandResult.startFailed.needsForeground)
        XCTAssertTrue(SovoxCommandResult.unavailable.needsForeground)
        XCTAssertTrue(SovoxCommandResult.awaitingConsent.needsForeground)
    }

    func testARealAnswerLeavesTheAppClosed() {
        for result in [SovoxCommandResult.started, .stopped, .paused,
                       .resumed, .alreadyRunning, .notRunning] {
            XCTAssertFalse(result.needsForeground, "\(result) is a real answer")
        }
    }

    func testTheFallbackIntentOpensTheApp() {
        XCTAssertTrue(OpenSovoxAndStartIntent.openAppWhenRun)
        XCTAssertFalse(OpenSovoxAndStartIntent.isDiscoverable,
                       "it exists for the fallback, not for the Shortcuts library")
    }

    func testEachIntentDeclaresExactlyOneSystemBehaviour() {
        // Conforming to two SystemIntent protocols at once is the most likely
        // reason the Action Button stopped working in build 12.
        XCTAssertFalse((StartSovoxIntent() as Any) is any LiveActivityIntent)
        XCTAssertFalse((ToggleSovoxIntent() as Any) is any LiveActivityIntent)
        // The transport intents stay LiveActivityIntent: they back the buttons
        // on the Lock Screen card.
        XCTAssertTrue((StopSovoxIntent() as Any) is any LiveActivityIntent)
        XCTAssertTrue((PauseSovoxIntent() as Any) is any LiveActivityIntent)
        XCTAssertTrue((ResumeSovoxIntent() as Any) is any LiveActivityIntent)
    }

    func testTheStartingIntentsDeclareThemselvesAsRecording() {
        // The declaration is what earns the background session activation.
        XCTAssertTrue((StartSovoxIntent() as Any) is any AudioRecordingIntent)
        XCTAssertTrue((ToggleSovoxIntent() as Any) is any AudioRecordingIntent)
    }
}

/// Every route that can start a recording, checked together. Build 12 broke one
/// of them by changing an intent the other three also use.
final class StartRouteTests: XCTestCase {

    func testEveryStartingRouteUsesAnIntentThatCanRecordInTheBackground() {
        // Action Button and Siri go through the App Shortcut, Control Centre
        // goes through the control, and both land on these two.
        XCTAssertTrue((ToggleSovoxIntent() as Any) is any AudioRecordingIntent)
        XCTAssertTrue((StartSovoxIntent() as Any) is any AudioRecordingIntent)
    }

    func testTheShortcutsProviderStillExposesTheStartingPhrases() {
        // The Action Button binds to an App Shortcut. If Toggle stops being
        // listed, the button has nothing to bind to.
        let shortcuts = SovoxShortcuts.appShortcuts
        XCTAssertGreaterThanOrEqual(shortcuts.count, 5)
    }

    @MainActor
    func testTheHandlerWaitIsBoundedAndConfigurable() async {
        // Two seconds was not enough for a cold background launch, and giving
        // up early looked exactly like a dead button. The wait still has to
        // end, well inside the intent execution budget.
        let started = Date()
        let resolved = await SovoxCommands.resolveHandler(timeoutSeconds: 0.2)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 2.0, "the wait is bounded")
        if resolved == nil { XCTAssertGreaterThanOrEqual(elapsed, 0.1, "and it did wait") }
    }
}
