import XCTest
import SwiftData
@testable import Cutaway

/// Which apps prove work for the SELECTED project. One pure function, so
/// the gate/replace decision has exactly one home.
final class AnchorSetTests: XCTestCase {

    func testEmptyProjectListMeansTheGlobalList() {
        XCTAssertEqual(AnchorSet.resolve(project: [], global: ["a", "b"]), ["a", "b"])
    }

    func testProjectListReplacesTheGlobalListVerbatim() {
        XCTAssertEqual(AnchorSet.resolve(project: ["com.microsoft.Excel"], global: ["a", "b"]),
                       ["com.microsoft.Excel"], "replace, not extend — that is the whole point")
    }

    func testProjectListIsSanitizedLikeTheSettingsEditor() {
        XCTAssertEqual(AnchorSet.resolve(project: [" com.adobe.Photoshop ", "", "COM.ADOBE.PHOTOSHOP"],
                                         global: ["a"]),
                       ["com.adobe.Photoshop"])
    }

    func testDefaultsIncludeResolve() {
        for id in DetectionInput.resolveBundleIDs {
            XCTAssertTrue(DetectionInput.defaultWorkAppPrefixes.contains(id), id)
        }
        XCTAssertEqual(AnchorSet.globalList(saved: nil), DetectionInput.defaultWorkAppPrefixes)
    }

    func testASavedListFromBeforeGetsResolveBack() {
        let old = ["com.adobe.PremierePro", "com.adobe.Photoshop"]
        let repaired = AnchorSet.globalList(saved: old)
        XCTAssertEqual(repaired, DetectionInput.resolveBundleIDs + old,
                       "a list saved when Resolve was implicit must not stop counting Resolve")
        XCTAssertEqual(AnchorSet.globalList(saved: repaired), repaired, "idempotent")
    }

    func testASavedListThatCoversResolveIsLeftAlone() {
        let mine = ["com.blackmagic-design.DaVinciResolve", "com.microsoft.Excel"]
        XCTAssertEqual(AnchorSet.globalList(saved: mine), mine,
                       "one prefix covers all three Resolve ids; nothing is prepended")
    }

    @MainActor
    func testProjectPersistsItsApps() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly, hourlyRate: 85,
                                        currency: .chf, appBundleIDs: ["com.adobe.InDesign"])
        XCTAssertEqual(try store.projects()[0].appBundleIDs, ["com.adobe.InDesign"])
        let legacy = try store.createProject(name: "Old", client: "", mode: .hourly, hourlyRate: 85, currency: .chf)
        XCTAssertEqual(legacy.appBundleIDs, [], "a project created before the field existed reads as 'global'")
        _ = p
    }

    /// The engine does not know about projects; it bills whatever list it
    /// holds. This pins that a NARROWED list really stops Resolve counting.
    @MainActor
    func testAnExcelOnlyListRecordsInExcelAndNotInResolve() {
        let probes = DetectionEngineTests.FakeProbes()
        let scratch = scratchDefaults()
        let engine = DetectionEngine(probes: probes, defaults: scratch)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { clock }
        engine.workAppPrefixes = AnchorSet.resolve(project: ["com.microsoft.Excel"],
                                                   global: DetectionInput.defaultWorkAppPrefixes)

        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        for _ in 0..<5 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .paused(.notFrontmost), "Resolve is not this project's app")
        XCTAssertEqual(engine.accumulator.activeSeconds, 0)

        probes.frontmost = "com.microsoft.Excel"
        for _ in 0..<5 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .recording)
        XCTAssertGreaterThan(engine.accumulator.activeSeconds, 3)

        // Back to "global" — the fallback restores Resolve as an anchor.
        engine.workAppPrefixes = AnchorSet.resolve(project: [], global: DetectionInput.defaultWorkAppPrefixes)
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        for _ in 0..<3 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .recording)
    }
}
