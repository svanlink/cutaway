import XCTest
import SwiftData
@testable import Cutaway

/// A backup nobody has restored is a belief, not a backup. The README tells
/// a user whose Mac died to quit Cutaway, copy three files back into
/// Application Support, and relaunch. Until now nothing had ever done that
/// and checked the money was still there.
@MainActor
final class DisasterRecoveryTests: XCTestCase {

    private var dir: URL!
    private var live: URL!
    private var backups: URL!
    private var cal: Calendar!
    private var fm: FileManager { .default }

    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dr-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        live = dir.appendingPathComponent("default.store")
        backups = dir.appendingPathComponent("Backups")
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    override func tearDown() async throws { try? fm.removeItem(at: dir) }

    private func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: d, hour: h))!
    }

    /// A fortnight of billable work, the thing a user would actually lose.
    @discardableResult
    private func seedAndClose() throws -> (projects: Int, seconds: TimeInterval, earned: Double) {
        let store = try SessionStore(url: live)
        let nyx = try store.createProject(name: "Nyx Fashion Film", client: "Nyx Studios",
                                          mode: .hourly, hourlyRate: 85, currency: .chf)
        let alpina = try store.createProject(name: "Alpina Ski Promo", client: "Alpina",
                                             mode: .budget, hourlyRate: 120, budget: 4500,
                                             currency: .chf)
        for day in 1...10 {
            try store.record(SessionRecord(start: date(day, 9), end: date(day, 17),
                                           activeSeconds: 6.5 * 3600), to: nyx, calendar: cal)
            try store.record(SessionRecord(start: date(day, 18), end: date(day, 20),
                                           activeSeconds: 1.5 * 3600), to: alpina, calendar: cal)
        }
        let totals = (projects: try store.projects().count,
                      seconds: store.totalActiveSeconds(for: nyx) + store.totalActiveSeconds(for: alpina),
                      earned: store.totalEarned(for: nyx) + store.totalEarned(for: alpina))
        // SwiftData holds the files open; drop the container before copying.
        return totals
    }

    /// The README's procedure, performed literally.
    private func restoreNewestBackup() throws {
        let folders = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let newest = try XCTUnwrap(folders.last)
        for suffix in ["", "-wal", "-shm"] {
            let src = newest.appendingPathComponent("default.store" + suffix)
            let dst = URL(fileURLWithPath: live.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
    }

    private func destroyLiveStore() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: live.path + suffix))
        }
        XCTAssertFalse(fm.fileExists(atPath: live.path), "the disaster has to actually happen")
    }

    func testTheDocumentedRestoreProcedureActuallyWorks() throws {
        let before = try seedAndClose()
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: live, backupsDir: backups))

        try destroyLiveStore()
        try restoreNewestBackup()

        let recovered = try SessionStore(url: live)
        let projects = try recovered.projects()
        XCTAssertEqual(projects.count, before.projects, "every project came back")

        let seconds = projects.reduce(0.0) { $0 + recovered.totalActiveSeconds(for: $1) }
        let earned = projects.reduce(0.0) { $0 + recovered.totalEarned(for: $1) }
        XCTAssertEqual(seconds, before.seconds, accuracy: 0.001, "every tracked second came back")
        XCTAssertEqual(earned, before.earned, accuracy: 0.01, "and it is still worth the same")
    }

    /// Rates are stamped per session; a restore that lost them would reprice
    /// history at whatever the project rate happens to be now.
    func testRestoredSessionsKeepTheRateTheyWereWorkedAt() throws {
        let store = try SessionStore(url: live)
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        try store.record(SessionRecord(start: date(1, 9), end: date(1, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        p.hourlyRate = 200
        try store.context.save()
        try store.record(SessionRecord(start: date(2, 9), end: date(2, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let expected = store.totalEarned(for: p)   // 170 + 400

        XCTAssertNotNil(try StoreBackup.backUp(storeURL: live, backupsDir: backups))
        try destroyLiveStore()
        try restoreNewestBackup()

        let recovered = try SessionStore(url: live)
        let p2 = try XCTUnwrap(try recovered.projects().first)
        XCTAssertEqual(recovered.totalEarned(for: p2), expected, accuracy: 0.01,
                       "a restore must not reprice invoices that were already sent")
        XCTAssertEqual(expected, 570, accuracy: 0.01, "sanity: 2h at 85 plus 2h at 200")
    }

    /// The oldest kept backup is the one someone reaches for when they notice
    /// the problem late. It has to work too.
    func testAnOlderBackupIsAlsoRestorable() throws {
        try seedAndClose()
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: live, backupsDir: backups))
        let firstGeneration = try SessionStore(url: live).projects().count

        // More work happens, and is backed up again.
        let store = try SessionStore(url: live)
        _ = try store.createProject(name: "Later Project", client: "", mode: .hourly,
                                    hourlyRate: 85, currency: .chf)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: live, backupsDir: backups,
                                               now: Date().addingTimeInterval(60)))

        let folders = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("billing-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(folders.count, 2)

        // Restore the OLDER one.
        try destroyLiveStore()
        for suffix in ["", "-wal", "-shm"] {
            let src = folders[0].appendingPathComponent("default.store" + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: URL(fileURLWithPath: live.path + suffix))
        }
        let recovered = try SessionStore(url: live)
        XCTAssertEqual(try recovered.projects().count, firstGeneration,
                       "the older generation restores to the state it captured")
    }
}
