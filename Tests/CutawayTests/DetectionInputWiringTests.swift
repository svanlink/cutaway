import XCTest
@testable import Cutaway

/// Every field the state machine reads must be filled by the engine.
///
/// Three separate rules have now shipped written-but-unwired:
/// `freshProjectName()` had zero callers, `DetectionFollower` is
/// instantiated and bypassed, and `anchorAppRunning` — the whole of
/// "closing Resolve stops the clock" — was never assigned in `tick()`, so
/// it kept the permissive `true` it defaults to and the requirement was
/// inert from the day it was written. Each was found by a human noticing
/// wrong behaviour, months apart. None was found by a test, because the
/// tests all construct `DetectionInput` themselves and set what they mean.
///
/// So this asserts the WIRING, generically: every settable field on
/// `DetectionInput` is assigned somewhere in `DetectionEngine`. It checks
/// the pattern, not the three names that have already bitten us — a guard
/// pinned to yesterday's offender only proves yesterday cannot recur.
final class DetectionInputWiringTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testEveryDetectionInputFieldIsFilledByTheEngine() throws {
        let state = try source("Sources/Cutaway/Detection/DetectionState.swift")
        let engine = try source("Sources/Cutaway/Detection/DetectionEngine.swift")

        // The fields of `struct DetectionInput`, in declaration order.
        guard let structRange = state.range(of: "struct DetectionInput: Sendable {"),
              let end = state.range(of: "\n}", range: structRange.upperBound..<state.endIndex)
        else { return XCTFail("could not find DetectionInput") }
        let body = String(state[structRange.upperBound..<end.lowerBound])

        var fields: [String] = []
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("var "), trimmed.contains(":") else { continue }
            // Computed properties are derived, not filled.
            guard !trimmed.contains("{") else { continue }
            let name = trimmed.dropFirst(4).prefix { $0 != ":" && $0 != " " }
            fields.append(String(name))
        }
        XCTAssertGreaterThan(fields.count, 8, "the field scan found nothing — the struct moved")

        // A field is filled either by the initialiser call or by assignment.
        let unfilled = fields.filter { field in
            !engine.contains("input.\(field) =") && !engine.contains("\(field):")
        }
        XCTAssertEqual(unfilled, [], """
            DetectionEngine never fills these DetectionInput fields, so they keep \
            their defaults forever and any rule that reads them is inert:
            \(unfilled.joined(separator: ", "))
            """)
    }
}
