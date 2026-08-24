import XCTest
@testable import Sovox

/// Phase 19f. Aligned on silence, not on the clock, because a fixed window cuts
/// through the middle of a clause.
final class TranscriptMergeTests: XCTestCase {

    private func words(_ spec: [(String, TimeInterval, TimeInterval)]) -> [TimedWord] {
        spec.map { TimedWord(text: $0.0, start: $0.1, duration: $0.2) }
    }

    func testAPauseEndsAWindowOnceTheMinimumIsPast() {
        // Four seconds of speech, a 600ms pause, then more.
        let primary = words([("we", 0, 0.4), ("should", 0.5, 0.5), ("confirm", 1.1, 0.7),
                             ("pricing", 2.0, 0.8), ("today", 3.0, 1.0),
                             ("kal", 4.6, 0.4), ("milte", 5.1, 0.5), ("hain", 5.7, 0.5)])
        let ranges = TranscriptMerge.boundaries(for: primary)
        XCTAssertEqual(ranges.count, 2, "the 600ms gap after four seconds is a boundary")
        XCTAssertEqual(ranges[0].upperBound, 4.0, accuracy: 0.001)
        XCTAssertEqual(ranges[1].lowerBound, 4.6, accuracy: 0.001)
    }

    func testAPauseTooEarlyDoesNotSplit() {
        // A gap at one second would leave a window under the three second floor.
        let primary = words([("yes", 0, 0.3), ("so", 1.5, 0.3), ("the", 1.9, 0.2),
                             ("budget", 2.2, 0.6), ("stands", 3.0, 0.8)])
        XCTAssertEqual(TranscriptMerge.boundaries(for: primary).count, 1)
    }

    func testAWindowIsSplitBeforeItOverrunsTheMaximum() {
        // Continuous speech with no gap at all, thirty seconds of it.
        let primary = words((0..<30).map { ("word\($0)", TimeInterval($0), 0.9) })
        let ranges = TranscriptMerge.boundaries(for: primary)
        XCTAssertGreaterThan(ranges.count, 1, "twenty seconds is a hard ceiling")
        for range in ranges {
            XCTAssertLessThanOrEqual(range.upperBound - range.lowerBound,
                                     TranscriptMerge.maximumWindow + 1.0)
        }
    }

    func testBothReadingsLandInTheSameWindow() {
        let primary = words([("call", 0, 0.4), ("mil", 0.5, 0.4), ("they", 1.0, 0.4),
                             ("in", 1.5, 0.3), ("tomorrow", 1.9, 0.9)])
        let secondary = words([("कल", 0, 0.4), ("मिलते", 0.5, 0.4), ("हैं", 1.0, 0.4),
                               ("कल", 1.5, 0.3), ("सुबह", 1.9, 0.9)])
        let windows = TranscriptMerge.windows(primary: primary, secondary: secondary)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].primary, "call mil they in tomorrow")
        XCTAssertEqual(windows[0].secondary, "कल मिलते हैं कल सुबह")
    }

    func testAWindowNeitherPassHeardAnythingInIsOmitted() {
        let primary = words([("hello", 0, 0.5)])
        let windows = TranscriptMerge.windows(primary: primary, secondary: [])
        XCTAssertEqual(windows.count, 1, "the primary heard something, so it stays")
        XCTAssertTrue(windows[0].secondary.isEmpty)
        XCTAssertTrue(TranscriptMerge.windows(primary: [], secondary: []).isEmpty)
    }

    func testDevanagariPassesThroughUntouched() {
        let secondary = words([("मीटिंग", 0, 0.6)])
        let rendered = TranscriptMerge.render(
            TranscriptMerge.windows(primary: words([("meeting", 0, 0.6)]), secondary: secondary))
        XCTAssertTrue(rendered.contains("मीटिंग"), "transliterating here would lose information")
        XCTAssertTrue(rendered.contains("EN: meeting"))
        XCTAssertTrue(rendered.hasPrefix("[00:00]"))
    }

    func testTimestampsAreMinutesAndSeconds() {
        XCTAssertEqual(TranscriptMerge.timestamp(0), "[00:00]")
        XCTAssertEqual(TranscriptMerge.timestamp(252), "[04:12]")
        XCTAssertEqual(TranscriptMerge.timestamp(3661), "[61:01]")
    }

    func testNothingScoresOrClassifiesTheTwoReadings() {
        // The merge lays both side by side. If it ever started preferring one,
        // this window would not carry the poorer reading at all.
        let windows = TranscriptMerge.windows(
            primary: words([("garbled", 0, 0.5)]),
            secondary: words([("साफ", 0, 0.5)]))
        XCTAssertEqual(windows[0].primary, "garbled")
        XCTAssertEqual(windows[0].secondary, "साफ")
    }
}

