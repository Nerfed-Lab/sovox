#if SOVOX_SPEECHANALYZER
import Foundation
import Speech
import AVFoundation

/// iOS 26 SpeechAnalyzer path.
///
/// This file is behind the SOVOX_SPEECHANALYZER compilation condition on
/// purpose. The SpeechAnalyzer and SpeechTranscriber initialisers are the one
/// area of this project where the exact signatures could not be verified
/// against a compiler, and a signature drift here would otherwise take the whole
/// app down with it. The default build uses SFSpeechRecognizer with
/// requiresOnDeviceRecognition, which is equally on device and is a signature
/// that has been stable since iOS 13.
///
/// To switch over: Build Settings, Other Swift Flags, add
/// -D SOVOX_SPEECHANALYZER to the Sovox target.
@available(iOS 26.0, *)
enum SpeechAnalyzerTranscriber {

    /// Downloads and installs the language asset if it is not already present.
    static func ensureModelInstalled(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    static func isInstalled(locale: Locale) async -> Bool {
        await SpeechTranscriber.installedLocales.contains { $0.identifier == locale.identifier }
    }

    /// Streams the file through the analyzer. AVAudioFile reads incrementally,
    /// so nothing is loaded into memory as a Data blob.
    static func transcribe(fileURL: URL, locale: Locale) async throws -> String {
        try await ensureModelInstalled(locale: locale)

        let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: fileURL)

        async let collected: String = {
            var text = AttributedString("")
            for try await result in transcriber.results {
                text += result.text
            }
            return String(text.characters)
        }()

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await collected
    }
}
#endif
