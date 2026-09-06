import XCTest
import AppKit
@testable import Cutaway

@MainActor
final class FrontmostTrackerTests: XCTestCase {
    func testStartsFromTheGivenValueAndFollowsNotifications() {
        let nc = NotificationCenter()
        let t = FrontmostTracker(initial: "com.apple.finder", center: nc)
        XCTAssertEqual(t.bundleID, "com.apple.finder")
        nc.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: FakeApp(id: "com.blackmagic-design.DaVinciResolve")])
        XCTAssertEqual(t.bundleID, "com.blackmagic-design.DaVinciResolve")
    }

    /// The userInfo carries an NSRunningApplication in production; the tracker
    /// reads `bundleIdentifier` through a protocol so a test can post a fake.
    struct FakeApp: FrontmostApplication { let id: String; var bundleIdentifier: String? { id } }
}
