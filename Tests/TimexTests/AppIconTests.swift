import XCTest
import AppKit
@testable import Cutaway

@MainActor
final class AppIconTests: XCTestCase {
    func testInstalledAppYieldsItsIconAndCachesIt() {
        let host = InstalledApp(name: "Cutaway", bundleID: Bundle.main.bundleIdentifier!, url: Bundle.main.bundleURL)
        let first = AppIcon.image(for: host)
        XCTAssertNotNil(first)
        XCTAssertTrue(AppIcon.image(for: host) === first, "second lookup is the cached object")
    }

    func testNotInstalledYieldsNoImage() {
        XCTAssertNil(AppIcon.image(for: nil))
    }
}
