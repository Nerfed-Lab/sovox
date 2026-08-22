import SwiftUI

/// Widget side of the token file. The Live Activity renders outside the app's
/// environment, so the tokens resolve per trait collection and follow the same
/// light and dark values.
///
/// Nothing here is thinner than semibold and nothing is low contrast grey,
/// because the Lock Screen presentation has to stay readable in the dimmed
/// Always On state where the system reduces luminance.
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

enum WidgetPalette {
    static let recording = token(dark: 0xFF3B30, light: 0xE5342A)
    static let paused    = token(dark: 0xFFB020, light: 0xC97A00)
    static let accent    = token(dark: 0x5E6AD2, light: 0x4B57C4)
    static let ink       = token(dark: 0xF5F5F7, light: 0x16161A)
    /// Deliberately far brighter than the app's textSecondary. Always On dims
    /// the whole presentation, and a 0x9A9AA3 grey disappears there.
    static let subdued   = token(dark: 0xD8D8DE, light: 0x3A3A42)
}
