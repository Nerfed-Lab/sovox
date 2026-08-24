import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var fullName: String { didSet { defaults.set(fullName, forKey: Keys.fullName) } }
    var workEmail: String { didSet { defaults.set(workEmail, forKey: Keys.workEmail) } }
    var destination: AIDestination { didSet { defaults.set(destination.rawValue, forKey: Keys.destination) } }
    var segmentMinutes: Int { didSet { defaults.set(segmentMinutes, forKey: Keys.segmentMinutes) } }
    var announceConsent: Bool { didSet { defaults.set(announceConsent, forKey: Keys.announceConsent) } }
    var sessionsStarted: Int { didSet { defaults.set(sessionsStarted, forKey: Keys.sessionsStarted) } }
    var customActions: [CustomAction] { didSet { persistCustomActions() } }
    var transcriptionLocale: String {
        didSet {
            defaults.set(transcriptionLocale, forKey: Keys.transcriptionLocale)
            // 19b. The two languages cannot be the same, and picking a
            // duplicate clears the other rather than silently transcribing the
            // same audio twice with one model.
            if TranscriptionLocale.normalise(secondaryLocale) == TranscriptionLocale.normalise(transcriptionLocale) {
                secondaryLocale = ""
            }
        }
    }
    /// Phase 19b. Empty means none chosen.
    var secondaryLocale: String {
        didSet {
            defaults.set(secondaryLocale, forKey: Keys.secondaryLocale)
            if TranscriptionLocale.normalise(secondaryLocale) == TranscriptionLocale.normalise(transcriptionLocale) {
                transcriptionLocale = TranscriptionLocale.defaultIdentifier
            }
        }
    }
    var dualLanguage: Bool { didSet { defaults.set(dualLanguage, forKey: Keys.dualLanguage) } }
    var verifiedBridges: Set<String> { didSet { defaults.set(Array(verifiedBridges), forKey: Keys.verifiedBridges) } }
    var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: Keys.setupCompleted) } }
    /// Phase 15h. True once, for a user who set up a bridge under the old
    /// names, until they dismiss the card explaining the three edits.
    var bridgeMigrationPending: Bool {
        didSet { defaults.set(bridgeMigrationPending, forKey: Keys.bridgeMigrationPending) }
    }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var defaultOutputs: Set<OutputMode> {
        didSet { defaults.set(defaultOutputs.map(\.rawValue), forKey: Keys.defaultOutputs) }
    }

    enum Keys {
        static let fullName = "sovox.fullName"
        static let workEmail = "sovox.workEmail"
        static let destination = "sovox.destination"
        static let segmentMinutes = "sovox.segmentMinutes"
        static let announceConsent = "sovox.announceConsent"
        static let sessionsStarted = "sovox.sessionsStarted"
        static let defaultOutputs = "sovox.defaultOutputs"
        static let appearance = "sovox.appearance"
        static let customActions = "sovox.customActions"
        static let verifiedBridges = "sovox.verifiedBridges"
        static let setupCompleted = "sovox.setupCompleted"
        static let bridgeMigrationPending = "sovox.bridgeMigrationPending"
        static let bridgeNamesV15 = "sovox.bridgeNamesV15"
        static let transcriptionLocale = "sovox.transcriptionLocale"
        static let secondaryLocale = "sovox.secondaryLocale"
        static let dualLanguage = "sovox.dualLanguage"
    }

    static let segmentOptions = [15, 30, 60]

    /// The rename moved every key from the capture. prefix to sovox. Because the
    /// bundle identifier did not change, the container survived the update, so
    /// the old values are still sitting there. Copying them once keeps a user's
    /// name, work email and preferences across the rename instead of silently
    /// resetting them. Runs at most once.
    private static func migrateLegacyKeys(_ defaults: UserDefaults) {
        let migrationFlag = "sovox.migratedFromCapture"
        guard !defaults.bool(forKey: migrationFlag) else { return }
        for key in [Keys.fullName, Keys.workEmail, Keys.destination, Keys.segmentMinutes,
                    Keys.announceConsent, Keys.sessionsStarted, Keys.defaultOutputs] {
            let legacy = key.replacingOccurrences(of: "sovox.", with: "capture.")
            guard defaults.object(forKey: key) == nil,
                  let value = defaults.object(forKey: legacy) else { continue }
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationFlag)
    }

    /// Phase 15a renamed both bridge Shortcuts, so any earlier verification
    /// proves nothing: it was a round trip through a name that no longer
    /// exists. Clear it and raise the migration card once, for users who had
    /// actually got that far. A fresh install has nothing to migrate and is
    /// left alone.
    @discardableResult
    static func migrateBridgeNames(_ defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: Keys.bridgeNamesV15) else { return false }
        defaults.set(true, forKey: Keys.bridgeNamesV15)
        let hadOldSetup = defaults.bool(forKey: Keys.setupCompleted)
            || !(defaults.stringArray(forKey: Keys.verifiedBridges) ?? []).isEmpty
        guard hadOldSetup else { return false }
        defaults.set([String](), forKey: Keys.verifiedBridges)
        defaults.set(true, forKey: Keys.bridgeMigrationPending)
        return true
    }

    private init() {
        AppSettings.migrateLegacyKeys(defaults)
        _ = AppSettings.migrateBridgeNames(defaults)
        fullName = defaults.string(forKey: Keys.fullName) ?? ""
        workEmail = defaults.string(forKey: Keys.workEmail) ?? ""
        destination = AIDestination(rawValue: defaults.string(forKey: Keys.destination) ?? "") ?? .chatgpt
        let stored = defaults.integer(forKey: Keys.segmentMinutes)
        segmentMinutes = AppSettings.segmentOptions.contains(stored) ? stored : 30
        announceConsent = defaults.object(forKey: Keys.announceConsent) as? Bool ?? false
        sessionsStarted = defaults.integer(forKey: Keys.sessionsStarted)
        if let data = defaults.data(forKey: Keys.customActions),
           let decoded = try? JSONDecoder().decode([CustomAction].self, from: data) {
            customActions = decoded
        } else {
            customActions = []
        }
        transcriptionLocale = defaults.string(forKey: Keys.transcriptionLocale) ?? TranscriptionLocale.defaultIdentifier
        secondaryLocale = defaults.string(forKey: Keys.secondaryLocale) ?? AppSettings.defaultSecondaryLocale
        // Defaults on where the device can actually do it, off where it cannot.
        dualLanguage = defaults.object(forKey: Keys.dualLanguage) as? Bool
            ?? (TranscriptionLocale.availability(AppSettings.defaultSecondaryLocale) == .ready)
        verifiedBridges = Set(defaults.stringArray(forKey: Keys.verifiedBridges) ?? [])
        setupCompleted = defaults.bool(forKey: Keys.setupCompleted)
        bridgeMigrationPending = defaults.bool(forKey: Keys.bridgeMigrationPending)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .dark
        let raw = defaults.stringArray(forKey: Keys.defaultOutputs) ?? [OutputMode.actionsAndDecisions.rawValue]
        let parsed = Set(raw.compactMap(OutputMode.init(rawValue:)))
        defaultOutputs = parsed.isEmpty ? [.actionsAndDecisions] : parsed
    }

    private func persistCustomActions() {
        guard let data = try? JSONEncoder().encode(customActions) else { return }
        defaults.set(data, forKey: Keys.customActions)
    }

    /// Ticked on the Transcript Ready screen without the user asking.
    var defaultCustomActionIDs: Set<UUID> {
        Set(customActions.filter(\.includeByDefault).map(\.id))
    }

    static let defaultSecondaryLocale = "hi_IN"

    /// The secondary language a job should actually use, or nil.
    ///
    /// Nil whenever the feature is off, nothing is chosen, or the chosen
    /// language cannot run without a network. The last one matters: an online
    /// only secondary would produce nothing on every segment and the merge
    /// would silently become a single reading.
    var activeSecondaryLocale: String? {
        guard dualLanguage else { return nil }
        let wanted = TranscriptionLocale.normalise(secondaryLocale)
        guard !wanted.isEmpty,
              wanted != TranscriptionLocale.normalise(transcriptionLocale),
              TranscriptionLocale.availability(wanted) == .ready else { return nil }
        return wanted
    }

    func isBridgeVerified(_ destination: AIDestination) -> Bool {
        verifiedBridges.contains(destination.rawValue)
    }

    func markBridgeVerified(_ destination: AIDestination) {
        verifiedBridges.insert(destination.rawValue)
    }

    /// The Record tab warns while the destination actually in use is unverified.
    var needsBridgeSetup: Bool {
        !isBridgeVerified(destination)
    }

    var canAddCustomAction: Bool {
        customActions.count < CustomActionSanitiser.maxActions
    }

    var segmentSeconds: TimeInterval { TimeInterval(segmentMinutes * 60) }

    /// The reassurance line under the recording hero is shown for the first
    /// three sessions and then retires itself.
    var showsBackgroundHint: Bool { sessionsStarted <= 3 }
}
