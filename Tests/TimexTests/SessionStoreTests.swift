import XCTest
@testable import Cutaway

@MainActor
final class SessionStoreTests: XCTestCase {

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

    func testCreateAndFetchProject() throws {
        try store.createProject(name: "Nyx", client: "Nyx Studios", mode: .hourly,
                                hourlyRate: 85, currency: .chf)
        let projects = try store.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Nyx")
        XCTAssertEqual(projects[0].currency, .chf)
    }

    func testRecordSessionAndTotals() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        let rec = SessionRecord(start: date(2026, 7, 17, 10), end: date(2026, 7, 17, 12), activeSeconds: 6000)
        try store.record(rec, to: p, calendar: cal)
        XCTAssertEqual(store.totalActiveSeconds(for: p), 6000)
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).count, 1)
    }

    func testMidnightSessionCreatesTwoDayRows() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        let rec = SessionRecord(start: date(2026, 7, 17, 23), end: date(2026, 7, 18, 1), activeSeconds: 7200)
        try store.record(rec, to: p, calendar: cal)
        let days = store.dayTotals(for: p, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(store.totalActiveSeconds(for: p), 7200, accuracy: 1)
    }

    func testAvgDailySeconds() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        try store.record(SessionRecord(start: date(2026, 7, 16, 10), end: date(2026, 7, 16, 12), activeSeconds: 7200), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(2026, 7, 17, 10), end: date(2026, 7, 17, 11), activeSeconds: 3600), to: p, calendar: cal)
        XCTAssertEqual(store.avgDailySeconds(for: p, calendar: cal), 5400, accuracy: 1)
    }
}

final class ProjectDetectorParsingTests: XCTestCase {

    func testParsesProjectFromHyphenTitle() {
        XCTAssertEqual(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - Nyx Fashion Film"),
                       "Nyx Fashion Film")
    }

    func testParsesProjectWithDashesInName() {
        XCTAssertEqual(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - Alpina - Ski Promo"),
                       "Alpina - Ski Promo")
    }

    func testBareTitleReturnsNil() {
        XCTAssertNil(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve"))
    }

    func testEmptySuffixReturnsNil() {
        XCTAssertNil(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - "))
    }
}
