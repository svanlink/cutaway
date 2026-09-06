import XCTest
@testable import Cutaway

final class AppCatalogTests: XCTestCase {

    func testNoCatalogPrefixShadowsAnother() {
        let prefixes = AppCatalog.allEntries.map(\.prefix)
        XCTAssertEqual(Set(prefixes).count, prefixes.count, "duplicate prefix")
        // Resolve's three ids are a family the engine matches EXACTLY (they are
        // DetectionInput.resolveBundleIDs), so "…DaVinciResolve" being a string
        // prefix of "…DaVinciResolveLite" is not a shadow.
        let exact = Set(DetectionInput.resolveBundleIDs)
        for a in prefixes where !exact.contains(a) {
            for b in prefixes where a != b {
                XCTAssertFalse(b.hasPrefix(a), "\(a) would also match \(b) — one tile would tick two apps")
            }
        }
    }

    func testTheNamedSuitesArePresent() {
        let names = Set(AppCatalog.groups.map(\.name))
        for g in ["DaVinci Resolve", "Adobe", "Microsoft Office", "Also"] {
            XCTAssertTrue(names.contains(g), g)
        }
        XCTAssertTrue(AppCatalog.allEntries.contains { $0.prefix == "com.adobe.PremierePro" })
        XCTAssertTrue(AppCatalog.allEntries.contains { $0.prefix == "com.microsoft.Excel" })
    }

    /// One Resolve tile whose prefix reaches every edition the engine knows.
    func testOneResolveTileCoversEveryEdition() throws {
        let resolve = try XCTUnwrap(AppCatalog.groups.first { $0.name == "DaVinci Resolve" })
        XCTAssertEqual(resolve.entries.count, 1)
        let prefix = resolve.entries[0].prefix
        for id in DetectionInput.resolveBundleIDs {
            XCTAssertTrue(id.hasPrefix(prefix), "\(id) must be covered by \(prefix)")
        }
    }

    /// The scan finds the app the tests are running inside — no fixture, no
    /// assumption about what is in /Applications on this Mac.
    func testScanFindsTheTestHost() {
        let productsDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let found = InstalledApps.scan(directories: [productsDir])
        let host = found.first { $0.bundleID == Bundle.main.bundleIdentifier }
        XCTAssertNotNil(host, "Cutaway.app must be found in \(productsDir.path)")
        XCTAssertEqual(host?.name, "Cutaway")
    }

    func testScanSkipsNonBundlesAndSortsByName() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Empty.app"), withIntermediateDirectories: true)
        for (name, id) in [("Zed", "dev.zed"), ("Alpha", "com.alpha")] {
            let contents = dir.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        let found = InstalledApps.scan(directories: [dir])
        XCTAssertEqual(found.map(\.name), ["Alpha", "Zed"], "sorted; Empty.app (no plist) and notes.txt skipped")
    }

    /// Adobe and Blackmagic ship inside a vendor folder ("Adobe Premiere Pro
    /// 2026/Adobe Premiere Pro 2026.app", "DaVinci Resolve/DaVinci
    /// Resolve.app"). A scan that stops at the top level calls the user's
    /// main tools "not installed".
    func testScanLooksOneFolderDeepForVendorSuites() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nested = dir.appendingPathComponent("Adobe Premiere Pro 2026/Adobe Premiere Pro 2026.app/Contents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.adobe.PremierePro.2026", "CFBundleName": "Premiere Pro"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: nested.appendingPathComponent("Info.plist"))
        // Two levels down is not a suite folder; it stays out of the list.
        let deep = dir.appendingPathComponent("Vendor/Sub/Deep.app/Contents")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "x.deep"] as [String: Any], format: .xml, options: 0)
            .write(to: deep.appendingPathComponent("Info.plist"))
        let found = InstalledApps.scan(directories: [dir])
        XCTAssertEqual(found.map(\.bundleID), ["com.adobe.PremierePro.2026"])
    }

    func testPrefixResolvesToAnInstalledBundle() {
        let apps = [
            InstalledApp(name: "Premiere Pro 2025", bundleID: "com.adobe.PremierePro.2025", url: URL(fileURLWithPath: "/x")),
            InstalledApp(name: "Excel", bundleID: "com.microsoft.Excel", url: URL(fileURLWithPath: "/y")),
        ]
        XCTAssertEqual(InstalledApps.installed(matching: "com.adobe.PremierePro", in: apps)?.bundleID, "com.adobe.PremierePro.2025")
        XCTAssertEqual(InstalledApps.installed(matching: "com.microsoft.Excel", in: apps)?.name, "Excel")
        XCTAssertNil(InstalledApps.installed(matching: "com.blackmagic-design.DaVinciResolve", in: apps))
    }
}
