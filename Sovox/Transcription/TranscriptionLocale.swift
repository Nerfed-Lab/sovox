import Foundation
import Speech

/// Phase 14a. The list is queried at runtime, never hardcoded, because which
/// locales have an on device asset varies by OS version and by device.
enum TranscriptionLocale {
    /// Default is en-IN, not en-US.
    static let defaultIdentifier = "en_IN"

    static func normalise(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "-", with: "_")
    }

    /// Every locale the recogniser claims to support, sorted by display name.
    static func supported() -> [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { displayName($0) < displayName($1) }
    }

    static func displayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// True when the language model asset is actually installed on this device,
    /// as opposed to merely being a supported language.
    static func isOnDeviceReady(_ identifier: String) -> Bool {
        guard let recogniser = SFSpeechRecognizer(locale: Locale(identifier: normalise(identifier))) else {
            return false
        }
        return recogniser.supportsOnDeviceRecognition
    }

    static func isSupported(_ identifier: String) -> Bool {
        let wanted = normalise(identifier)
        return supported().contains { normalise($0.identifier) == wanted }
    }

    /// Used when a recording carries no stored locale, which is every recording
    /// made before this setting existed.
    static func resolved(_ stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return defaultIdentifier }
        return normalise(stored)
    }

    /// What to try, in order, when the asked for locale has no asset on this
    /// device: the phone's own language, then US English, which is the one
    /// English asset practically every device has.
    static func fallbackChain(for identifier: String) -> [String] {
        var chain = [normalise(identifier)]
        for candidate in [Locale.current.identifier, "en_US"] {
            let normalised = normalise(candidate)
            if !chain.contains(normalised) { chain.append(normalised) }
        }
        return chain
    }

    /// The next locale worth trying when the chosen one produces nothing.
    ///
    /// supportsOnDeviceRecognition can report true for a language whose offline
    /// model is not really there. The request then honours
    /// requiresOnDeviceRecognition, hears nothing, and returns an empty final
    /// result rather than an error, so every recording reads as silence. One
    /// retry on a language known to work turns that from a dead end into a
    /// transcript.
    static func alternate(to identifier: String,
                          isReady: (String) -> Bool = isOnDeviceReady) -> String? {
        let asked = normalise(identifier)
        return fallbackChain(for: asked).dropFirst().first { $0 != asked && isReady($0) }
    }

    /// Three states, per locale, decided at runtime.
    enum Availability: Equatable, Sendable {
        case ready
        case needsInstall
        /// Recognition for this locale wants a network, and this app never uses
        /// one. Offered as a choice it would silently produce nothing.
        case notUsable

        var isSelectable: Bool { self != .notUsable }
    }

    static func availability(_ identifier: String) -> Availability {
        let wanted = normalise(identifier)
        guard let recogniser = SFSpeechRecognizer(locale: Locale(identifier: wanted)) else {
            return .notUsable
        }
        if recogniser.supportsOnDeviceRecognition { return .ready }
        // Present and reachable, but only over the network.
        return recogniser.isAvailable ? .notUsable : .needsInstall
    }

    /// The locale a job should actually run in.
    ///
    /// A supported language is not the same as an installed one. Without this
    /// a device that never downloaded the en_IN asset failed every segment of
    /// every recording permanently, while holding a perfectly good en_US asset
    /// the whole time. The asked for locale is returned unchanged when nothing
    /// is ready, so the error still names what the user chose.
    static func usable(_ stored: String?, isReady: (String) -> Bool = isOnDeviceReady) -> String {
        let asked = resolved(stored)
        return fallbackChain(for: asked).first(where: isReady) ?? asked
    }
}
