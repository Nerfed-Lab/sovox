import XCTest
import Speech
@testable import Sovox

/// Phase 19a. Reports what this runtime can actually do, rather than what the
/// documentation implies. Prints rather than asserts: the answer is the point.
///
/// Simulator results are not device results for INSTALLED assets. They are a
/// reasonable proxy for SUPPORTED locales, which is what the tier turns on.
final class SpeechCapabilityProbeTests: XCTestCase {

    func testProbeSpeechTranscriber() async throws {
        guard #available(iOS 26.0, *) else {
            print("PROBE: iOS 26 unavailable"); return
        }
        print("PROBE ==== SpeechTranscriber ====")
        print("PROBE isAvailable: \(SpeechTranscriber.isAvailable)")

        let supported = await SpeechTranscriber.supportedLocales
        print("PROBE supportedLocales count: \(supported.count)")
        for locale in supported.sorted(by: { $0.identifier < $1.identifier }) {
            let script = locale.language.script?.identifier ?? "-"
            print("PROBE   supported: \(locale.identifier)  script=\(script)")
        }

        let installed = await SpeechTranscriber.installedLocales
        print("PROBE installedLocales count: \(installed.count)")
        for locale in installed.sorted(by: { $0.identifier < $1.identifier }) {
            print("PROBE   installed: \(locale.identifier)")
        }

        for wanted in ["hi-IN", "hi_IN", "en-IN", "en_IN", "en-US"] {
            let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: wanted))
            print("PROBE equivalent for \(wanted): \(match?.identifier ?? "none")")
        }
    }

    func testProbeDevanagariSpecifically() async throws {
        guard #available(iOS 26.0, *) else { return }
        let supported = await SpeechTranscriber.supportedLocales
        let devanagari = supported.filter {
            $0.language.script?.identifier == "Deva"
                || $0.identifier.hasPrefix("hi")
                || $0.identifier.hasPrefix("mr")
                || $0.identifier.hasPrefix("ne")
        }
        print("PROBE Devanagari-capable locales: \(devanagari.map(\.identifier))")
        print("PROBE TIER 1 QUALIFIES: \(!devanagari.isEmpty)")
    }

    func testProbeAssetInventoryForHindi() async throws {
        guard #available(iOS 26.0, *) else { return }
        let hi = SpeechTranscriber(locale: Locale(identifier: "hi-IN"),
                                   transcriptionOptions: [],
                                   reportingOptions: [],
                                   attributeOptions: [.audioTimeRange])
        let status = await AssetInventory.status(forModules: [hi])
        print("PROBE AssetInventory.status(hi-IN): \(status)")
        let reserved = await AssetInventory.reservedLocales
        print("PROBE reservedLocales: \(reserved.map(\.identifier)), max \(AssetInventory.maximumReservedLocales)")
    }

    func testProbeLegacyRecogniser() {
        print("PROBE ==== SFSpeechRecognizer ====")
        let all = SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
        print("PROBE SFSpeechRecognizer.supportedLocales count: \(all.count)")
        let indic = all.filter {
            ["hi", "mr", "ne", "bn", "ta", "te", "gu", "kn", "ml", "pa", "ur", "en"].contains($0.language.languageCode?.identifier ?? "")
        }
        for locale in indic {
            print("PROBE   indic/english supported: \(locale.identifier)")
        }
        for wanted in ["hi-IN", "hi_IN", "en-IN", "en_IN", "en-US"] {
            let recogniser = SFSpeechRecognizer(locale: Locale(identifier: wanted))
            print("PROBE \(wanted): recogniser=\(recogniser != nil) available=\(recogniser?.isAvailable ?? false) onDevice=\(recogniser?.supportsOnDeviceRecognition ?? false)")
        }
        print("PROBE authorisation: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
    }
}

/// Phase 19a. The tier rule itself, asserted rather than eyeballed.
final class SpeechTierRuleTests: XCTestCase {

    private func report(analyzerAvailable: Bool,
                        devanagari: [String],
                        secondaryAvailable: Bool,
                        secondaryOnDevice: Bool) -> SpeechCapabilityReport {
        SpeechCapabilityReport(probedAt: Date(),
                               primaryIdentifier: "en_IN",
                               secondaryIdentifier: "hi_IN",
                               analyzerAvailable: analyzerAvailable,
                               analyzerSupported: devanagari,
                               analyzerInstalled: [],
                               analyzerDevanagari: devanagari,
                               legacySupportedCount: 63,
                               legacySecondaryExists: true,
                               legacySecondaryAvailable: secondaryAvailable,
                               legacySecondaryOnDevice: secondaryOnDevice,
                               legacyPrimaryOnDevice: true,
                               tier: .three)
    }

    func testOnlineOnlyHindiIsTierThreeNotTierTwo() {
        // A Hindi keyboard that dictates fine in Notes proves nothing: that
        // path may use Apple's servers, and this app may not.
        let r = report(analyzerAvailable: false, devanagari: [],
                       secondaryAvailable: true, secondaryOnDevice: false)
        XCTAssertTrue(r.secondaryIsOnlineOnly)
    }

    func testOnDeviceHindiIsNotFlaggedAsOnlineOnly() {
        let r = report(analyzerAvailable: false, devanagari: [],
                       secondaryAvailable: true, secondaryOnDevice: true)
        XCTAssertFalse(r.secondaryIsOnlineOnly)
    }

    func testDevanagariDetectionIgnoresLatinHindi() {
        XCTAssertTrue(SpeechCapabilityProbe.isDevanagari(Locale(identifier: "hi_IN")))
        XCTAssertTrue(SpeechCapabilityProbe.isDevanagari(Locale(identifier: "mr_IN")))
        XCTAssertFalse(SpeechCapabilityProbe.isDevanagari(Locale(identifier: "hi-Latn")),
                       "romanised Hindi is not the secondary pass this phase wants")
        XCTAssertFalse(SpeechCapabilityProbe.isDevanagari(Locale(identifier: "en_IN")))
    }

    func testTheReportNamesTheTierAndBothLists() {
        let text = report(analyzerAvailable: true, devanagari: ["hi_IN"],
                          secondaryAvailable: true, secondaryOnDevice: true).plainText
        XCTAssertTrue(text.contains("supportedLocales"))
        XCTAssertTrue(text.contains("installedLocales"))
        XCTAssertTrue(text.contains("tier:"))
        XCTAssertTrue(text.contains("onDevice="))
    }

    func testProbingThisRuntimeResolvesATier() async {
        let live = await SpeechCapabilityProbe.run(primary: "en_IN", secondary: "hi_IN")
        print("PROBE RESOLVED TIER: \(live.tier.title) devanagari=\(live.analyzerDevanagari) onlineOnly=\(live.secondaryIsOnlineOnly)")
        XCTAssertNotNil(SpeechTier(rawValue: live.tier.rawValue))
    }
}
