import XCTest
@testable import Sovox

/// The Capture to Sovox rename broke two things that no compiler could catch:
/// the deep link handler still compared against the old scheme, so every
/// sovox://done callback was silently ignored, and Self Test looked for the old
/// scheme in Info.plist so it reported FAIL on a correct build. Both carried
/// their own copy of the string. These tests pin the single source of truth.
final class RenameIntegrityTests: XCTestCase {

    private var declaredSchemes: [String] {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    func testInfoPlistDeclaresTheSchemeTheCodeUses() {
        XCTAssertTrue(declaredSchemes.contains(SovoxURL.scheme),
                      "Info.plist declares \(declaredSchemes), code expects \(SovoxURL.scheme)")
    }

    func testCallbackURLsAllUseTheDeclaredScheme() {
        for url in [SovoxURL.recording, SovoxURL.done, SovoxURL.failed] {
            XCTAssertEqual(url.scheme, SovoxURL.scheme)
        }
    }

    func testCallbackHostsMatchTheConstantsTheHandlerSwitchesOn() {
        XCTAssertEqual(SovoxURL.recording.host, SovoxURL.Host.recording)
        XCTAssertEqual(SovoxURL.done.host, SovoxURL.Host.done)
        XCTAssertEqual(SovoxURL.failed.host, SovoxURL.Host.failed)
    }

    func testLiveActivityDeepLinkIsTheRecordingURL() {
        XCTAssertEqual(SovoxLiveActivity.deepLink, SovoxURL.recording)
    }

    func testNoCallbackStillPointsAtTheOldScheme() {
        for url in [SovoxURL.recording, SovoxURL.done, SovoxURL.failed] {
            XCTAssertFalse(url.absoluteString.hasPrefix("capture:"), "\(url) is still on the old scheme")
        }
        XCTAssertFalse(declaredSchemes.contains("capture"))
    }

    func testBrandDerivedStringsFollowTheDisplayName() {
        let display = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
        XCTAssertEqual(display, "Sovox")
        XCTAssertEqual(RecordingPaths.filesFolderName, "Sovox")
        XCTAssertEqual(RecordingPaths.filesLocation, "On My iPhone, Sovox")
    }

    func testRecordingAndBridgeFileNamesUseTheNewPrefix() {
        let id = RecordingPaths.sessionID(for: Date(timeIntervalSince1970: 1_787_322_600))
        XCTAssertTrue(id.hasPrefix("sovox-"), id)
        XCTAssertEqual(RecordingPaths.pendingPromptFile.lastPathComponent, "sovox-pending.txt")
        XCTAssertEqual(RecordingPaths.resultFile.lastPathComponent, "sovox-result.txt")
    }

    func testBridgeShortcutNamesAreRebranded() {
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .chatgpt), "SovoxChatGPT")
        XCTAssertEqual(BridgeShortcutRecipe.name(for: .claude), "SovoxClaude")
        for destination in AIDestination.allCases {
            for step in BridgeShortcutRecipe.steps(for: destination) {
                XCTAssertFalse(step.lowercased().contains("capture-"), step)
            }
        }
    }
}

/// The rename broke the callback once already, by leaving the handler matching
/// the old scheme. These pin the routing itself.
final class URLRoutingTests: XCTestCase {

    func testTheSuccessCallbackCollectsTheResult() {
        XCTAssertEqual(SovoxURL.route(for: SovoxURL.done, isInFlight: true), .collectResult)
        XCTAssertEqual(SovoxURL.route(for: SovoxURL.done, isInFlight: false), .collectResult)
    }

    func testTheFailureCallbackReportsIt() {
        XCTAssertEqual(SovoxURL.route(for: SovoxURL.failed, isInFlight: true), .reportFailure)
    }

    func testTheLockScreenDeepLinkOpensRecording() {
        XCTAssertEqual(SovoxURL.route(for: SovoxURL.recording, isInFlight: false), .openRecording)
    }

    func testCaseIsNormalised() {
        let url = try? XCTUnwrap(URL(string: "Sovox://DONE"))
        XCTAssertEqual(SovoxURL.route(for: url!, isInFlight: false), .collectResult)
    }

    func testAnotherAppsSchemeIsIgnored() {
        let url = try? XCTUnwrap(URL(string: "shortcuts://done"))
        XCTAssertEqual(SovoxURL.route(for: url!, isInFlight: true), .ignore)
    }

    func testAMistypedHostStillCollectsWhileARequestIsInFlight() {
        let url = try? XCTUnwrap(URL(string: "sovox://donee"))
        XCTAssertEqual(SovoxURL.route(for: url!, isInFlight: true), .collectResult,
                       "the bridge is the only caller, and waiting forever is worse")
    }

    func testAMistypedHostIsIgnoredWhenNothingIsWaiting() {
        let url = try? XCTUnwrap(URL(string: "sovox://donee"))
        XCTAssertEqual(SovoxURL.route(for: url!, isInFlight: false), .ignore)
    }
}
