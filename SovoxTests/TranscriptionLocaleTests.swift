import XCTest
import Speech
@testable import Sovox

/// Phase 14a. E38 and E39.
final class TranscriptionLocaleTests: XCTestCase {

    func testDefaultIsEnINNotEnUS() {
        XCTAssertEqual(TranscriptionLocale.defaultIdentifier, "en_IN")
        XCTAssertNotEqual(TranscriptionLocale.defaultIdentifier, "en_US")
    }

    func testAFreshSettingsObjectStartsOnTheIndianEnglishDefault() {
        // Resolved through the same path the recorder uses when a recording
        // carries no stored locale.
        XCTAssertEqual(TranscriptionLocale.resolved(nil), "en_IN")
        XCTAssertEqual(TranscriptionLocale.resolved(""), "en_IN")
    }

    /// The list is queried from the framework, never hardcoded.
    func testSupportedLocalesComeFromTheFrameworkAndAreNotEmpty() {
        let supported = TranscriptionLocale.supported()
        XCTAssertFalse(supported.isEmpty)
        XCTAssertEqual(Set(supported.map(\.identifier)),
                       Set(SFSpeechRecognizer.supportedLocales().map(\.identifier)))
    }

    func testSupportedListIsSortedByDisplayName() {
        let names = TranscriptionLocale.supported().map(TranscriptionLocale.displayName)
        XCTAssertEqual(names, names.sorted())
    }

    func testIdentifiersAreNormalisedSoHyphenAndUnderscoreAgree() {
        XCTAssertEqual(TranscriptionLocale.normalise("en-IN"), "en_IN")
        XCTAssertEqual(TranscriptionLocale.normalise("en_IN"), "en_IN")
        XCTAssertEqual(TranscriptionLocale.resolved("en-GB"), "en_GB")
    }

    func testOnDeviceReadinessIsCheckedPerLocaleRatherThanAssumed() {
        // The value depends on which assets this device has, so the contract
        // tested here is that an unknown locale is never reported as ready.
        XCTAssertFalse(TranscriptionLocale.isOnDeviceReady("zz_ZZ"))
        XCTAssertFalse(TranscriptionLocale.isSupported("zz_ZZ"))
    }

    // MARK: E39, stored per recording

    func testSessionCarriesItsOwnLocaleSoItCanBeRegeneratedAsRecorded() throws {
        var session = RecordingSession(id: "s", startDate: Date())
        session.localeIdentifier = "en_GB"
        let data = try JSONEncoder().encode(session)
        let back = try JSONDecoder().decode(RecordingSession.self, from: data)
        XCTAssertEqual(back.localeIdentifier, "en_GB")
        XCTAssertEqual(TranscriptionLocale.resolved(back.localeIdentifier), "en_GB")
    }

    func testARecordingMadeBeforeThisSettingExistedFallsBackToTheDefault() throws {
        let session = RecordingSession(id: "s", startDate: Date())
        XCTAssertNil(session.localeIdentifier)
        XCTAssertEqual(TranscriptionLocale.resolved(session.localeIdentifier),
                       TranscriptionLocale.defaultIdentifier)
    }

    func testJobCarriesTheLocaleThroughToTheRecogniser() {
        let job = TranscriptionService.Job(sessionID: "s",
                                           index: 1,
                                           fileURL: URL(fileURLWithPath: "/tmp/x.m4a"),
                                           expectedDuration: 60,
                                           localeIdentifier: "en_GB")
        XCTAssertEqual(job.localeIdentifier, "en_GB")
    }

    func testJobDefaultsToTheIndianEnglishLocale() {
        let job = TranscriptionService.Job(sessionID: "s",
                                           index: 1,
                                           fileURL: URL(fileURLWithPath: "/tmp/x.m4a"),
                                           expectedDuration: 60)
        XCTAssertEqual(job.localeIdentifier, "en_IN")
    }
}

/// A supported language is not an installed one. Without a fallback, a device
/// that never downloaded the en_IN asset failed every segment of every
/// recording while holding a working en_US asset the whole time.
final class LocaleFallbackTests: XCTestCase {

    func testTheAskedForLocaleComesFirst() {
        XCTAssertEqual(TranscriptionLocale.fallbackChain(for: "en_IN").first, "en_IN")
    }

    func testTheChainEndsAtUSEnglish() {
        XCTAssertTrue(TranscriptionLocale.fallbackChain(for: "hi_IN").contains("en_US"))
    }

    func testTheChainHasNoDuplicates() {
        let chain = TranscriptionLocale.fallbackChain(for: "en_US")
        XCTAssertEqual(Set(chain).count, chain.count)
    }

    func testHyphensAreNormalisedThroughout() {
        XCTAssertTrue(TranscriptionLocale.fallbackChain(for: "en-IN").allSatisfy { !$0.contains("-") })
    }

    func testTheAskedForLocaleWinsWhenItIsInstalled() {
        let used = TranscriptionLocale.usable("en_IN") { _ in true }
        XCTAssertEqual(used, "en_IN")
    }

    func testItFallsBackOnlyWhenTheAskedForOneIsMissing() {
        let used = TranscriptionLocale.usable("en_IN") { $0 == "en_US" }
        XCTAssertEqual(used, "en_US")
    }

    func testWithNothingInstalledItStillNamesWhatWasAsked() {
        let used = TranscriptionLocale.usable("en_IN") { _ in false }
        XCTAssertEqual(used, "en_IN", "the failure should name the language the user chose")
    }

    func testNoStoredLocaleUsesTheDefault() {
        XCTAssertEqual(TranscriptionLocale.usable(nil) { _ in true },
                       TranscriptionLocale.defaultIdentifier)
    }
}
