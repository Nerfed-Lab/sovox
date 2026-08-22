import XCTest
@testable import Sovox

final class StorageGuardTests: XCTestCase {

    private let oneGB: Int64 = 1_073_741_824
    private let threeHundredMB: Int64 = 314_572_800

    func testStartBoundaryExactlyAtOneGigabyte() {
        XCTAssertTrue(StorageGuard.canStart(freeBytes: oneGB))
    }

    func testStartBoundaryOneByteBelow() {
        XCTAssertFalse(StorageGuard.canStart(freeBytes: oneGB - 1))
    }

    func testStartBoundaryOneByteAbove() {
        XCTAssertTrue(StorageGuard.canStart(freeBytes: oneGB + 1))
    }

    func testStartRefusedAtZero() {
        XCTAssertFalse(StorageGuard.canStart(freeBytes: 0))
    }

    func testStopBoundaryExactlyAtThreeHundredMegabytes() {
        XCTAssertFalse(StorageGuard.mustStop(freeBytes: threeHundredMB))
    }

    func testStopBoundaryOneByteBelow() {
        XCTAssertTrue(StorageGuard.mustStop(freeBytes: threeHundredMB - 1))
    }

    func testStopBoundaryOneByteAbove() {
        XCTAssertFalse(StorageGuard.mustStop(freeBytes: threeHundredMB + 1))
    }

    func testWarningBandSitsBetweenTheTwoThresholds() {
        XCTAssertTrue(StorageGuard.shouldWarn(freeBytes: threeHundredMB))
        XCTAssertTrue(StorageGuard.shouldWarn(freeBytes: StorageGuard.warningBytes - 1))
        XCTAssertFalse(StorageGuard.shouldWarn(freeBytes: StorageGuard.warningBytes))
        XCTAssertFalse(StorageGuard.shouldWarn(freeBytes: threeHundredMB - 1))
    }

    func testRecordableMinutesIsZeroAtAndBelowTheStopThreshold() {
        XCTAssertEqual(StorageGuard.recordableMinutes(freeBytes: threeHundredMB), 0)
        XCTAssertEqual(StorageGuard.recordableMinutes(freeBytes: threeHundredMB - 1), 0)
        XCTAssertEqual(StorageGuard.recordableMinutes(freeBytes: 0), 0)
    }

    func testRecordableMinutesAtOneGigabyte() {
        // 1 GB minus the 300 MB floor, at 8000 bytes per second.
        let expected = Int((oneGB - threeHundredMB) / (8_000 * 60))
        XCTAssertEqual(StorageGuard.recordableMinutes(freeBytes: oneGB), expected)
        XCTAssertEqual(expected, 1581)
    }

    func testBitrateMatchesRoughlyThirtyMegabytesPerHour() {
        let perHour = StorageGuard.estimatedBytes(forSeconds: 3600)
        XCTAssertEqual(perHour, 28_800_000)
        XCTAssertLessThan(perHour, 32_000_000)
        XCTAssertGreaterThan(perHour, 25_000_000)
    }

    func testThreeHourMeetingFitsInsideOneGigabyte() {
        XCTAssertLessThan(StorageGuard.estimatedBytes(forSeconds: 3 * 3600), oneGB)
    }
}
