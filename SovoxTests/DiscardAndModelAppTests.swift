import XCTest
@testable import Sovox

/// Phase 18. History was filling with rows reading "could not be transcribed"
/// for recordings where nobody said anything.
final class DiscardVerdictTests: XCTestCase {

    private func session(duration: TimeInterval,
                         states: [SegmentState],
                         complete: Bool = true,
                         source: SessionSource = .recorded) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date(), source: source)
        s.isComplete = complete
        s.duration = duration
        s.segments = states.enumerated().map { index, state in
            SegmentRecord(index: index + 1,
                          fileName: RecordingPaths.segmentFileName(index + 1),
                          duration: duration,
                          state: state,
                          text: state == .done ? "text" : "")
        }
        return s
    }

    // MARK: 18a, three outcomes

    func testEmptyIsTerminalButNeitherDoneNorFailed() {
        XCTAssertTrue(SegmentState.empty.isTerminal)
        XCTAssertFalse(SegmentState.empty.isFailure)
        XCTAssertTrue(SegmentState.empty.isEmptyResult)
        XCTAssertFalse(SegmentState.done.isEmptyResult)
        XCTAssertEqual(SegmentState.empty.label, "No speech")
    }

    func testEmptyAndFailedAreNotConflatedInTheTranscript() {
        let silent = session(duration: 120, states: [.empty])
        XCTAssertFalse(silent.stitchedTranscript.contains("could not be transcribed"),
                       "silence is not a failure")

        let broken = session(duration: 120, states: [.failed(reason: "x")])
        XCTAssertTrue(broken.stitchedTranscript.contains("could not be transcribed"),
                      "a lost segment still leaves a stated gap")
    }

    // MARK: 18b, discard

    func testAMisTapIsDiscardedWhateverTheState() {
        XCTAssertTrue(session(duration: 1.4, states: [.empty]).discardVerdict.discards)
        XCTAssertTrue(session(duration: 2.9, states: [.done]).discardVerdict.discards)
        // 18b says "always discard, whatever the state". At under three seconds
        // there is no meeting to lose.
        XCTAssertTrue(session(duration: 1.0, states: [.failed(reason: "x")]).discardVerdict.discards)
    }

    func testShortSilentRecordingsAreDiscarded() {
        XCTAssertTrue(session(duration: 42, states: [.empty, .empty]).discardVerdict.discards)
    }

    // MARK: 18c, never discard

    func testAFailedSegmentIsNeverSweptAwayAtAnyRealLength() {
        let s = session(duration: 5400, states: [.done, .failed(reason: "thermal")])
        XCTAssertFalse(s.discardVerdict.discards, "a 90 minute meeting must survive a retryable error")
        XCTAssertEqual(s.emptyStateLabel, "Transcription failed, tap to retry")
    }

    func testALongSilentRecordingIsKeptBecauseItMayMeanABrokenMicrophone() {
        let s = session(duration: 300, states: [.empty])
        XCTAssertFalse(s.discardVerdict.discards)
        XCTAssertEqual(s.emptyStateLabel, "No speech detected")
    }

    func testSixtySecondsIsTheBoundary() {
        XCTAssertTrue(session(duration: 59.5, states: [.empty]).discardVerdict.discards)
        XCTAssertFalse(session(duration: 60, states: [.empty]).discardVerdict.discards)
    }

    func testARecordingWithSpeechIsAlwaysKept() {
        XCTAssertFalse(session(duration: 30, states: [.done]).discardVerdict.discards)
        XCTAssertNil(session(duration: 30, states: [.done]).emptyStateLabel)
    }

    func testAnIncompleteOrPastedSessionIsNeverSwept() {
        XCTAssertFalse(session(duration: 1, states: [.empty], complete: false).discardVerdict.discards)
        var pasted = RecordingSession(id: "p", startDate: Date(), source: .pasted)
        pasted.isComplete = true
        pasted.transcript = "text"
        XCTAssertFalse(pasted.discardVerdict.discards)
        XCTAssertNil(pasted.emptyStateLabel)
    }

    func testStillRunningSegmentsMeanNoVerdictYet() {
        XCTAssertFalse(session(duration: 20, states: [.empty, .running]).isSilent)
        XCTAssertFalse(session(duration: 20, states: [.empty, .running]).discardVerdict.discards)
    }
}

/// Phase 15a. A wrong scheme and an uninstalled app both return false, and
/// telling someone to install what they are holding is worse than asking.
@MainActor
final class ModelAppProbeTests: XCTestCase {

