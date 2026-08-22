import XCTest
@testable import Sovox

final class ElapsedClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_787_322_600)

    func testElapsedIsWallClockWhenNeverPaused() {
        let clock = ElapsedClock(startDate: t0)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(90)), 90, accuracy: 0.001)
    }

    /// Sixty seconds in the background, then a ten second pause, then resume.
    /// The computed elapsed must equal wall clock minus paused duration, which
    /// is exactly what a Timer driven counter would get wrong.
    func testBackgroundThenPauseThenResume() {
        var clock = ElapsedClock(startDate: t0)

        let afterBackground = t0.addingTimeInterval(60)
        XCTAssertEqual(clock.elapsed(at: afterBackground), 60, accuracy: 0.001)

        clock.pause(at: afterBackground)
        let midPause = afterBackground.addingTimeInterval(4)
        XCTAssertEqual(clock.elapsed(at: midPause), 60, accuracy: 0.001)

        let resumeAt = afterBackground.addingTimeInterval(10)
        clock.resume(at: resumeAt)
        XCTAssertEqual(clock.accumulatedPaused, 10, accuracy: 0.001)

        let end = resumeAt.addingTimeInterval(30)
        let wall = end.timeIntervalSince(t0)
        XCTAssertEqual(wall, 100, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: end), wall - 10, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: end), 90, accuracy: 0.001)
    }

    func testElapsedFreezesWhilePaused() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(600)), 10, accuracy: 0.001)
    }

    func testDoublePauseIsIgnored() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        clock.pause(at: t0.addingTimeInterval(20))
        clock.resume(at: t0.addingTimeInterval(30))
        XCTAssertEqual(clock.accumulatedPaused, 20, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(30)), 10, accuracy: 0.001)
    }

    func testResumeWithoutPauseIsANoOp() {
        var clock = ElapsedClock(startDate: t0)
        clock.resume(at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.accumulatedPaused, 0, accuracy: 0.001)
    }

    func testMultiplePauseCyclesAccumulate() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        clock.resume(at: t0.addingTimeInterval(15))
        clock.pause(at: t0.addingTimeInterval(20))
        clock.resume(at: t0.addingTimeInterval(27))
        XCTAssertEqual(clock.accumulatedPaused, 12, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(60)), 48, accuracy: 0.001)
    }

    func testThreeHourRunStaysExact() {
        let clock = ElapsedClock(startDate: t0)
        let threeHours = t0.addingTimeInterval(3 * 3600)
        XCTAssertEqual(clock.elapsed(at: threeHours), 10800, accuracy: 0.001)
    }

    func testNegativeIsClamped() {
        let clock = ElapsedClock(startDate: t0)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(-50)), 0, accuracy: 0.001)
    }

    func testTotalPausedIncludesAnOpenPause() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.totalPaused(at: t0.addingTimeInterval(25)), 15, accuracy: 0.001)
    }

    func testClockFormatting() {
        XCTAssertEqual(DurationFormat.clock(0), "0:00")
        XCTAssertEqual(DurationFormat.clock(59), "0:59")
        XCTAssertEqual(DurationFormat.clock(600), "10:00")
        XCTAssertEqual(DurationFormat.clock(3600), "1:00:00")
        XCTAssertEqual(DurationFormat.clock(10_805), "3:00:05")
    }
}