/// Phase 19b, 19e, 19g, 19h.
final class DualLanguagePipelineTests: XCTestCase {

    private func session(secondary: Bool, segments count: Int = 1,
                         wordsPerSegment: Int = 5) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = TimeInterval(count * 60)
        s.segments = (1...count).map { index in
            var record = SegmentRecord(index: index,
                                       fileName: RecordingPaths.segmentFileName(index),
                                       duration: 60,
                                       state: .done,
                                       text: "english reading \(index)")
            record.primaryWords = (0..<wordsPerSegment).map {
                TimedWord(text: "word\($0)", start: TimeInterval($0) * 1.1, duration: 0.5)
            }
            if secondary {
                record.secondaryText = "हिंदी \(index)"
                record.secondaryWords = (0..<wordsPerSegment).map {
                    TimedWord(text: "शब्द\($0)", start: TimeInterval($0) * 1.1, duration: 0.5)
                }
            }
            return record
        }
        return s
    }

    // MARK: 19e, the primary stays canonical

    func testTheSecondaryReadingNeverLeaksIntoTheStoredTranscript() {
        let s = session(secondary: true)
        XCTAssertFalse(s.stitchedTranscript.contains("हिंदी"))
        XCTAssertFalse(TranscriptStitcher.preview(s.stitchedTranscript).contains("हिंदी"))
        XCTAssertTrue(s.stitchedTranscript.contains("english reading 1"))
    }

    func testTheMergedPathIsOnlyTakenWhenASecondReadingExists() {
        XCTAssertTrue(session(secondary: true).hasMergedReading)
        // With no second reading anywhere, generation uses the single
        // transcript prompt unchanged. The merged rendering still exists and
        // still carries the primary, which is what stops a partial failure
        // dropping segments, but nothing reads it.
        let single = session(secondary: false)
        XCTAssertFalse(single.hasMergedReading)
        XCTAssertFalse(single.mergedTranscript.contains("HI: \u{939}"))
    }

    func testTimestampsRunAcrossTheWholeRecordingNotPerSegment() {
        let merged = session(secondary: true, segments: 3).mergedTranscript
        XCTAssertTrue(merged.contains("[00:00]"))
        XCTAssertTrue(merged.contains("[01:00]"), "segment two starts a minute in")
        XCTAssertTrue(merged.contains("[02:00]"))
    }

    // MARK: 19g, the prompt

    func testTheToggleOffPromptIsUnchanged() {
        let plain = PromptBuilder.build(transcript: "hello", modes: [.cleanedTranscript],
                                        ownName: "R", date: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(plain.contains(PromptBuilder.mergedPreamble))
        XCTAssertFalse(plain.contains("MERGED TRANSCRIPT"))
    }

    func testTheMergedPromptCarriesThePreambleImmediatelyBeforeTheTranscript() {
        let merged = PromptBuilder.build(transcript: "[00:00]\nEN: a\nHI: ब",
                                         modes: [.cleanedTranscript],
                                         ownName: "R",
                                         date: Date(timeIntervalSince1970: 0),
                                         merged: true)
        guard let preamble = merged.range(of: "MERGED TRANSCRIPT"),
              let fence = merged.range(of: PromptBuilder.transcriptBegin) else {
            return XCTFail("missing blocks")
        }
        XCTAssertTrue(preamble.upperBound < fence.lowerBound)
        XCTAssertTrue(merged.contains("never recover Hindi from a name"))
        XCTAssertTrue(merged.contains("Never output Devanagari"))
    }

    func testTheResolutionPromptAsksForNoSummary() {
        let prompt = PromptBuilder.resolutionPrompt(merged: "[00:00]\nEN: a\nHI: ब")
        XCTAssertTrue(prompt.contains("MERGED TRANSCRIPT"))
        XCTAssertTrue(prompt.contains("No summary"))
        XCTAssertFalse(prompt.contains("SUBJECT:"), "stage one is not producing an email")
    }

    // MARK: 19h, two stages

    func testShortRecordingsStayASingleCall() {
        XCTAssertFalse(StagedGeneration.isNeeded(for: session(secondary: true)))
    }

    func testTheThresholdIsMeasuredOnTheMergedText() {
        let big = session(secondary: true, segments: 40, wordsPerSegment: 400)
        XCTAssertGreaterThan(big.mergedTranscript.count, StagedGeneration.threshold)
        XCTAssertTrue(StagedGeneration.isNeeded(for: big))
    }

    func testStageTwoRunsOnceOverTheWholeConversation() {
        var plan = StagedGeneration.plan(for: session(secondary: true, segments: 3),
                                         modes: [.actionsAndDecisions],
                                         customActions: [],
                                         conversationType: .auto,
                                         destination: .claude)
        XCTAssertEqual(plan.totalCount, 3)
        plan.resolved[1] = "one"
        plan.resolved[2] = "two"
        XCTAssertEqual(plan.nextSegment, 3, "still resolving")
        XCTAssertFalse(plan.isReadyForSynthesis)
        plan.resolved[3] = "three"
        XCTAssertTrue(plan.isReadyForSynthesis)
        XCTAssertEqual(plan.resolvedTranscript, "one\n\ntwo\n\nthree",
                       "one synthesis over everything, in order, never stitched summaries")
    }

    func testProgressNamesTheStage() {
        var plan = StagedGeneration.plan(for: session(secondary: true, segments: 2),
                                         modes: [], customActions: [],
                                         conversationType: .auto, destination: .chatgpt)
        XCTAssertEqual(plan.progressLabel, "Resolving segment 1 of 2")
        plan.resolved[1] = "a"
        XCTAssertEqual(plan.progressLabel, "Resolving segment 2 of 2")
        plan.resolved[2] = "b"
        XCTAssertEqual(plan.progressLabel, "Generating notes")
    }

    func testThePlanSurvivesEncoding() throws {
        let plan = StagedGeneration.plan(for: session(secondary: true, segments: 2),
                                         modes: [.cleanedTranscript], customActions: [],
                                         conversationType: .executive, destination: .claude)
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(try JSONDecoder().decode(StagedGeneration.self, from: data), plan)
    }
}

