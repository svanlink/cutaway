import XCTest
import SwiftData
@testable import Cutaway

/// The store's schema identity is declared, not inferred. Ruled blocking on
/// 2026-09-07: entities added to an undeclared schema leave a later
/// `SchemaV1` with no version to migrate from, and the only path left is the
/// in-memory fallback — a day of billing into RAM behind a banner.
@MainActor
final class SchemaVersionTests: XCTestCase {

    func testVersionOneHoldsExactlyTheEntitiesThatShipped() {
        let names = Set(CutawaySchemaV1.models.map { String(describing: $0) })
        XCTAssertEqual(names, ["Project", "WorkSession"],
                       "V1 is history — it describes what the store already holds, not what is wanted now")
        XCTAssertEqual(CutawaySchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testTheMigrationPlanStartsAtVersionOne() {
        XCTAssertEqual(CutawayMigrationPlan.schemas.count, 1)
        XCTAssertTrue(CutawayMigrationPlan.schemas.first == CutawaySchemaV1.self)
        XCTAssertTrue(CutawayMigrationPlan.stages.isEmpty,
                      "every change so far is lightweight; the plan exists for the first one that is not")
    }

    /// The whole point: a store written before the declaration still opens.
    func testAStoreWrittenByTheUndeclaredSchemaStillOpens() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("billing.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        // Written the old way — the implicit schema from an argument list.
        let legacy = try ModelContainer(for: Project.self, WorkSession.self,
                                        configurations: ModelConfiguration(url: url))
        let p = Project(name: "Richemont", client: "", mode: .hourly, hourlyRate: 120, currency: .chf)
        legacy.mainContext.insert(p)
        try legacy.mainContext.save()

        // Reopened the declared way, which is what every launch does now.
        let declared = try ModelContainer(for: Schema(versionedSchema: CutawaySchemaV1.self),
                                          migrationPlan: CutawayMigrationPlan.self,
                                          configurations: ModelConfiguration(url: url))
        let found = try declared.mainContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(found.map(\.name), ["Richemont"], "the owner's existing store must open unchanged")
    }
}
