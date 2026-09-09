import XCTest
@testable import Cutaway

/// An hour that failed to save must still be there after the next session.
///
/// The bug this pins: the crash snapshot is one slot in UserDefaults, and a
/// failed save left the record there while the NEXT session's first
/// checkpoint overwrote it fifteen seconds later. Three and a half hours of
/// billable work, gone, while the banner told the owner to relaunch — the
/// one action that finished the job.
final class UnsavedSessionsTests: XCTestCase {

    private var dir: URL!
    private var journal: UnsavedSessions!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unsaved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = UnsavedSessions(storeURL: dir.appendingPathComponent("billing.store"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func record(_ seconds: TimeInterval) -> UnsavedSessions.Entry {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return UnsavedSessions.Entry(
            record: SessionRecord(start: start, end: start + seconds, activeSeconds: seconds),
            projectName: "Richemont", hourlyRate: 120, uid: "uid-\(Int(seconds))")
    }

    func testAFailedSaveIsStillThereAfterAnotherOne() {
        XCTAssertTrue(journal.append(record(12_600)))   // the 3.5-hour morning
        XCTAssertTrue(journal.append(record(45)))       // the afternoon that also failed

        let pending = journal.pending()
        XCTAssertEqual(pending.count, 2, "one slot held one record; this holds every one")
        XCTAssertEqual(pending[0].record.activeSeconds, 12_600, "oldest first, and the morning survived")
    }

    func testARecordIsDroppedOnlyWhenItsOwnSaveSucceeded() {
        journal.append(record(3600))
        journal.append(record(1800))

        // The first replays into the store; the second throws again.
        journal.replace(with: [journal.pending()[1]])

        XCTAssertEqual(journal.pending().map(\.record.activeSeconds), [1800],
                       "the one that saved is gone, the one that failed is kept")
    }

    func testAnEmptyReplayRemovesTheFileRatherThanLeavingLitter() {
        journal.append(record(60))
        journal.replace(with: [])
        XCTAssertTrue(journal.pending().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.url.path))
    }

    func testAMalformedLineDoesNotTakeTheOthersWithIt() throws {
        journal.append(record(3600))
        var blob = try Data(contentsOf: journal.url)
        blob.append(contentsOf: Array("{ not json\n".utf8))
        try blob.write(to: journal.url)
        journal.append(record(120))

        XCTAssertEqual(journal.pending().map(\.record.activeSeconds), [3600, 120],
                       "a corrupt line is skipped, never a reason to discard the rest")
    }

    func testNothingPendingOnAFreshMac() {
        XCTAssertTrue(journal.pending().isEmpty)
    }
}

extension UnsavedSessionsTests {
    /// A journal that cannot be READ must not be overwritten.
    ///
    /// `.atomic` writes are temp-file + rename and need only directory
    /// permission, so an unreadable file is still replaceable — and
    /// `existingData()` turned the read failure into empty Data. The append
    /// then reported success, the caller released the crash snapshot, and
    /// the morning was gone from the one file that exists to keep it.
    func testAnUnreadableJournalIsNotSilentlyReplaced() throws {
        journal.append(record(12_600))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: journal.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: journal.url.path) }
        try XCTSkipIf(getuid() == 0, "root reads anything; the guard cannot be exercised")

        XCTAssertFalse(journal.append(record(60)),
                       "an append that cannot see what is already there must fail loudly")
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: journal.url.path)
        XCTAssertEqual(journal.pending().map(\.record.activeSeconds), [12_600],
                       "and the parked work is still there")
    }
}
