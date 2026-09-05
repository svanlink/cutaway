import XCTest
import SwiftUI
import AppKit
@testable import Cutaway

/// WCAG contrast, computed from the tokens as they actually render.
///
/// The old version asserted alpha-composited text against two surfaces and
/// only ever checked a floor — which is how `text2` drifted from 0.55 to
/// 0.62 alpha and ended up 6 L* from `text3`, two names for one colour, with
/// nothing failing. This version checks every pair the app actually uses,
/// and asserts the ladder has real gaps rather than merely clearing a bar.
final class ContrastTests: XCTestCase {

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }

    private func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ color: Color) -> Double {
        let c = components(color)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ fg: Color, on bg: Color) -> Double {
        let l1 = luminance(fg), l2 = luminance(bg)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Perceptual lightness — the axis a reader actually experiences.
    private func lStar(_ color: Color) -> Double {
        let y = luminance(color)
        return y > 0.008856 ? 116 * pow(y, 1.0 / 3) - 16 : 903.3 * y
    }

    // MARK: - Text

    func testEveryTextLevelMeetsAAOnEverySurfaceItIsUsedOn() {
        let surfaces: [(Color, String)] = [(DT.base, "base"), (DT.raised, "raised")]
        for (surface, name) in surfaces {
            for (fg, label) in [(DT.textPrimary, "primary"), (DT.textSecondary, "secondary"),
                                (DT.textTertiary, "tertiary"), (DT.money, "money")] {
                XCTAssertGreaterThanOrEqual(contrast(fg, on: surface), 4.5,
                                            "\(label) text on \(name)")
            }
        }
    }

    /// Tertiary clears AA on base and raised but lands at 4.13 on overlay.
    /// The rule is that it is not legal there — this pins the rule so a
    /// future edit cannot quietly start using it on popovers.
    func testTertiaryTextIsNotUsableOnTheOverlaySurface() {
        XCTAssertLessThan(contrast(DT.textTertiary, on: DT.overlay), 4.5,
                          "if this passes, tertiary became legal on overlay — update the rule")
        XCTAssertGreaterThanOrEqual(contrast(DT.textSecondary, on: DT.overlay), 4.5,
                                    "secondary is what overlay surfaces must step up to")
    }

    /// The defect that started this: a ladder whose lower two rungs were the
    /// same rung. A gap under 10 L* is not a level, it is a rounding error.
    func testTheTextLadderHasPerceptibleGaps() {
        let primary = lStar(DT.textPrimary)
        let secondary = lStar(DT.textSecondary)
        let tertiary = lStar(DT.textTertiary)
        XCTAssertGreaterThan(primary - secondary, 10, "primary and secondary must differ")
        XCTAssertGreaterThan(secondary - tertiary, 10,
                             "secondary and tertiary were 6 L* apart — one colour, two names")
    }

    // MARK: - Surfaces

    /// Elevation used to span L* 3.7–12.4, with card-on-window at 1.085:1 —
    /// invisible in a dark room, which is where this app lives.
    func testTheSurfaceRampIsPerceptibleStepByStep() {
        let ramp: [(Color, String)] = [(DT.sunken, "sunken"), (DT.base, "base"),
                                       (DT.raised, "raised"), (DT.overlay, "overlay"),
                                       (DT.float, "float")]
        for (lower, upper) in zip(ramp, ramp.dropFirst()) {
            let step = lStar(upper.0) - lStar(lower.0)
            XCTAssertGreaterThan(step, 4, "\(lower.1) → \(upper.1) is not a visible step")
        }
    }

    /// It also has to share a register with Resolve's own panels (L* 17–20),
    /// or the app reads as a void on the same desk.
    func testTheAppSitsInTheSameLightnessRegisterAsResolve() {
        XCTAssertGreaterThan(lStar(DT.raised), 12, "cards must not sit at near-black")
        XCTAssertGreaterThan(lStar(DT.overlay), 17, "popovers should meet Resolve's panel range")
    }

    // MARK: - Non-text (WCAG 1.4.11)

    func testStateAndSignalColoursMeetNonTextContrast() {
        for (color, label) in [(DT.signal, "signal"), (DT.recording, "recording"),
                               (DT.held, "held"), (DT.alarm, "alarm"), (DT.idle, "idle")] {
            XCTAssertGreaterThanOrEqual(contrast(color, on: DT.base), 3.0,
                                        "\(label) is a status indicator on base")
        }
    }

    func testTextOnTheSignalColourIsLegible() {
        XCTAssertGreaterThanOrEqual(contrast(DT.onSignal, on: DT.signal), 4.5,
                                    "the primary button's own label")
    }

    // MARK: - Semantics

    /// Money is never an accent — and the honest test of that is CHROMA, not
    /// lightness. A currency figure must be a neutral: colouring it implies a
    /// judgement about the number that the app is not entitled to make.
    private func chroma(_ color: Color) -> Double {
        let c = components(color)
        return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))
    }

    func testMoneyIsNeutralAndSignalIsNot() {
        XCTAssertLessThan(chroma(DT.money), 0.06,
                          "currency must read as a neutral, not as an accent")
        XCTAssertGreaterThan(chroma(DT.signal), 0.4,
                             "the accent must be unmistakably chromatic")
        for (fg, label) in [(DT.textPrimary, "primary"), (DT.textSecondary, "secondary"),
                            (DT.textTertiary, "tertiary")] {
            XCTAssertLessThan(chroma(fg), 0.06, "\(label) text must be neutral too")
        }
    }
}
