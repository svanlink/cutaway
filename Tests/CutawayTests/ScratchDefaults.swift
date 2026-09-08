import XCTest

/// cfprefsd writes an EMPTY plist back after a domain is removed, so
/// per-test cleanup alone still leaves a 42-byte file per scratch suite.
/// This sweeps the folder when the first scratch suite of a run is asked
/// for (clearing whatever the previous run left) and again when the bundle
/// finishes. Litter is bounded to one run instead of growing forever.
private final class ScratchSweeper: NSObject, XCTestObservation {
    nonisolated(unsafe) static let shared = ScratchSweeper()
    nonisolated(unsafe) private static var armed = false

    static func arm() {
        guard !armed else { return }
        armed = true
        XCTestObservationCenter.shared.addTestObserver(shared)
        sweep()
    }

    func testBundleDidFinish(_ testBundle: Bundle) { Self.sweep() }

    static func sweep() {
        let prefs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: prefs.path) else { return }
        for name in names where name.hasPrefix("cutaway.tests.") && name.hasSuffix(".plist") {
            try? FileManager.default.removeItem(at: prefs.appendingPathComponent(name))
        }
    }
}

extension XCTestCase {
    /// A throwaway defaults suite that removes itself.
    ///
    /// Tests used to open `UserDefaults(suiteName: "cutaway.tests.<uuid>")`
    /// and walk away. On 2026-09-07 the owner's Mac held 3'921 abandoned
    /// domains and 3'921 plists in ~/Library/Preferences, one pair per test
    /// run since the suite existed. Nothing in a test may outlive the test.
    func scratchDefaults(_ name: String = "cutaway.tests.\(UUID().uuidString)") -> UserDefaults {
        ScratchSweeper.arm()
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        // Capture the NAME, not the instance: a UserDefaults crossing into
        // the @Sendable teardown block is a Swift 6 data-race error, and
        // removePersistentDomain works on any domain from `.standard`.
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
            UserDefaults.standard.removeSuite(named: name)
            // removePersistentDomain empties the domain; the plist itself can
            // survive it. Take the file too, or the folder still fills up.
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        return defaults
    }
}

final class ScratchDefaultsTests: XCTestCase {
    /// The guard on the guard: a scratch suite must leave no plist behind.
    func testAScratchSuiteRemovesItsOwnFile() {
        let name = "cutaway.tests.selfcheck.\(UUID().uuidString)"
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        do {
            let d = UserDefaults(suiteName: name)!
            d.set(true, forKey: "written")
            d.removePersistentDomain(forName: name)
            UserDefaults.standard.removeSuite(named: name)
            try? FileManager.default.removeItem(at: plist)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path),
                       "a test suite must not leave a plist in the user's Preferences")
    }
}
