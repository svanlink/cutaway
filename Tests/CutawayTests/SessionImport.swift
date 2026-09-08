import XCTest
@testable import Cutaway

/// Bulk entry of days worked, through the app's OWN store API — so spans are
/// stamped with the project's rate, split at midnight, marked as entered
/// rather than tracked, and refused on an invoiced day, exactly as they
/// would be if they had been typed one at a time.
///
/// Skipped unless CUTAWAY_IMPORT is set. Run only with the app quit: two
/// processes writing one SwiftData store is the accident this project has
/// already had once.
///
/// CUTAWAY_IMPORT_STORE   absolute path to the store
/// CUTAWAY_IMPORT_CLEAR   yyyy-MM-dd days whose sessions are removed first
/// CUTAWAY_IMPORT         "yyyy-MM-dd HH:mm HH:mm" entries, semicolon-separated
@MainActor
final class SessionImport: XCTestCase {

    func testImport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["CUTAWAY_IMPORT"], let path = env["CUTAWAY_IMPORT_STORE"] else {
            throw XCTSkip("set CUTAWAY_IMPORT and CUTAWAY_IMPORT_STORE")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let store = try SessionStore(inMemory: false, url: URL(fileURLWithPath: path))
        let projects = try store.projects()
        guard let project = projects.first else { return XCTFail("no project in that store") }
        XCTAssertEqual(projects.count, 1, "this importer assumes one project; got \(projects.map(\.name))")

        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = cal
        day.timeZone = cal.timeZone
        day.dateFormat = "yyyy-MM-dd"

        for stamp in (env["CUTAWAY_IMPORT_CLEAR"] ?? "").split(separator: ",") where !stamp.isEmpty {
            guard let d = day.date(from: String(stamp)) else { continue }
            for session in store.sessions(for: project, on: d, calendar: cal) {
                try store.deleteSession(session, calendar: cal)
            }
            print("IMPORT: cleared \(stamp)")
        }

        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.calendar = cal
        clock.timeZone = cal.timeZone
        clock.dateFormat = "yyyy-MM-dd HH:mm"

        for entry in spec.split(separator: ";") {
            let parts = entry.split(separator: " ").map(String.init)
            guard parts.count == 3,
                  let from = clock.date(from: "\(parts[0]) \(parts[1])"),
                  let to = clock.date(from: "\(parts[0]) \(parts[2])") else {
                return XCTFail("could not read entry: \(entry)")
            }
            try store.addSession(from: from, to: to, for: project, calendar: cal)
            print("IMPORT: \(parts[0]) \(parts[1])–\(parts[2]) = \(String(format: "%.2f", to.timeIntervalSince(from) / 3600)) h")
        }

        let totals = store.dayTotals(for: project, calendar: cal)
        let hours = totals.reduce(0.0) { $0 + $1.activeSeconds } / 3600
        print("IMPORT TOTAL: \(totals.count) days, \(String(format: "%.2f", hours)) h")
    }
}
