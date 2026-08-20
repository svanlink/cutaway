import XCTest
import AppKit
@testable import Cutaway

/// The status item is the one surface that is NOT inside a window forced to
/// dark. It sits on the system menu bar, which follows the user's appearance
/// setting — so the app's fixed light-on-dark tokens rendered near-white text
/// on a light menu bar at 1.13:1. The number the whole app exists to show was
/// invisible to everyone running Light mode, disabled or not.
final class MenuBarContrastTests: XCTestCase {

    /// Approximate menu-bar backgrounds. The real bar is translucent over the
    /// wallpaper, so these are the light and dark ends of what it can be.
    private let lightBar = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)
    private let darkBar = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)

    private func linear(_ c: CGFloat) -> Double {
        let c = Double(c)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * linear(c.redComponent)
             + 0.7152 * linear(c.greenComponent)
             + 0.0722 * linear(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Resolve a dynamic color the way it will actually render.
    private func resolved(_ color: NSColor, dark: Bool) -> NSColor {
        var out = color
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.sRGB) ?? color
        }
        return out
    }

    func testPillTextIsLegibleInBothAppearances() {
        for (dark, bar, name) in [(false, lightBar, "light"), (true, darkBar, "dark")] {
            let primary = resolved(.labelColor, dark: dark)
            XCTAssertGreaterThanOrEqual(contrast(primary, bar), 4.5,
                "pill time readout is unreadable on a \(name) menu bar")
            let secondary = resolved(.secondaryLabelColor, dark: dark)
            XCTAssertGreaterThanOrEqual(contrast(secondary, bar), 4.5,
                "paused readout is unreadable on a \(name) menu bar")
        }
    }

    /// The traffic-light border is the only thing carrying state at a glance.
    func testStateColoursMeetNonTextContrastInBothAppearances() {
        let states: [(NSColor, String)] = [(NSColor(DT.barGreen), "recording"),
                                           (NSColor(DT.barAmber), "paused"),
                                           (NSColor(DT.barRed), "no project")]
        for (dark, bar, name) in [(false, lightBar, "light"), (true, darkBar, "dark")] {
            for (color, state) in states {
                XCTAssertGreaterThanOrEqual(contrast(resolved(color, dark: dark), bar), 3.0,
                    "\(state) state indicator fails on a \(name) menu bar")
            }
        }
    }

    /// The regression itself: the in-app dark tokens must never come back to
    /// the menu bar. They are correct in a window and wrong on the bar.
    func testTheOldFixedTokensWouldStillFail() {
        let fixedText = NSColor(srgbRed: 245/255, green: 245/255, blue: 247/255, alpha: 1)
        XCTAssertLessThan(contrast(fixedText, lightBar), 4.5,
            "if this ever passes, the assumption behind DT.barText is wrong")
    }
}
