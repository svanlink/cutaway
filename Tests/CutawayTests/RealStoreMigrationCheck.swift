import XCTest
import SwiftData
@testable import Cutaway

/// Opens a REAL store copy under the current schema and reports what
/// survived. Skipped unless CUTAWAY_MIGRATE_CHECK points at one.
///
/// This exists because "the migration is lightweight" is a claim, and the
/// owner's store is the only copy of what they are owed. Run it on a COPY
/// before installing a build that changes the schema.
@MainActor
final class RealStoreMigrationCheck: XCTestCase {
    func testARealStoreOpensAndKeepsItsWork() throws {
        guard let path = ProcessInfo.processInfo.environment["CUTAWAY_MIGRATE_CHECK"] else {
            throw XCTSkip("set CUTAWAY_MIGRATE_CHECK to a COPY of a real store")
        }
        let store = try SessionStore(inMemory: false, url: URL(fileURLWithPath: path))
        let projects = try store.projects()
        var totalSessions = 0
        var totalHours = 0.0
        for p in projects {
            totalSessions += p.sessions.count
            let seconds = p.sessions.reduce(0.0) { $0 + $1.activeSeconds }
            totalHours += seconds / 3600
            print("MIGRATE: project=\(p.name) sessions=\(p.sessions.count) hours=\(String(format: "%.2f", seconds / 3600)) rate=\(p.hourlyRate) currency=\(p.currency.rawValue)")
        }
        print("MIGRATE TOTAL: projects=\(projects.count) sessions=\(totalSessions) hours=\(String(format: "%.2f", totalHours))")
        XCTAssertFalse(projects.isEmpty, "a real store must not come back empty")
    }
}
