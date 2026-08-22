import Foundation
import AVFoundation
import Speech
import ActivityKit
import UIKit
import Observation

enum SelfTestFix: Equatable, Sendable {
    case none
    case openAppSettings
    case requestSpeech
    case requestMicrophone
    case openShortcuts
    case getOutlook
    case openDictationHelp
}

struct SelfTestRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var passed: Bool?
    var detail: String
    var fix: SelfTestFix = .none
}

@MainActor
@Observable
final class SelfTest {
    /// Process wide, because a recording can be started from Siri, a Shortcut,
    /// the Control Centre control or the Live Activity, none of which can see a
    /// disabled button in Settings.
    static var smokeInProgress = false

    var rows: [SelfTestRow] = []
    var isRunning = false
    var smokeSummary: String?
    var smokeRunning = false
    var smokeProgress: Double = 0

    private let engine = AudioCaptureEngine()

    func runAll() async {
        isRunning = true
        rows = []
        rows.append(await micRow())
        rows.append(await speechRow())
        rows.append(await modelRow())
        rows.append(liveActivityRow())
        rows.append(backgroundModeRow())
        rows.append(documentsRow())
        rows.append(urlSchemeRow())
        rows.append(shortcutsRow())
        rows.append(outlookRow())
        rows.append(diskRow())
        isRunning = false
    }

    // MARK: Rows