/// 19b. Two languages, never the same one twice.
@MainActor
final class SecondaryLanguageSettingTests: XCTestCase {

    func testChoosingTheSameLanguageTwiceClearsTheOther() {
        let settings = AppSettings.shared
        let primary = settings.transcriptionLocale
        let secondary = settings.secondaryLocale
        defer { settings.transcriptionLocale = primary; settings.secondaryLocale = secondary }

        settings.transcriptionLocale = "en_IN"
        settings.secondaryLocale = "en_IN"
        XCTAssertNotEqual(TranscriptionLocale.normalise(settings.transcriptionLocale),
                          TranscriptionLocale.normalise(settings.secondaryLocale))
    }

    func testTheSecondPassIsSkippedWhenTheToggleIsOff() {
        let settings = AppSettings.shared
        let was = settings.dualLanguage
        defer { settings.dualLanguage = was }
        settings.dualLanguage = false
        XCTAssertNil(settings.activeSecondaryLocale)
    }

    func testAnOnlineOnlySecondaryIsNeverUsed() {
        let settings = AppSettings.shared
        let was = (settings.dualLanguage, settings.secondaryLocale)
        defer { settings.dualLanguage = was.0; settings.secondaryLocale = was.1 }
        settings.dualLanguage = true
        settings.secondaryLocale = "hi_IN"
        // On a device where Hindi cannot run offline this must be nil rather
        // than a language that returns nothing on every segment.
        if TranscriptionLocale.availability("hi_IN") != .ready {
            XCTAssertNil(settings.activeSecondaryLocale)
        } else {
            XCTAssertEqual(settings.activeSecondaryLocale, "hi_IN")
        }
    }
}

/// The Phase 19 audit found the merge dropping whole segments and the second
/// pass being skipped in the one case it exists for.
final class MergeDegradationTests: XCTestCase {

    private func segment(_ index: Int, secondary: Bool) -> SegmentRecord {
        var record = SegmentRecord(index: index,
                                   fileName: RecordingPaths.segmentFileName(index),
                                   duration: 60,
                                   state: .done,
                                   text: "english \(index)")
        record.primaryWords = [TimedWord(text: "english", start: 0, duration: 0.5),
                               TimedWord(text: "words\(index)", start: 0.6, duration: 0.5)]
        if secondary {
            record.secondaryText = "हिंदी \(index)"
            record.secondaryWords = [TimedWord(text: "हिंदी", start: 0, duration: 0.5),
                                     TimedWord(text: "शब्द", start: 0.6, duration: 0.5)]
        }
        return record
    }

    func testOneFailedSecondaryDoesNotDeleteThatSegmentFromThePrompt() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 180
        s.segments = [segment(1, secondary: true),
                      segment(2, secondary: false),   // the second pass failed here
                      segment(3, secondary: true)]

