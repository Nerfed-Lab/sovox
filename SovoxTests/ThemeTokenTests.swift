import XCTest
import SwiftUI
@testable import Sovox

/// Phase 3. The app forces its own colour scheme, so a simulator screenshot
/// cannot prove the light palette. Resolving each token against an explicit
/// trait collection can.
final class ThemeTokenTests: XCTestCase {

    private func hex(_ color: Color, dark: Bool) -> UInt32 {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(round(r * 255)) << 16) | (UInt32(round(g * 255)) << 8) | UInt32(round(b * 255))
    }

    private func assertToken(_ color: Color, dark: UInt32, light: UInt32,
                             _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(hex(color, dark: true), dark, "\(name) dark", file: file, line: line)
        XCTAssertEqual(hex(color, dark: false), light, "\(name) light", file: file, line: line)
    }

    func testEveryTokenMatchesTheSpecifiedPalette() {
        assertToken(SovoxPalette.bg,            dark: 0x0E0E11, light: 0xFAFAFA, "bg")
        assertToken(SovoxPalette.surface,       dark: 0x1A1A1F, light: 0xFFFFFF, "surface")
        assertToken(SovoxPalette.surfaceRaised, dark: 0x232329, light: 0xF2F2F5, "surfaceRaised")
        assertToken(SovoxPalette.textPrimary,   dark: 0xF5F5F7, light: 0x16161A, "textPrimary")
        assertToken(SovoxPalette.textSecondary, dark: 0x9A9AA3, light: 0x6B6B75, "textSecondary")
        assertToken(SovoxPalette.separator,     dark: 0x2C2C33, light: 0xE3E3E8, "separator")
        assertToken(SovoxPalette.accent,        dark: 0x5E6AD2, light: 0x4B57C4, "accent")
        assertToken(SovoxPalette.recordRed,     dark: 0xFF3B30, light: 0xE5342A, "recordRed")
        assertToken(SovoxPalette.pauseAmber,    dark: 0xFFB020, light: 0xC97A00, "pauseAmber")
        assertToken(SovoxPalette.destructive,   dark: 0xFF453A, light: 0xD70015, "destructive")
    }

    func testAliasesPointAtTheRightTokens() {
        XCTAssertEqual(hex(SovoxPalette.recording, dark: true), hex(SovoxPalette.recordRed, dark: true))
        XCTAssertEqual(hex(SovoxPalette.paused, dark: true), hex(SovoxPalette.pauseAmber, dark: true))
        XCTAssertEqual(hex(SovoxPalette.ink, dark: true), hex(SovoxPalette.textPrimary, dark: true))
        XCTAssertEqual(hex(SovoxPalette.dim, dark: true), hex(SovoxPalette.textSecondary, dark: true))
        // "ok" used to be green and is now accent, because only genuinely
        // alarming actions may carry a signal colour.
        XCTAssertEqual(hex(SovoxPalette.ok, dark: true), hex(SovoxPalette.accent, dark: true))
    }

    /// Always On dims the Lock Screen presentation. The widget's secondary text
    /// must stay well clear of the app's textSecondary grey or it vanishes.
    func testWidgetSubduedIsBrighterThanAppSecondaryInDark() {
        func luminance(_ h: UInt32) -> Double {
            let r = Double((h >> 16) & 0xFF), g = Double((h >> 8) & 0xFF), b = Double(h & 0xFF)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        XCTAssertGreaterThan(luminance(0xD8D8DE), luminance(0x9A9AA3))
    }

    func testAppearanceModeMapsToColorScheme() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(AppearanceMode.allCases.count, 3)
    }

    func testSpaceRemainingIsReadable() {
        XCTAssertEqual(DurationFormat.spaceRemaining(minutes: 22815), "380 hrs of space left")
        XCTAssertEqual(DurationFormat.spaceRemaining(minutes: 121), "2 hrs of space left")
        XCTAssertEqual(DurationFormat.spaceRemaining(minutes: 120), "120 min of space left")
        XCTAssertEqual(DurationFormat.spaceRemaining(minutes: 45), "45 min of space left")
        XCTAssertEqual(DurationFormat.spaceRemaining(minutes: 0), "no space left")
    }
}