    func testSchemesAreTheOnesDeclaredForQuerying() throws {
        let declared = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
        for destination in AIDestination.allCases {
            XCTAssertTrue(declared.contains(destination.appScheme),
                          "\(destination.appScheme) missing from LSApplicationQueriesSchemes, canOpenURL would always say false")
        }
        XCTAssertEqual(AIDestination.chatgpt.appScheme, "chatgpt")
        XCTAssertEqual(AIDestination.claude.appScheme, "claude")
    }

    func testNothingDetectedAndNothingProvenReadsAsUnknownNotAsNone() {
        // The test host has neither app, and no scheme has ever come back true,
        // which is exactly the ambiguous case.
        UserDefaults.standard.removeObject(forKey: "sovox.modelSchemeVerified")
        XCTAssertEqual(ModelAppProbe.availability(), .unknown)
        XCTAssertFalse(ModelAppAvailability.unknown.detectedAny)
    }

    func testOneConfirmedSchemeDoesNotVouchForTheOther() {
        // A right scheme must not make a wrong one look definitively absent:
        // that greys out a model the user has installed, with no way back.
        let defaults = UserDefaults.standard
        for destination in AIDestination.allCases {
            defaults.removeObject(forKey: "sovox.modelSchemeVerified.\(destination.rawValue)")
        }
        defer {
            for destination in AIDestination.allCases {
                defaults.removeObject(forKey: "sovox.modelSchemeVerified.\(destination.rawValue)")
            }
        }
        defaults.set(true, forKey: "sovox.modelSchemeVerified.chatgpt")

        XCTAssertTrue(ModelAppProbe.schemeConfirmed(.chatgpt))
        XCTAssertFalse(ModelAppProbe.schemeConfirmed(.claude),
                       "claude has never been seen to work, so a false probe for it is unknown")
        XCTAssertFalse(ModelAppProbe.schemesEverConfirmed,
                       "a clean sweep of negatives is only believable once every scheme has proven itself")
    }

    func testUnknownIsDistinctFromNone() {
        XCTAssertNotEqual(ModelAppAvailability.unknown, ModelAppAvailability.none)
        XCTAssertFalse(ModelAppAvailability.none.detectedAny)
        XCTAssertTrue(ModelAppAvailability.both.detectedAny)
        XCTAssertTrue(ModelAppAvailability.only(.claude).detectedAny)
    }
}

/// The audit found the discard rule deleting real meetings. A duration of zero
/// is the persisted default, not a measurement, and a force quit during the
/// first segment carries it for as long as an hour.
final class UnmeasuredDurationTests: XCTestCase {

    private func crashRecovered(_ state: SegmentState) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 0
        s.segments = [SegmentRecord(index: 1, fileName: "seg-01.m4a",
                                    duration: 0, state: state, text: "")]
        return s
    }

    func testAnUnmeasuredRecordingIsNeverSwept() {
        // The exact chain: jetsam mid segment, orphan file adopted with no
        // duration, its moov atom missing so verification throws.
        XCTAssertFalse(crashRecovered(.failed(reason: "unreadable")).discardVerdict.discards,
                       "this was deleting meetings up to an hour long")
        XCTAssertFalse(crashRecovered(.empty).discardVerdict.discards)
        XCTAssertFalse(crashRecovered(.done).discardVerdict.discards)
    }

    func testRetryingAFailedRecordingCannotDeleteIt() {
        var s = crashRecovered(.failed(reason: "unreadable"))
        XCTAssertEqual(s.emptyStateLabel, "Transcription failed, tap to retry")
        // Following the app's own instruction must not destroy the audio.
        XCTAssertFalse(s.discardVerdict.discards)
        s.duration = 1800
        XCTAssertFalse(s.discardVerdict.discards, "still failed, still kept")
    }

    func testAMeasuredMisTapIsStillSwept() {
        var s = crashRecovered(.empty)
        s.duration = 1.2
        XCTAssertTrue(s.discardVerdict.discards, "18b still holds for a real measurement")
    }

    func testASilentSegmentNoLongerBlocksAudioDeletion() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 300
        s.segments = [SegmentRecord(index: 1, fileName: "seg-01.m4a", duration: 150, state: .done, text: "words"),
                      SegmentRecord(index: 2, fileName: "seg-02.m4a", duration: 150, state: .empty, text: "")]
        XCTAssertTrue(s.isFullyTranscribed, "a quiet stretch is finished, not pending")
        XCTAssertTrue(s.canDeleteAudio)
    }

    func testAFailedSegmentStillBlocksAudioDeletion() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 300
        s.segments = [SegmentRecord(index: 1, fileName: "seg-01.m4a", duration: 300,
                                    state: .failed(reason: "x"), text: "")]
        XCTAssertFalse(s.isFullyTranscribed)
        XCTAssertFalse(s.canDeleteAudio, "the audio is still the only copy of those minutes")
    }
}
