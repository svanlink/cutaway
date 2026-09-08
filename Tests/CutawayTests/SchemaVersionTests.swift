import XCTest
import SwiftData
@testable import Cutaway

/// The store must open stores it has already written — including the ones
/// written before anybody thought about versioning.
///
/// The previous version of this file asserted that a versioned schema
/// declared the entity NAMES "Project" and "WorkSession", and passed while
/// the app was one install away from refusing to open the owner's real
/// store. Names were never the thing that changed. See Schema.swift.
@MainActor
final class SchemaVersionTests: XCTestCase {

    /// A guard, in the style of DesignTokenGuardTests: a staged migration
    /// plan rejects every store whose version it does not know, which is
    /// every store that predates the plan.
    func testTheContainerDoesNotUseAStagedMigrationPlan() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Cutaway/Projects/SessionStore.swift"),
                                encoding: .utf8)
        XCTAssertFalse(source.contains("migrationPlan:"),
                       """
                       A declared plan makes SwiftData refuse stores it cannot
                       version — the owner's included. If you are adding one,
                       freeze the CURRENT shape as V1 in its own nested types
                       first, and prove it against a copy of a real store with
                       RealStoreMigrationCheck.
                       """)
    }

    /// The entities the container must carry, or an invoice cannot be saved.
    func testTheContainerCarriesEveryEntity() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        XCTAssertNoThrow(try store.context.save())
        let invoice = Invoice()
        invoice.number = "INV-2026-0001"
        invoice.projectName = p.name
        store.context.insert(invoice)
        XCTAssertNoThrow(try store.context.save(), "Invoice must be part of the container's schema")
        XCTAssertEqual(try store.invoices().count, 1)
    }

    /// A store written by the shape that shipped still opens today. This is
    /// the weaker cousin of RealStoreMigrationCheck — it can only build a
    /// store from the CURRENT types, which is exactly the blind spot that
    /// let the staged-migration bug through. Kept, but not trusted alone.
    func testAStoreWrittenByAnUndeclaredSchemaStillOpens() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("billing.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let legacy = try ModelContainer(for: Project.self, WorkSession.self,
                                            configurations: ModelConfiguration(url: url))
            legacy.mainContext.insert(Project(name: "Richemont", client: "", mode: .hourly,
                                              hourlyRate: 120, currency: .chf))
            try legacy.mainContext.save()
        }
        let reopened = try SessionStore(inMemory: false, url: url)
        XCTAssertEqual(try reopened.projects().map(\.name), ["Richemont"])
    }
}