        let merged = s.mergedTranscript
        XCTAssertTrue(merged.contains("words1"))
        XCTAssertTrue(merged.contains("words2"),
                      "a failed second pass must not silently remove the meeting's middle")
        XCTAssertTrue(merged.contains("words3"))
        XCTAssertEqual(s.mergedWindowCount, 3)
    }

    func testTheFailedSegmentStillCarriesAnEmptyHindiLine() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.segments = [segment(1, secondary: false)]
        XCTAssertTrue(s.mergedTranscript.contains("EN: english words1"))
        XCTAssertTrue(s.mergedTranscript.contains("HI: "))
    }

    func testAPureSecondaryLanguageRecordingIsNotTreatedAsSilence() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 30
        var record = segment(1, secondary: true)
        // The English model heard nothing. The Hindi model heard the meeting.
        record.state = .empty
        record.text = ""
        s.segments = [record]

        XCTAssertFalse(s.isSilent, "it was a conversation, in the other language")
        XCTAssertFalse(s.discardVerdict.discards, "and it must not be swept away")
    }

    func testATrulySilentRecordingIsStillSwept() {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = 30
        var record = segment(1, secondary: false)
        record.state = .empty
        record.text = ""
        s.segments = [record]
        XCTAssertTrue(s.isSilent)
        XCTAssertTrue(s.discardVerdict.discards)
    }
}

/// The audit found the merged prompt losing whole segments two different ways,
/// the second of which was a memory optimisation defeating the fix for the
/// first. Both cost the user a stretch of the meeting with nothing on screen
/// to say so.
final class MergedCompletenessTests: XCTestCase {

    private func session(secondaryOn: [Int], timingsOn: [Int], count: Int = 4) -> RecordingSession {
        var s = RecordingSession(id: "s", startDate: Date())
        s.isComplete = true
        s.duration = TimeInterval(count * 60)
        s.segments = (1...count).map { index in
            var record = SegmentRecord(index: index,
                                       fileName: RecordingPaths.segmentFileName(index),
                                       duration: 60,
                                       state: .done,
                                       text: "spoken words in segment \(index)")
            if timingsOn.contains(index) {
                record.primaryWords = [TimedWord(text: "spoken", start: 0, duration: 0.5),
                                       TimedWord(text: "seg\(index)", start: 0.6, duration: 0.5)]
            }
            if secondaryOn.contains(index) {
                record.secondaryText = "हिंदी \(index)"
                record.secondaryWords = [TimedWord(text: "हिंदी", start: 0, duration: 0.5)]
            }
            return record
        }
        return s
    }

    func testEverySegmentReachesThePromptWhenOneSecondPassFailed() {
        // Segments 1 and 2 have both readings. 3 and 4 lost the second pass and
        // with it, before the fix, their timings.
        let s = session(secondaryOn: [1, 2], timingsOn: [1, 2])
        let merged = s.mergedTranscript
        for index in 1...4 {
            XCTAssertTrue(merged.contains("segment \(index)") || merged.contains("seg\(index)"),
                          "segment \(index) is missing from the prompt entirely")
        }
    }

    func testASegmentWithNoTimingsStillAppearsAsAnEnglishBlock() {
        let s = session(secondaryOn: [1], timingsOn: [1])
        let merged = s.mergedTranscript
        XCTAssertTrue(merged.contains("EN: spoken words in segment 2"))
        XCTAssertTrue(merged.contains("[01:00]"), "and at the right point in the recording")
    }

    func testStageOneCoversEverySegmentThatHoldsSpeech() {
        let s = session(secondaryOn: [1, 2], timingsOn: [1, 2])
        let plan = StagedGeneration.plan(for: s, modes: [.actionsAndDecisions],
                                         customActions: [], conversationType: .auto,
                                         destination: .claude)
        XCTAssertEqual(plan.segmentIndices, [1, 2, 3, 4],
                       "a segment left out here is left out of the synthesis too")
    }

    func testASingleReadingSegmentSkipsTheRoundTripButKeepsItsWords() {
        let s = session(secondaryOn: [1], timingsOn: [1])
        var plan = StagedGeneration.plan(for: s, modes: [], customActions: [],
                                         conversationType: .auto, destination: .claude)
        XCTAssertEqual(plan.nextSegment, 1, "only the two reading segment needs resolving")
        plan.resolved[1] = "resolved one"
        XCTAssertTrue(plan.isReadyForSynthesis)
        let synthesis = plan.resolvedTranscript
        XCTAssertTrue(synthesis.contains("resolved one"))
        for index in 2...4 {
            XCTAssertTrue(synthesis.contains("segment \(index)"),
                          "segment \(index) must still reach stage two")
        }
    }
}
