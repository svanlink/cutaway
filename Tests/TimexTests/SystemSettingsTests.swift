import XCTest
import SwiftUI
import AppKit
@testable import Cutaway

/// Before this, the app read no system accessibility setting at all — grep
/// found zero occurrences of Reduce Motion, Increase Contrast, Reduce
/// Transparency or Differentiate Without Color anywhere in the source. Every
/// control is `.buttonStyle(.plain)` with hand-drawn chrome, so a hairline at
/// 1.2:1 stayed at 1.2:1 no matter what the user asked the OS for.
final class SystemSettingsTests: XCTestCase {

    /// What the tokens are worth in each state. The alphas are asserted here
    /// and the mapping is a pure function; what cannot be asserted is whether
    /// AppKit hands the colour provider a high-contrast appearance, because
    /// `NSAppearance(named: .accessibilityHighContrastDarkAqua)` does not
    /// report that name back unless the system setting is genuinely on. That
    /// half is a manual check — docs/ACCESSIBILITY-MANUAL.md, section 5.
    func testBordersStrengthenUnderIncreaseContrast() {
        for (alphas, label) in [(DT.strokeSubtleAlphas, "strokeSubtle"),
                                (DT.strokeWindowAlphas, "strokeWindow"),
                                (DT.ringTrackAlphas, "ringTrack"),
                                (DT.ringPausedAlphas, "ringPaused")] {
            let normal = DT.contrastAlpha(normal: alphas.normal,
                                          increased: alphas.increased, highContrast: false)
            let increased = DT.contrastAlpha(normal: alphas.normal,
                                             increased: alphas.increased, highContrast: true)
            XCTAssertEqual(normal, alphas.normal)
            XCTAssertGreaterThan(increased, normal, "\(label) ignores Increase Contrast")
            XCTAssertGreaterThan(increased / normal, 1.5,
                                 "\(label) barely moves — the user asked for a visible change")
        }
    }

    /// The paused ring is a status indicator: WCAG 1.4.11 wants 3:1 even
    /// without any accessibility setting turned on. It measured 1.94:1.
    func testThePausedRingMeetsNonTextContrastNormally() {
        XCTAssertGreaterThanOrEqual(DT.ringPausedAlphas.normal, 0.28,
                                    "a status indicator that faint is not an indicator")
    }

    /// Guard against the settings being read once and then quietly dropped in
    /// a later edit — this is the check the audit said nothing automated
    /// would ever do for this class of defect.
    func testTheAppStillReadsTheSystemSettings() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let ui = root.appendingPathComponent("Sources/Timex/UI")
        let sources = try FileManager.default
            .contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()

        for setting in ["accessibilityReduceMotion",
                        "accessibilityReduceTransparency",
                        "accessibilityDisplayShouldReduceMotion"] {
            XCTAssertTrue(sources.contains(setting), "nothing reads \(setting) any more")
        }
    }
}
