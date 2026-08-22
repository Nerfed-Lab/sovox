import XCTest
import AVFoundation
@testable import Sovox

/// Phase 14b, E37.
///
/// Voice processing, noise suppression and echo cancellation are tuned for a
/// single near speaker. On a table mic they actively suppress the distant
/// participants this app exists to capture, and the symptom misleads: your own
/// voice is crisp while everyone across the table is faint.
///
/// An earlier version of this file read AudioCaptureEngine.swift from disk and
/// asserted on its text. That cannot work: the test host runs sandboxed in the
/// simulator and cannot read arbitrary host paths, so every assertion silently
/// passed on an empty string until the suite was actually run to completion.
/// These assert on real symbols instead. The source level sweep for the banned
/// API names lives in the build verification script, where a shell can actually
/// read the tree.
final class CapturePathGuardTests: XCTestCase {

    func testSessionModeIsDefaultAndNotANearFieldMode() {
        XCTAssertEqual(AudioCaptureEngine.sessionMode, .default)
        for banned: AVAudioSession.Mode in [.voiceChat, .videoChat, .gameChat, .measurement] {
            XCTAssertNotEqual(AudioCaptureEngine.sessionMode, banned)
        }
    }

    /// Every rung of the fallback ladder differs only in options. If a rung ever
    /// needed a different mode, that would be the moment voice processing crept
    /// in, so the mode is a single constant rather than a per rung value.
    func testTheLadderVariesOptionsOnlyNeverTheMode() {
        let ladder = AudioCaptureEngine.categoryLadder
        XCTAssertGreaterThanOrEqual(ladder.count, 2)
        for rung in ladder {
            XCTAssertFalse(rung.contains(.mixWithOthers),
                           "mixWithOthers would let another app hold the input")
        }
    }

    /// The recorder must reach the hardware unprocessed, so nothing in the
    /// ladder may request an option that only makes sense for playback routing.
    func testNoRungRequestsPlaybackOnlyBehaviour() {
        for rung in AudioCaptureEngine.categoryLadder {
            XCTAssertFalse(rung.contains(.duckOthers))
            XCTAssertFalse(rung.contains(.interruptSpokenAudioAndMixWithOthers))
        }
    }

    /// E42. The transcriber is handed a file and a locale, nothing else. There
    /// is no place to inject a term list even if someone wanted to.
    func testTranscriptionJobCarriesNoVocabularyOrHintPayload() {
        let job = TranscriptionService.Job(sessionID: "s",
                                           index: 1,
                                           fileURL: URL(fileURLWithPath: "/tmp/x.m4a"),
                                           expectedDuration: 60,
                                           localeIdentifier: "en_IN")
        // Mirror describes the stored properties. A vocabulary or hints field
        // appearing here would be the regression E42 forbids.
        let fields = Mirror(reflecting: job).children.compactMap(\.label).sorted()
        XCTAssertEqual(fields, ["expectedDuration", "fileURL", "index", "localeIdentifier", "sessionID"])
    }
}
