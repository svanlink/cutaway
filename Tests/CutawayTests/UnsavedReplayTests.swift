import XCTest
@testable import Cutaway

/// The journal must not invent work, and must not invent a client.
///
/// Both defects here are in code written on 2026-09-09, in the fix for "a
/// failed save was overwritten by the next session". The fix parked failed
/// work in a journal and replayed it at launch — but the journal line carried
/// only {start, end, activeSeconds}:
///
///  - No project. Replay attached every record to whatever happened to be
///    selected at the next launch, which after an auto-switch or a rename is
///    a different client. That is the precise rule commit 648d6aa exists to
///    enforce: never bill the wrong project.
///  - No identity. SwiftData's save() can throw AFTER the row has landed, so
///    the record was journalled as well as stored — and replay wrote it a
///    second time. Three and a half hours could bill three times.
///  - No rate. A replayed record was priced at the rate in force at replay,
///    not the rate it was worked at, contradicting the comment on the very
///    line that stamps it.
@MainActor
final class UnsavedReplayTests: XCTestCase {

    private var store: SessionStore!
    private var dir: URL!
    private var journal: UnsavedSessions!

    override func setUpWithError() throws {
        store = try SessionStore(inMemory: true)
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = UnsavedSessions(storeURL: dir.appendingPathComponent("billing.store"))
        addTeardownBlock { [dir] in if let dir { try? FileManager.default.removeItem(at: dir) } }
    }

    private func record(_ seconds: TimeInterval) -> SessionRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return SessionRecord(start: start, end: start + seconds, activeSeconds: seconds)
    }

    /// A save that throws can still have written the row. Replaying it must
    /// not produce a second one.
    func testReplayingTheSameWorkTwiceStoresItOnce() throws {
        let p = try store.createProject(name: "Aurora", client: "Aurora EC",
                                        mode: .hourly, hourlyRate: 120, currency: .chf)
        let entry = UnsavedSessions.Entry(record: record(12_600), projectName: "Aurora",
                                          hourlyRate: 120, uid: "fixed-uid-1")
        try store.record(entry.record, to: p, uid: entry.uid)
        try store.record(entry.record, to: p, uid: entry.uid)

        XCTAssertEqual(p.sessions.count, 1, "the same banked work must not land twice")
        XCTAssertEqual(p.sessions.first?.activeSeconds, 12_600)
    }

    /// The journal remembers whose work it is.
    func testTheJournalCarriesTheProjectAndTheRate() {
        let entry = UnsavedSessions.Entry(record: record(3600), projectName: "Aurora",
                                          hourlyRate: 120, uid: "u1")
        XCTAssertTrue(journal.append(entry))
        let back = journal.pending()
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].projectName, "Aurora")
        XCTAssertEqual(back[0].hourlyRate, 120, "priced at what it was worked at, not at replay time")
        XCTAssertEqual(back[0].uid, "u1")
    }

    /// A record whose project cannot be found is KEPT, not billed to someone
    /// else — the same ruling `SessionRecovery.target` already makes for the
    /// crash snapshot.
    func testWorkForAMissingProjectIsHeldRatherThanGuessedAt() throws {
        _ = try store.createProject(name: "Alpina", client: "Alpina", mode: .hourly,
                                    hourlyRate: 90, currency: .chf)
        let entry = UnsavedSessions.Entry(record: record(3600), projectName: "Aurora",
                                          hourlyRate: 120, uid: "u2")
        let target = UnsavedSessions.owner(of: entry, among: try store.projects())
        XCTAssertNil(target, "a name nobody answers to must not become somebody's invoice")

        let known = UnsavedSessions.Entry(record: record(60), projectName: "Alpina",
                                          hourlyRate: 90, uid: "u3")
        XCTAssertEqual(UnsavedSessions.owner(of: known, among: try store.projects())?.name, "Alpina")
    }
}

extension UnsavedReplayTests {
    /// A journal written by the previous release must still be readable.
    ///
    /// Found by Greptile, 2026-09-10. The journal shipped this morning storing
    /// a bare {start, end, activeSeconds}; hours later it became an Entry
    /// carrying the project, the rate and an identity. `pending()` decodes
    /// only Entry and compactMaps the failures away — so an upgrade over a
    /// journal holding parked work read it as EMPTY, and the next
    /// `replace(with:)` rewrote the file without those lines. Work that
    /// survived a failed save was deleted by the fix for failed saves.
    func testAJournalFromTheOlderFormatIsStillRead() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = SessionRecord(start: start, end: start + 12_600, activeSeconds: 12_600)
        let line = try JSONEncoder().encode(legacy)
        var blob = Data(); blob.append(line); blob.append(0x0A)
        try blob.write(to: journal.url)

        let pending = journal.pending()
        XCTAssertEqual(pending.count, 1, "the morning is still in the journal, not silently gone")
        XCTAssertEqual(pending[0].record.activeSeconds, 12_600)
        XCTAssertTrue(pending[0].projectName.isEmpty,
                      "the old format carried no project — that must stay unknown, not be guessed")
    }

    /// And unknown-project work is HELD, never billed to whoever is selected.
    func testWorkFromTheOlderFormatIsNeverBilledToAGuess() throws {
        let p = try store.createProject(name: "Alpina", client: "Alpina", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        let orphan = UnsavedSessions.Entry(record: record(3600), projectName: "",
                                           hourlyRate: 0, uid: "legacy-1")
        XCTAssertNil(UnsavedSessions.owner(of: orphan, among: [p]),
                     "no project answers to an empty name, so nobody gets billed for it")
    }
}
