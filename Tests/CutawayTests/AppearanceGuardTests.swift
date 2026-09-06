import XCTest
@testable import Cutaway

/// Dark-only is a documented instrument exception (decision 3), decided
/// ONCE at the app level. Seven per-view forces were the fragile version
/// App Review rejects.
final class AppearanceGuardTests: XCTestCase {
    private func sources() throws -> [(String, String)] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let base = root.appendingPathComponent("Sources/Cutaway")
        return try FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testNoViewForcesItsOwnColorScheme() throws {
        let offenders = try sources().filter { $0.1.contains("preferredColorScheme(") }.map(\.0)
        XCTAssertEqual(offenders, [], "appearance is decided once in AppDelegate")
    }

    func testTheAppDecidesOnceAtLaunch() throws {
        let app = try XCTUnwrap(sources().first { $0.0 == "CutawayApp.swift" }).1
        XCTAssertTrue(app.contains("NSApp.appearance = NSAppearance(named: .darkAqua)"))
    }
}
