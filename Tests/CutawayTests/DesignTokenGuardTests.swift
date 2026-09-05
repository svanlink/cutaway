import XCTest
@testable import Cutaway

/// The rule "no hardcoded font sizes outside DesignTokens" — now checked over
/// the WHOLE source tree, not one folder — was honoured by
/// whoever remembered to look. It caught exactly one literal in this run —
/// because someone happened to diff for it — while eighteen others sat in
/// the files. A rule nobody checks is a preference. This checks it.
final class DesignTokenGuardTests: XCTestCase {

    /// Walk up from this test file to the repository root.
    private var uiSources: [URL] {
        get throws {
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<3 { root.deleteLastPathComponent() }   // Tests/CutawayTests/<file>
            let base = root.appendingPathComponent("Sources/Cutaway")
            let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
            return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }

    func testTheGuardIsActuallyLookingAtTheSources() throws {
        let files = try uiSources
        XCTAssertGreaterThan(files.count, 5,
                             "if this test cannot find the sources it proves nothing")
        XCTAssertTrue(files.contains { $0.lastPathComponent == "DesignTokens.swift" })
    }

    func testNoFontSizeLiteralsOutsideDesignTokens() throws {
        var offenders: [String] = []
        for file in try uiSources where file.lastPathComponent != "DesignTokens.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(".system(size:") {
                offenders.append("\(file.lastPathComponent):\(index + 1) —\(line)")
            }
        }
        XCTAssertEqual(offenders, [], """
            Font sizes belong in DesignTokens, named for the role they play.
            Add a token and use it:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The tokens themselves are allowed literals — that is the point of the
    /// file — but they must be reachable, or the rule just moves the problem.
    func testDesignTokensDefinesTheRolesTheUIAsksFor() throws {
        let tokens = try String(contentsOf: uiSources.first { $0.lastPathComponent == "DesignTokens.swift" }!,
                                encoding: .utf8)
        for role in ["pillTime", "pillMessage", "panelHero", "panelProject",
                     "glyphLight", "glyphTiny", "buttonGlyph", "smallBold"] {
            XCTAssertTrue(tokens.contains("static let \(role)"), "missing token: \(role)")
        }
    }
}
