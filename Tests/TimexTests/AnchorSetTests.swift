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
}
