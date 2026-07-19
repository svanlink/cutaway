import XCTest
@testable import Cutaway

/// WCAG 2.x relative-luminance contrast, computed from the DT raw tokens.
/// Secondary text is composited (alpha over surface) exactly as rendered.
final class ContrastTests: XCTestCase {

    private func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    private func blend(_ top: (r: Double, g: Double, b: Double), alpha: Double,
                       over bg: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        (alpha * top.r + (1 - alpha) * bg.r,
         alpha * top.g + (1 - alpha) * bg.g,
         alpha * top.b + (1 - alpha) * bg.b)
    }

    private func contrast(alpha: Double, over bg: (r: Double, g: Double, b: Double)) -> Double {
        let l1 = luminance(blend(DT.baseTextRGB, alpha: alpha, over: bg))
        let l2 = luminance(bg)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testSecondaryTextMeetsAAOnCard() {
        XCTAssertGreaterThanOrEqual(contrast(alpha: DT.text3Alpha, over: DT.cardRGB), 4.5,
                                    "settings subtitles must meet WCAG AA on cards")
        XCTAssertGreaterThanOrEqual(contrast(alpha: DT.text2Alpha, over: DT.cardRGB), 4.5)
    }

    func testSecondaryTextMeetsAAOnWindow() {
        XCTAssertGreaterThanOrEqual(contrast(alpha: DT.text3Alpha, over: DT.windowRGB), 4.5,
                                    "section headers must meet WCAG AA on the window")
    }

    func testTextHierarchyPreserved() {
        XCTAssertGreaterThan(DT.text2Alpha, DT.text3Alpha,
                             "contrast lift must not flatten the text ladder")
    }
}
