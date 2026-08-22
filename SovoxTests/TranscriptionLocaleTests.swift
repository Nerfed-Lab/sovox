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
