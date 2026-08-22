import XCTest
import AVFoundation
@testable import Sovox

/// Regression cover for OSStatus -50 on a real device.
///
/// allowBluetoothA2DP and defaultToSpeaker are documented against the
/// playAndRecord category. Requesting either alongside .record makes
/// setCategory fail with paramErr, and the first build shipped a fallback that
/// still carried allowBluetoothA2DP, so both rungs failed and recording could
/// not start at all.
final class AudioSessionLadderTests: XCTestCase {

    private var ladder: [AVAudioSession.CategoryOptions] { AudioCaptureEngine.categoryLadder }

    func testFirstRungRequestsEverythingTheSpecAsksFor() {
        let first = ladder[0]
        XCTAssertTrue(first.contains(.allowBluetoothHFP))
        XCTAssertTrue(first.contains(.allowBluetoothA2DP))
        XCTAssertTrue(first.contains(.defaultToSpeaker))
    }

    func testLadderEndsWithAnEmptyOptionSet() {
        XCTAssertEqual(ladder.last, [])
    }

    func testEveryRungIsAStrictSubsetOfTheOneAbove() {
        for index in 1..<ladder.count {
            let above = ladder[index - 1]
            let below = ladder[index]
            XCTAssertTrue(below.isSubset(of: above), "rung \(index) is not a subset of rung \(index - 1)")
            XCTAssertNotEqual(below, above, "rung \(index) is identical to rung \(index - 1), which wastes an attempt")
        }
    }

    /// The one option that is genuinely valid with .record must survive as long
    /// as possible, so a Bluetooth headset mic keeps working on the rung that
    /// actually succeeds.
    func testBluetoothHFPSurvivesUntilTheFinalRung() {
        for rung in ladder.dropLast() {
            XCTAssertTrue(rung.contains(.allowBluetoothHFP))
        }
    }

    func testAtLeastOneRungContainsOnlyOptionsValidForTheRecordCategory() {
        let invalidForRecord: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
        XCTAssertTrue(ladder.contains { $0.isDisjoint(with: invalidForRecord) },
                      "no rung avoids the options that make setCategory fail with -50")
    }

    func testLadderIsBoundedSoStartCannotSpinForever() {
        XCTAssertGreaterThanOrEqual(ladder.count, 2)
        XCTAssertLessThanOrEqual(ladder.count, 6)
    }
}
