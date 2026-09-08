import Foundation
import SwiftData

/// The store's declared schema history.
///
/// This exists BEFORE the invoice entities, and that order is not a
/// preference. `ModelContainer(for:)` derives an implicit schema identity
/// from whatever types it is handed; add two entities to an undeclared
/// schema and the store's identity changes with no origin to migrate from.
/// A `SchemaV1` declared afterwards has nothing to migrate *out of*, so the
/// only path left is `SessionStore()` throwing into the in-memory fallback —
/// which means `storeIsEphemeral`, a banner someone misses while a render
/// runs, and a day of billing into RAM. Roughly twenty-five lines, and no
/// second chance at them.
enum CutawaySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Project.self, WorkSession.self] }
}

/// V2 adds the invoice document. Project and WorkSession gain properties with
/// defaults, which is a lightweight change; Invoice and InvoiceLine are new
/// entities, which is also lightweight. The stage is declared anyway, so the
/// store carries an explicit record of when the shape changed.
enum CutawaySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Project.self, WorkSession.self, Invoice.self, InvoiceLine.self]
    }
}

/// The order the app has ever stored data in. Append; never reorder.
enum CutawayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CutawaySchemaV1.self, CutawaySchemaV2.self] }

    /// Lightweight: every V1→V2 change is an added property with a default or
    /// a new entity. The stage exists so the first change that ISN'T has
    /// somewhere to go, and so the store records that this one happened.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CutawaySchemaV1.self, toVersion: CutawaySchemaV2.self)]
    }
}
