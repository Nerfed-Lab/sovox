import SwiftUI

/// The single colour token file. No hardcoded hex may appear anywhere else.
///
/// Tokens resolve per trait collection, so light and dark come from one
/// declaration and the Live Activity, which renders outside the app's own
/// environment, still picks up the right side.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

private func token(dark: UInt32, light: UInt32) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
    })
}

enum SovoxPalette {
    static let bg            = token(dark: 0x0E0E11, light: 0xFAFAFA)
    static let surface       = token(dark: 0x1A1A1F, light: 0xFFFFFF)
    static let surfaceRaised = token(dark: 0x232329, light: 0xF2F2F5)
    static let textPrimary   = token(dark: 0xF5F5F7, light: 0x16161A)
    static let textSecondary = token(dark: 0x9A9AA3, light: 0x6B6B75)
    static let separator     = token(dark: 0x2C2C33, light: 0xE3E3E8)
    static let accent        = token(dark: 0x5E6AD2, light: 0x4B57C4)
    static let recordRed     = token(dark: 0xFF3B30, light: 0xE5342A)
    static let pauseAmber    = token(dark: 0xFFB020, light: 0xC97A00)
    static let destructive   = token(dark: 0xFF453A, light: 0xD70015)

    /// Highlight on the record button's fill. Declared here so no view carries
    /// its own hex.
    static let recordHighlight = token(dark: 0xFF7062, light: 0xFF5B4C)

    /// Names the rest of the app already uses. Red is now reserved for the
    /// record button, the REC dot, Stop, and destructive actions. Everything
    /// that used to be red and is not one of those now resolves to accent.
    static let recording = recordRed
    static let paused    = pauseAmber
    static let ok        = accent
    static let ink       = textPrimary
    static let dim       = textSecondary
}

/// Flat ground. The red radial gradient is gone: it tinted every screen and made
/// the whole app read as an emergency alert.
struct SovoxBackdrop: View {
    var accent: Color = SovoxPalette.accent
    var active: Bool = false

    var body: some View {
        SovoxPalette.bg.ignoresSafeArea()
    }
}
