import XCTest
import SwiftData
@testable import Cutaway

/// Money already invoiced must not change because the project's rate changed
/// later. Before this, every earnings figure was seconds × the CURRENT rate,
/// so the October export of September's work disagreed with the invoice
/// already sent — and the new file was the wrong one.
@MainActor
final class RateHistoryTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func record(_ p: Project, day: Int, hours: Double) throws {
        let start = date(2026, 7, day, 9)
        try store.record(SessionRecord(start: start,
                                       end: start.addingTimeInterval(hours * 3600),
                                       activeSeconds: hours * 3600), to: p, calendar: cal)
    }

    func testARaiseDoesNotRepriceWorkAlreadyDone() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        try record(p, day: 16, hours: 2)          // billed at 85 → 170
        p.hourlyRate = 120
        try store.context.save()
        try record(p, day: 17, hours: 2)          // billed at 120 → 240

        let days = store.dayTotals(for: p, calendar: cal).sorted { $0.day < $1.day }
        XCTAssertEqual(days[0].earned, 170, accuracy: 0.001, "September's work stays at September's rate")
        XCTAssertEqual(days[1].earned, 240, accuracy: 0.001)
        XCTAssertEqual(store.totalEarned(for: p), 410, accuracy: 0.001,
                       "the total is the sum of what each day actually earned")
    }

    func testTotalAlwaysReconcilesWithTheDays() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        try record(p, day: 16, hours: 3)
        p.hourlyRate = 100
        try store.context.save()
        try record(p, day: 17, hours: 1.5)
        p.hourlyRate = 42
        try store.context.save()

        let sum = store.dayTotals(for: p, calendar: cal).reduce(0) { $0 + $1.earned }
        XCTAssertEqual(sum, store.totalEarned(for: p), accuracy: 0.001,
                       "a third rate change must not desync the day rows from the total")
    }

    func testLegacyRowsBillAtTheProjectRate() throws {
        let p = try store.createProject(name: "Old", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        // A row written before the rate field existed: hourlyRate == 0.
        store.context.insert(WorkSession(start: date(2026, 7, 16, 9), end: date(2026, 7, 16, 11),
                                         activeSeconds: 7200, hourlyRate: 0, project: p))
        try store.context.save()
        XCTAssertEqual(store.totalEarned(for: p), 180, accuracy: 0.001,
                       "a pre-migration row prices exactly as it always did — no silent zeroes")
    }

    func testEffectiveRateBlendsADayThatSpansARateChange() throws {
        let p = try store.createProject(name: "Split", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try record(p, day: 16, hours: 1)          // 100
        p.hourlyRate = 200
        try store.context.save()
        try record(p, day: 16, hours: 1)          // 200, same day

        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.earned, 300, accuracy: 0.001)
        XCTAssertEqual(day.effectiveRate, 150, accuracy: 0.001,
                       "hours × printed rate must reconcile with earned, even mid-change")
    }

    func testRateIsStampedAtRecordTimeNotReadLater() throws {
        let p = try store.createProject(name: "Stamp", client: "", mode: .hourly,
                                        hourlyRate: 75, currency: .chf)
        try record(p, day: 16, hours: 1)
        let session = try XCTUnwrap(store.sessions(for: p, on: date(2026, 7, 16, 0), calendar: cal).first)
        XCTAssertEqual(session.hourlyRate, 75, "the rate travels with the session, not the project")
    }
}
