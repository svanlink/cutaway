import XCTest
import SwiftData
@testable import Cutaway

/// An accessibility audit found five things a VoiceOver user genuinely could
/// not do. Four of them were the same mistake: a label on a container
/// REPLACES its subtree, so labelling a row "Show sessions" deleted the date,
/// the hours and the money inside it. Every audit type passes on those —
/// the label is present, it is just wrong — so the only way to hold them
/// fixed is to assert the words.
@MainActor
final class SpokenContentTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: d, hour: h))!
    }

    // MARK: - The daily ledger

    func testEveryLedgerRowStatesItsOwnFigures() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 15),
                                       activeSeconds: 2 * 3600 + 14 * 60), to: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)

        let label = StatsView.dayRowLabel(day, project: p, isToday: false)
        XCTAssertTrue(label.contains("2 hours 14 minutes"), label)
        XCTAssertTrue(label.contains("CHF"), "the amount is the point of the row: \(label)")
        XCTAssertTrue(label.contains("July"), "and which day it was: \(label)")
        XCTAssertFalse(label.contains("Show sessions"),
                       "the disclosure verb belongs in the hint, not the label")
    }

    func testTodayIsSaidAsToday() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 11),
                                       activeSeconds: 3600), to: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertTrue(StatsView.dayRowLabel(day, project: p, isToday: true).hasPrefix("Today, "))
    }

    // MARK: - Announcements

    func testAnAutoSwitchIsAnnounced() {
        XCTAssertEqual(AppModel.switchAnnouncement(to: "Alpina Ski Promo"),
                       "Now tracking Alpina Ski Promo")
    }

    func testABankedSessionIsAnnouncedInWords() {
        let spoken = AppModel.bankedAnnouncement(47 * 60)
        XCTAssertEqual(spoken, "Session saved, 47 minutes")
        XCTAssertFalse(spoken.contains("✓"), "the pill's glyph must not be read aloud")
    }
}
