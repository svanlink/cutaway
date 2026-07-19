import XCTest
import SwiftUI
@testable import Cutaway

/// Renders the menu-bar pill in all three traffic-light states at 2x —
/// proof the states render distinctly, and the source of the close-ups the
/// design gate judges. Files land in tmp/cutaway-pill-renders/.
@MainActor
final class PillRenderTests: XCTestCase {

    private func render(_ pill: PillBody, to name: String) throws -> URL {
        let renderer = ImageRenderer(content: pill.background(Color.black).padding(0))
        renderer.scale = 4  // menu-bar pill is tiny — 4x for judgeable close-ups
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cutaway-pill-renders")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        guard let cg = renderer.cgImage else { throw XCTSkip("no CG image") }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testAllThreeStatesRenderDistinctly() throws {
        let states: [(String, PillBody)] = [
            ("pill-green.png", PillBody(stateColor: DT.green, isRecording: true, showsPauseGlyph: false,
                                        goalFraction: 0.57, goalReached: false, seconds: 16572)),
            ("pill-amber.png", PillBody(stateColor: DT.amber, isRecording: false, showsPauseGlyph: true,
                                        goalFraction: 0.57, goalReached: false, seconds: 16572)),
            ("pill-red.png", PillBody(stateColor: DT.red, isRecording: false, showsPauseGlyph: false,
                                      goalFraction: 0, goalReached: false, seconds: 0)),
        ]
        var pixels: Set<Int> = []
        for (name, pill) in states {
            let url = try render(pill, to: name)
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 1000, "\(name) must be a real render")
            pixels.insert(data.count)
        }
        XCTAssertEqual(pixels.count, 3, "three states must not render identically")
    }
}
