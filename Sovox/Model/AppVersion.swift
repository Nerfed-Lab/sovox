import Foundation

/// Read from the bundle rather than written out, so it cannot drift from what
/// was actually built. Hardcoding a version string here is the same mistake
/// that made CFBundleVersion ignore the build setting.
enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// The minor component is the highest build phase completed, so 1.14 means
    /// phases 1 through 14 are in.
    static var display: String { "\(marketing) (\(build))" }

    /// Highest completed phase, parsed from the version rather than tracked
    /// separately so the two cannot disagree.
    static var phase: Int {
        Int(marketing.split(separator: ".").dropFirst().first.map(String.init) ?? "") ?? 0
    }
}
