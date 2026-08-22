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
    var transcriptionLocale: String { didSet { defaults.set(transcriptionLocale, forKey: Keys.transcriptionLocale) } }
    var verifiedBridges: Set<String> { didSet { defaults.set(Array(verifiedBridges), forKey: Keys.verifiedBridges) } }
    var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: Keys.setupCompleted) } }
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
        static let transcriptionLocale = "sovox.transcriptionLocale"
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

    private init() {
        AppSettings.migrateLegacyKeys(defaults)
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
        verifiedBridges = Set(defaults.stringArray(forKey: Keys.verifiedBridges) ?? [])
        setupCompleted = defaults.bool(forKey: Keys.setupCompleted)
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
