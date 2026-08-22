import XCTest
@testable import Sovox

/// Regression cover for the Live Activity clock. The system renders elapsed time
/// from timerRange plus pauseTime with no help from the app, so the mapping from
/// ElapsedClock into ContentState is the only place this can go wrong, and when
/// it does the user sees the clock jump backwards mid meeting.
final class LiveActivityStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_787_322_600)

    private func state(_ clock: ElapsedClock) -> SovoxAttributes.ContentState {
        SovoxAttributes.ContentState.from(clock: clock,
                                            segmentIndex: 1,
                                            nextRollDate: nil,
                                            remainingMinutes: 100,
                                            lowStorage: false)
    }

    func testRunningClockReadsTrueElapsed() {
        let clock = ElapsedClock(startDate: t0)
        let now = t0.addingTimeInterval(600)
        XCTAssertEqual(state(clock).displayedElapsed(at: now), 600, accuracy: 0.001)
    }

    func testPausedClockFreezesAtTrueElapsed() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(600))
        let content = state(clock)
        XCTAssertEqual(content.displayedElapsed(at: t0.addingTimeInterval(900)), 600, accuracy: 0.001)
    }

    /// The regression. Rebuilding the state part way through a pause, which any
    /// discrete update does, must not move the range base. Using totalPaused
    /// here subtracted the open pause a second time and the clock ran backwards.
    func testBaseDoesNotMoveWhenStateIsRebuiltDuringAPause() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(600))

        let atPause = state(clock)
        let fiveMinutesLater = state(clock)

        XCTAssertEqual(atPause.timerRange.lowerBound, fiveMinutesLater.timerRange.lowerBound)
        XCTAssertEqual(fiveMinutesLater.displayedElapsed(at: t0.addingTimeInterval(900)), 600, accuracy: 0.001)
    }

    func testBaseAdvancesOnlyOnceAPauseHasEnded() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(600))
        let paused = state(clock)
        clock.resume(at: t0.addingTimeInterval(900))
        let resumed = state(clock)

        XCTAssertEqual(resumed.timerRange.lowerBound.timeIntervalSince(paused.timerRange.lowerBound),
                       300, accuracy: 0.001)
        XCTAssertEqual(resumed.displayedElapsed(at: t0.addingTimeInterval(1200)), 900, accuracy: 0.001)
    }

    func testMultiplePauseCyclesStayInStepWithElapsedClock() {
        var clock = ElapsedClock(startDate: t0)
        clock.pause(at: t0.addingTimeInterval(100))
        clock.resume(at: t0.addingTimeInterval(160))
        clock.pause(at: t0.addingTimeInterval(200))
        clock.resume(at: t0.addingTimeInterval(230))

        let now = t0.addingTimeInterval(600)
        XCTAssertEqual(state(clock).displayedElapsed(at: now), clock.elapsed(at: now), accuracy: 0.001)
    }

    func testFinishedFlagDefaultsOffAndIsPausedIsIndependent() {
        let running = state(ElapsedClock(startDate: t0))
        XCTAssertFalse(running.isFinished)
        XCTAssertFalse(running.isPaused)

        var finished = running
        finished.isFinished = true
        finished.pausedAt = t0.addingTimeInterval(600)
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.displayedElapsed(at: t0.addingTimeInterval(3600)), 600, accuracy: 0.001)
    }

    func testTimerRangeIsWideEnoughForALongMeeting() {
        let content = state(ElapsedClock(startDate: t0))
        let span = content.timerRange.upperBound.timeIntervalSince(content.timerRange.lowerBound)
        XCTAssertGreaterThanOrEqual(span, 8 * 3600)
    }
}
