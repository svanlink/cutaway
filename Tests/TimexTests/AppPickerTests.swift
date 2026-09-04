import XCTest
@testable import Cutaway

final class AppPickerTests: XCTestCase {
    private let installed = [
        InstalledApp(name: "Premiere Pro 2025", bundleID: "com.adobe.PremierePro.2025", url: URL(fileURLWithPath: "/a")),
        InstalledApp(name: "Excel", bundleID: "com.microsoft.Excel", url: URL(fileURLWithPath: "/b")),
        InstalledApp(name: "Spotify", bundleID: "com.spotify.client", url: URL(fileURLWithPath: "/c")),
    ]

    func testSearchFiltersAcrossGroupsAndDropsEmptyGroups() {
        var m = AppPickerModel(selected: [])
        m.query = "prem"
        let groups = m.visibleGroups(catalog: AppCatalog.groups, installed: installed)
        XCTAssertEqual(groups.map(\.name), ["Adobe"])
        XCTAssertEqual(groups[0].entries.map(\.name), ["Premiere Pro"])
    }

    func testOtherIsEveryInstalledAppNotAlreadyInTheCatalog() {
        let m = AppPickerModel(selected: [])
        XCTAssertEqual(m.otherApps(installed: installed).map(\.name), ["Spotify"],
                       "Premiere and Excel are catalog apps; only Spotify is 'other'")
    }

    func testToggleAddsAndRemoves() {
        var m = AppPickerModel(selected: ["a"])
        m.toggle("b"); XCTAssertEqual(m.selected, ["a", "b"])
        m.toggle("a"); XCTAssertEqual(m.selected, ["b"])
    }

    func testSearchAlsoReachesOtherApps() {
        var m = AppPickerModel(selected: [])
        m.query = "spot"
        XCTAssertEqual(m.otherApps(installed: installed).map(\.name), ["Spotify"])
        m.query = "zzz"
        XCTAssertTrue(m.otherApps(installed: installed).isEmpty)
    }
}
