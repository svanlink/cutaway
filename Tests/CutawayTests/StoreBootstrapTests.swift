import XCTest
@testable import Cutaway

/// The launch sequence, testable for the first time.
///
/// It spent a year inside `AppModel.init`, which is the one place a test
/// cannot reach — constructing an AppModel opens the real billing store. It
/// is also the only code in the app that irreversibly touches the owner's
/// money, so "untested because it is hard to reach" was the wrong trade.
@MainActor
final class StoreBootstrapTests: XCTestCase {

    private var dir: URL!
    private var storeURL: URL!
    private var backups: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bootstrap-\(UUID().uuidString)", isDirectory: true)
        backups = dir.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("billing.store")
        addTeardownBlock { [dir] in if let dir { try? FileManager.default.removeItem(at: dir) } }
    }

    private func open(ask: @escaping (String, StoreBootstrap.Candidate?) -> StoreBootstrap.DamagedStoreChoice,
                      revealed: UnsafeMutablePointer<Int>? = nil) throws -> StoreBootstrap.Opened {
        StoreBootstrap.open(
            scenario: false, storeURL: storeURL, backupsDir: backups,
            ask: ask,
            reveal: { _ in revealed?.pointee += 1 },
            adoptLegacy: { false },                       // never the real store
            makeStore: { try SessionStore(inMemory: true) },
            makeMemoryStore: { try SessionStore(inMemory: true) })
    }

    /// A damaged store the owner declines to restore stays EXACTLY as it is —
    /// the whole ruling in one test.
    func testDecliningLeavesTheDamagedFileUntouchedAndRunsInMemory() throws {
        try Data().write(to: storeURL)                    // zero-byte = damaged
        let before = try Data(contentsOf: storeURL)
        var asked = 0
        let opened = try open(ask: { _, _ in asked += 1; return .continueWithout })

        XCTAssertEqual(asked, 1, "it asks — always")
        XCTAssertTrue(opened.isEphemeral, "nothing tracked this run is kept")
        XCTAssertEqual(try Data(contentsOf: storeURL), before, "the evidence survives")
        XCTAssertTrue(opened.flags.contains { $0.contains("damaged") })
    }

    func testRevealingAlsoRefusesToOpenTheDamagedStore() throws {
        try Data().write(to: storeURL)
        var reveals = 0
        let opened = try withUnsafeMutablePointer(to: &reveals) { pointer in
            try open(ask: { _, _ in .revealBackups }, revealed: pointer)
        }
        XCTAssertEqual(reveals, 1)
        XCTAssertTrue(opened.isEphemeral)
    }

    /// A healthy store opens with nothing said at all.
    func testAUsableStoreOpensSilently() throws {
        try makeUsableStore(at: storeURL)
        let opened = try open(ask: { _, _ in XCTFail("must not ask about a healthy store"); return .continueWithout })
        XCTAssertFalse(opened.isEphemeral)
        XCTAssertTrue(opened.notices.isEmpty, "said: \(opened.notices)")
        // Name the flag. "isEmpty failed" told us a healthy store had
        // complained about something and nothing else, which cost a full-suite
        // hunt to reproduce.
        XCTAssertTrue(opened.flags.isEmpty, "flagged: \(opened.flags)")
    }

    /// First run: no store yet, nothing to back up, nothing to say.
    func testAnAbsentStoreIsNotADisaster() throws {
        let opened = try open(ask: { _, _ in XCTFail("a first run must not ask"); return .continueWithout })
        XCTAssertFalse(opened.isEphemeral)
        XCTAssertFalse(opened.backupMade)
    }

    /// The disk saying no is not the file saying no: warn, change nothing,
    /// and do NOT back up — a backup of an unreadable store would only push
    /// good generations out of the rotation.
    func testAnUnreadableStoreWarnsAndBacksUpNothing() throws {
        try makeUsableStore(at: storeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
        addTeardownBlock { [storeURL] in
            if let storeURL { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }
        }
        let opened = try open(ask: { _, _ in XCTFail("unreadable must never propose a restore"); return .continueWithout })
        XCTAssertFalse(opened.backupMade)
        XCTAssertTrue(opened.flags.contains { $0.contains("read the billing store") })
    }

    private func makeUsableStore(at url: URL) throws {
        let store = try SessionStore(inMemory: false, url: url)
        _ = try store.createProject(name: "Richemont", client: "", mode: .hourly,
                                    hourlyRate: 120, currency: .chf)
    }
}

/// The schedule that decides when each detection tier runs — until today it
/// lived inside a closure in `AppModel.init` and could only be read.
final class DetectionScheduleTests: XCTestCase {

    func testTierTwoRunsEveryFiveTicks() {
        var s = DetectionSchedule()
        var hits = 0
        for _ in 1...20 { s.advance(); if s.runsTier2 { hits += 1 } }
        XCTAssertEqual(hits, 4)
    }

    /// A fresh install must adopt whatever is already open in Resolve within
    /// seconds, not after the steady-state interval.
    func testTierOneFiresEarlyOnce() {
        var s = DetectionSchedule()
        for _ in 1...DetectionSchedule.tier1FirstAt { s.advance() }
        XCTAssertTrue(s.runsTier1(accessibilityGranted: true), "tick 3, whatever the interval")
    }

    /// Spawning fuscript is the heaviest periodic cost in the app, so the
    /// cheap tier being available has to actually buy something.
    func testTierOneBacksOffWhenAccessibilityIsGranted() {
        var granted = DetectionSchedule()
        var without = DetectionSchedule()
        var grantedHits = 0, withoutHits = 0
        for _ in 1...240 {
            granted.advance(); without.advance()
            if granted.runsTier1(accessibilityGranted: true) { grantedHits += 1 }
            if without.runsTier1(accessibilityGranted: false) { withoutHits += 1 }
        }
        XCTAssertEqual(grantedHits, 3, "every 120 ticks, plus the early one")
        XCTAssertEqual(withoutHits, 9, "every 30 ticks, plus the early one")
        XCTAssertLessThan(grantedHits, withoutHits)
    }
}

/// Where a crash snapshot belongs. A phantom session on the wrong client is
/// worse than a dropped one.
final class SessionRecoveryTests: XCTestCase {

    func testASnapshotNamingAKnownProjectGoesThere() {
        XCTAssertEqual(SessionRecovery.target(snapshotProject: "Richemont EC",
                                              existing: ["Nyx", "Richemont EC"]),
                       .project("Richemont EC"))
    }

    /// Tiers disagree about case and diacritics; two spellings of one project
    /// would split its billing.
    func testMatchingIgnoresCaseAndAccents() {
        XCTAssertEqual(SessionRecovery.target(snapshotProject: "maisons présentation",
                                              existing: ["Maisons Presentation"]),
                       .project("Maisons Presentation"))
    }

    func testAnOlderSnapshotWithNoNameUsesTheSelection() {
        XCTAssertEqual(SessionRecovery.target(snapshotProject: nil, existing: ["Nyx"]), .selection)
    }

    /// Kept, not guessed at: the project may come back by a rename or a
    /// restore, and the snapshot is only cleared once it is safely persisted.
    func testAnUnknownProjectDefersRatherThanLanding() {
        XCTAssertEqual(SessionRecovery.target(snapshotProject: "Gone", existing: ["Nyx"]),
                       .defer_("Gone"))
    }
}
