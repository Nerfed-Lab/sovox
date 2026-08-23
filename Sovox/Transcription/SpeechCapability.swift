import Foundation
import Speech

/// Phase 19a. What Hindi recognition this device can actually do.
///
/// Answered by asking the frameworks at runtime, on the device in question.
/// Nothing here is hardcoded and nothing is inferred from the OS version: the
/// simulator reports a different answer from a phone, and two phones on the
/// same iOS version can differ by which assets their owner installed.
enum SpeechTier: String, Sendable {
    /// A Devanagari locale is in SpeechTranscriber.supportedLocales. Both
    /// passes run through SpeechTranscriber, which is long form capable.
    case one
    /// It is not, but the legacy recogniser has an installed on device Hindi
    /// model. Secondary pass runs through SFSpeechRecognizer, short form, so
    /// long audio needs chunking.
    case two
    /// Neither works. The secondary language is disabled and said so.
    case three

    var title: String {
        switch self {
        case .one: return "Tier 1"
        case .two: return "Tier 2"
        case .three: return "Tier 3"
        }
    }

    var summary: String {
        switch self {
        case .one: return "SpeechTranscriber handles both languages on this device."
        case .two: return "Hindi runs through the older recogniser, on device, in short chunks."
        case .three: return "Hindi transcription is not available offline on this device."
        }
    }
}

struct SpeechCapabilityReport: Sendable, Equatable {
    var probedAt: Date
    var primaryIdentifier: String
    var secondaryIdentifier: String

    var analyzerAvailable: Bool
    var analyzerSupported: [String]
    var analyzerInstalled: [String]
    var analyzerDevanagari: [String]

    var legacySupportedCount: Int
    var legacySecondaryExists: Bool
    var legacySecondaryAvailable: Bool
    var legacySecondaryOnDevice: Bool
    var legacyPrimaryOnDevice: Bool

    var tier: SpeechTier

    /// True when the device can dictate Hindi but only with a network.
    ///
    /// This is the trap the phase calls out: a Hindi keyboard that works in
    /// Notes proves nothing, because that path is allowed to reach Apple's
    /// servers and this app is not. Reported as Tier 3, never as available.
    var secondaryIsOnlineOnly: Bool {
        legacySecondaryAvailable && !legacySecondaryOnDevice && analyzerDevanagari.isEmpty
    }

    /// Pasteable, because the answer usually has to travel from the phone to
    /// whoever is reading it.
    var plainText: String {
        var lines: [String] = []
        lines.append("Sovox speech capability probe")
        lines.append("probed: \(ISO8601DateFormatter().string(from: probedAt))")
        lines.append("device: \(SpeechCapabilityProbe.deviceDescription)")
        lines.append("tier: \(tier.title) — \(tier.summary)")
        lines.append("")
        lines.append("SpeechTranscriber.isAvailable: \(analyzerAvailable)")
        lines.append("SpeechTranscriber.supportedLocales (\(analyzerSupported.count)):")
        lines.append(analyzerSupported.isEmpty ? "  none" : "  " + analyzerSupported.joined(separator: ", "))
        lines.append("SpeechTranscriber.installedLocales (\(analyzerInstalled.count)):")
        lines.append(analyzerInstalled.isEmpty ? "  none" : "  " + analyzerInstalled.joined(separator: ", "))
        lines.append("Devanagari in supported: \(analyzerDevanagari.isEmpty ? "none" : analyzerDevanagari.joined(separator: ", "))")
        lines.append("")
        lines.append("SFSpeechRecognizer.supportedLocales count: \(legacySupportedCount)")
        lines.append("secondary \(secondaryIdentifier): exists=\(legacySecondaryExists) available=\(legacySecondaryAvailable) onDevice=\(legacySecondaryOnDevice)")
        lines.append("primary \(primaryIdentifier): onDevice=\(legacyPrimaryOnDevice)")
        lines.append("online only secondary: \(secondaryIsOnlineOnly)")
        return lines.joined(separator: "\n")
    }
}

enum SpeechCapabilityProbe {

    static var deviceDescription: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return "\(machine), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    /// Reads capability only. Dispatches no recognition request of any kind, so
    /// probing cannot itself reach a server.
    static func run(primary: String = TranscriptionLocale.defaultIdentifier,
                    secondary: String = "hi_IN") async -> SpeechCapabilityReport {
        let analyzerAvailable = SpeechTranscriber.isAvailable
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let devanagari = supported.filter { isDevanagari($0) }.map(\.identifier)

        let legacyAll = SFSpeechRecognizer.supportedLocales()
        let secondaryRecogniser = SFSpeechRecognizer(locale: Locale(identifier: TranscriptionLocale.normalise(secondary)))
        let primaryRecogniser = SFSpeechRecognizer(locale: Locale(identifier: TranscriptionLocale.normalise(primary)))

        let tier: SpeechTier
        if analyzerAvailable && !devanagari.isEmpty {
            tier = .one
        } else if secondaryRecogniser?.supportsOnDeviceRecognition == true {
            tier = .two
        } else {
            tier = .three
        }

        return SpeechCapabilityReport(
            probedAt: Date(),
            primaryIdentifier: TranscriptionLocale.normalise(primary),
            secondaryIdentifier: TranscriptionLocale.normalise(secondary),
            analyzerAvailable: analyzerAvailable,
            analyzerSupported: supported.map(\.identifier).sorted(),
            analyzerInstalled: installed.map(\.identifier).sorted(),
            analyzerDevanagari: devanagari.sorted(),
            legacySupportedCount: legacyAll.count,
            legacySecondaryExists: secondaryRecogniser != nil,
            legacySecondaryAvailable: secondaryRecogniser?.isAvailable ?? false,
            legacySecondaryOnDevice: secondaryRecogniser?.supportsOnDeviceRecognition ?? false,
            legacyPrimaryOnDevice: primaryRecogniser?.supportsOnDeviceRecognition ?? false,
            tier: tier
        )
    }

    /// Script first, identifier second. A locale can carry the script tag
    /// explicitly, and hi-Latn is Hindi in Latin script, which is not what the
    /// secondary pass is for.
    static func isDevanagari(_ locale: Locale) -> Bool {
        if let script = locale.language.script?.identifier { return script == "Deva" }
        guard let code = locale.language.languageCode?.identifier else { return false }
        return ["hi", "mr", "ne", "sa", "kok", "mai"].contains(code)
    }
}