    /// iOS only creates the Microphone row in Settings once the app has asked
    /// at least once, so routing an undetermined permission to Settings sends
    /// the user to a page that does not contain the switch. Ask instead.
    private func micRow() async -> SelfTestRow {
        var permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            _ = await RecorderController.shared.requestMicrophone()
            permission = AVAudioApplication.shared.recordPermission
        }
        switch permission {
        case .granted:
            return SelfTestRow(id: "mic", title: "Microphone permission", passed: true, detail: "Granted")
        case .denied:
            return SelfTestRow(id: "mic",
                               title: "Microphone permission",
                               passed: false,
                               detail: "Denied. Settings, Sovox, Microphone.",
                               fix: .openAppSettings)
        default:
            return SelfTestRow(id: "mic",
                               title: "Microphone permission",
                               passed: false,
                               detail: "Not decided yet. Tap Ask again and allow the prompt.",
                               fix: .requestMicrophone)
        }
    }

    private func speechRow() async -> SelfTestRow {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await SegmentTranscriber.requestAuthorisation()
        }
        let ok = status == .authorized
        return SelfTestRow(id: "speech",
                           title: "Speech recognition permission",
                           passed: ok,
                           detail: ok ? "Granted" : "Status is \(describe(status)).",
                           fix: ok ? .none : (status == .denied ? .openAppSettings : .requestSpeech))
    }

    private func modelRow() async -> SelfTestRow {
        let supported = await SegmentTranscriber.shared.supportsOnDevice()
        let locale = await SegmentTranscriber.shared.localeIdentifier()
        return SelfTestRow(id: "model",
                           title: "On device speech model",
                           passed: supported,
                           detail: supported
                             ? "Installed for \(locale)"
                             : "Not installed for \(locale). Turn on Settings, General, Keyboard, Enable Dictation and iOS downloads it.",
                           fix: supported ? .none : .openDictationHelp)
    }

    private func liveActivityRow() -> SelfTestRow {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        return SelfTestRow(id: "liveactivity",
                           title: "Live Activities enabled",
                           passed: enabled,
                           detail: enabled ? "On" : "Off. Settings, Sovox, Live Activities.",
                           fix: enabled ? .none : .openAppSettings)
    }

    private func backgroundModeRow() -> SelfTestRow {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let ok = modes.contains("audio")
        return SelfTestRow(id: "background",
                           title: "Background audio mode",
                           passed: ok,
                           detail: ok ? "UIBackgroundModes contains audio" : "Missing from Info.plist. Recording will die when backgrounded.")
    }

    private func documentsRow() -> SelfTestRow {
        let probe = RecordingPaths.documents.appendingPathComponent(".sovox-selftest")
        var writable = false
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            writable = (try? String(contentsOf: probe, encoding: .utf8)) == "ok"
            try? FileManager.default.removeItem(at: probe)
        } catch {
            writable = false
        }
        let sharing = Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool ?? false
        let inPlace = Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool ?? false
        let ok = writable && sharing && inPlace
        return SelfTestRow(id: "documents",
                           title: "Documents writable and in Files",
                           passed: ok,
                           detail: ok
                             ? "Visible as \(RecordingPaths.filesLocation)"
                             : "writable \(writable), UIFileSharingEnabled \(sharing), LSSupportsOpeningDocumentsInPlace \(inPlace)")
    }

    private func urlSchemeRow() -> SelfTestRow {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        let declared = schemes.contains(SovoxURL.scheme)
        let resolvable = UIApplication.shared.canOpenURL(SovoxURL.recording)
        let ok = declared && resolvable
        return SelfTestRow(id: "scheme",
                           title: "\(SovoxURL.scheme):// scheme resolves",
                           passed: ok,
                           detail: ok ? "Registered and resolvable" : "declared \(declared), canOpenURL \(resolvable)")
    }

    /// Two separate rows, because one missing app used to fail both and then
    /// offer the fix for the one that was actually fine.
    private func shortcutsRow() -> SelfTestRow {
        let ok = URL(string: "shortcuts://").map { UIApplication.shared.canOpenURL($0) } ?? false
        return SelfTestRow(id: "shortcuts",
                           title: "Shortcuts reachable",
                           passed: ok,
                           detail: ok ? "shortcuts:// resolves" : "Shortcuts is not installed. The hand off to ChatGPT or Claude needs it.",
                           fix: ok ? .none : .openShortcuts)
    }

    private func outlookRow() -> SelfTestRow {
        let ok = URL(string: "ms-outlook://").map { UIApplication.shared.canOpenURL($0) } ?? false
        return SelfTestRow(id: "outlook",
                           title: "Outlook reachable",
                           passed: ok,
                           detail: ok
                             ? "ms-outlook:// resolves"
                             : "Outlook is not installed. Everything else still works, the notes land on your clipboard and as a file instead of a prefilled draft.",
                           fix: ok ? .none : .getOutlook)
    }

    private func diskRow() -> SelfTestRow {
        guard let free = StorageGuard.freeBytes(at: RecordingPaths.documents) else {
            // Say so rather than print 0 bytes free, which reads as a failure
            // the user cannot act on.
            return SelfTestRow(id: "disk",
                               title: "Free space",
                               passed: false,
                               detail: "Free space could not be read. Recording is still allowed.")
        }
        let minutes = StorageGuard.recordableMinutes(freeBytes: free)
        let ok = StorageGuard.canStart(freeBytes: free)
        return SelfTestRow(id: "disk",
                           title: "Free space",
                           passed: ok,
                           detail: "\(StorageGuard.formatted(bytes: free)) free, about \(minutes) minutes recordable")
    }

    private func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorised"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    // MARK: Smoke test

    /// Records for sixty seconds with a twenty second segment interval, which
    /// forces at least two rollovers, then transcribes every segment, stitches
    /// them and compares the summed audio duration against the wall clock so a
    /// gap at a boundary would show up as a shortfall.
    func runSmokeTest() async {
        guard !smokeRunning else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            smokeSummary = "FAIL, microphone permission is not granted."
            return
        }
        guard !RecorderController.shared.isRecordingNow else {
            smokeSummary = "FAIL, a recording is in progress. Stop it first."
            return
        }
        SelfTest.smokeInProgress = true
        smokeRunning = true
        smokeProgress = 0
        smokeSummary = "Recording sixty seconds"

        let sessionID = "smoketest-" + RecordingPaths.uniqueSessionID(for: Date())
        let collector = SmokeCollector()
        engine.onEvent = { event in
            if case .segmentClosed(let index, let fileName, _) = event {
                collector.add(index: index, fileName: fileName)
            }
        }

        let clock = ElapsedClock(startDate: Date())
        do {
            try engine.start(sessionID: sessionID, segmentSeconds: 20)
        } catch {
            smokeSummary = "FAIL, engine did not start. \(error.localizedDescription)"
            smokeRunning = false
            SelfTest.smokeInProgress = false
            return
        }

        for tick in 1...60 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            smokeProgress = Double(tick) / 60.0 * 0.5
        }

        let final = engine.stop()
        if let final { collector.add(index: final.index, fileName: final.fileName) }
        let wallClock = clock.elapsed()

        let directory = RecordingPaths.sessionDirectory(sessionID)
        let files = collector.snapshot()
        var audioSeconds: TimeInterval = 0
        var transcripts: [SegmentTranscript] = []
        var failures: [String] = []

        for (offset, entry) in files.enumerated() {
            let url = directory.appendingPathComponent(entry.fileName)
            audioSeconds += Self.duration(of: url)
            do {
                let text = try await SegmentTranscriber.shared.transcribe(fileURL: url, expectedDuration: 30)
                transcripts.append(SegmentTranscript(index: entry.index, text: text))
            } catch {
                failures.append("seg \(entry.index): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
            smokeProgress = 0.5 + Double(offset + 1) / Double(max(1, files.count)) * 0.5
        }

        let stitched = TranscriptStitcher.stitch(transcripts)
        let gap = wallClock - audioSeconds
        let gapVerdict = abs(gap) <= 1.0 ? "no gap" : String(format: "%.2fs shortfall", gap)
        let segmentVerdict = files.count >= 2 ? "PASS" : "FAIL"

        var lines = [
            "\(segmentVerdict), \(files.count) segments rolled",
            String(format: "wall clock %.1fs, audio %.1fs, %@", wallClock, audioSeconds, gapVerdict),
            "transcript \(stitched.count) characters"
        ]
        if !failures.isEmpty { lines.append("transcription issues: " + failures.joined(separator: "; ")) }
        smokeSummary = lines.joined(separator: "\n")

        try? FileManager.default.removeItem(at: directory)
        smokeProgress = 1
        smokeRunning = false
        SelfTest.smokeInProgress = false
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }
}

/// Thread safe box, because segment events arrive on the audio io queue.
final class SmokeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(index: Int, fileName: String)] = []

    func add(index: Int, fileName: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !entries.contains(where: { $0.index == index }) else { return }
        entries.append((index, fileName))
    }

    func snapshot() -> [(index: Int, fileName: String)] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.index < $1.index }
    }
}
