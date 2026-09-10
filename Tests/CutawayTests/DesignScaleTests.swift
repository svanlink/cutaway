import XCTest
import SwiftUI
@testable import Cutaway

/// The scales stay scales.
///
/// Before 2026-09-09 the app used sixteen distinct font sizes — three of
/// them fractional — and thirteen distinct spacing values, most off the
/// grid. That is the whole of "too busy": hierarchy is carried by consistent
/// difference, and when 12 and 12.5 both exist neither says anything, so the
/// eye reads a panel as one undifferentiated mass rather than as groups.
///
/// These tests fail when a new size or gap is invented instead of chosen.
final class DesignScaleTests: XCTestCase {

    private func tokens() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Cutaway/Design/DesignTokens.swift"),
                          encoding: .utf8)
    }

    /// Every app font comes off the ladder, by name. A raw number here is a
    /// new step nobody decided to add.
    func testEveryFontSizeComesFromTheLadder() throws {
        let source = try tokens()
        // The invoice page and the QR-bill have their own scales on purpose:
        // one is a printed A4 document typeset in points on paper, the other
        // has its sizes fixed by the payment scheme. Neither is app chrome,
        // and neither should be dragged onto a screen ladder.
        let appSection = String(source[..<(source.range(of: "enum Page {")?.lowerBound ?? source.endIndex)])
        var offenders: [String] = []
        for line in appSection.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("Font.system(size:") else { continue }
            if line.contains("size: Step.") { continue }
            offenders.append(line.trimmingCharacters(in: .whitespaces))
        }
        XCTAssertEqual(offenders, [], """
            These fonts use a raw size instead of a Step. Pick the nearest \
            step, or argue for a new one in the ladder — do not add a size \
            in passing.
            """)
    }

    /// Eight steps, every one a size macOS itself uses, none fractional.
    func testTheLadderIsWholeNumbersAndStaysSmall() {
        let ladder: [CGFloat] = [DT.Step.display, DT.Step.xl, DT.Step.l, DT.Step.m,
                                 DT.Step.base, DT.Step.s, DT.Step.xs, DT.Step.xxs]
        XCTAssertEqual(Set(ladder).count, ladder.count, "two steps of the same size is one step")
        for size in ladder {
            XCTAssertEqual(size, size.rounded(),
                           "\(size) is fractional — the tell of a size nudged until it fit")
        }
        XCTAssertLessThanOrEqual(ladder.count, 8, "a scale a person can hold in their head")
        // Descending, with real distance between neighbours: two steps four
        // percent apart are one step with extra bookkeeping.
        for (big, small) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThan(big, small, "the ladder must descend")
            XCTAssertGreaterThanOrEqual(big / small, 1.07, "\(big) and \(small) are the same step")
        }
    }

    /// The ratio that makes grouping legible without drawing a single line.
    func testGroupsAreSeparatedByMoreThanTheirContents() {
        XCTAssertGreaterThanOrEqual(DT.between / DT.within, 2.0,
                                    "a group reads as a group because the gap around it is much "
                                  + "larger than the gap inside it — 2 vs 3 points reads as neither")
        XCTAssertEqual(DT.margin, 20, "HIG: 20pt window margins")
    }

    /// Gaps in app chrome come from the scale, not from a number typed at
    /// the call site.
    ///
    /// The type ladder is enforced in one file because every font already
    /// lives there. Spacing is not: it is written wherever a stack is, which
    /// is how thirteen different values accumulated. This scans the views.
    ///
    /// The printed invoice is excluded, and on principle rather than for
    /// convenience: it is typeset in millimetres for A4 by a payment scheme
    /// that fixes its measurements, so a screen grid has no authority there.
    func testAppChromeSpacesItselfFromTheScale() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Cutaway")
        let printed = ["PaymentPartView.swift", "InvoiceDocumentView.swift", "SwissQRCode.swift"]
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !printed.contains($0.lastPathComponent) }) ?? []
        XCTAssertGreaterThan(files.count, 30, "the source tree was not found")

        // What is flagged is a gap OFF the 4pt rhythm. A literal 8 where
        // DT.within would do produces identical pixels — that is tidiness,
        // and worth doing, but it is not what made the app look busy. A 3, a
        // 5, a 7, a 9 is a gap that belongs to no scale, and enough of those
        // is why nothing read as grouped.
        //
        // `spacing: 0` is "no gap", which is a decision, not a measurement.
        let offender = try NSRegularExpression(
            pattern: #"(spacing: [1-9][0-9]*\)|padding\(\.[a-zA-Z]+, [1-9][0-9]*\)|padding\([1-9][0-9]*\))"#)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") {
                let s = String(line)
                let range = NSRange(s.startIndex..., in: s)
                guard let match = offender.firstMatch(in: s, range: range),
                      let hit = Range(match.range, in: s) else { continue }
                let digits = s[hit].filter(\.isNumber)
                guard let value = Int(digits), value % 4 != 0 else { continue }
                found.append("\(file.lastPathComponent): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(found, [], """
            These gaps are typed numbers rather than steps on the scale. Use             DT.s1 (inside a unit), DT.within (inside a group), DT.between or             DT.margin (around one) — or argue for a new step.
            \(found.joined(separator: "\n"))
            """)
    }

    /// Everything on the 4pt grid, which is what keeps unrelated views in
    /// the same rhythm.
    func testTheSpacingScaleIsOnTheGrid() {
        for step in [DT.s1, DT.s2, DT.s3, DT.s4, DT.s5, DT.s6, DT.within, DT.between,
                     DT.margin, DT.rowInset] {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: 4), 0, "\(step) is off the 4pt grid")
        }
    }
}
