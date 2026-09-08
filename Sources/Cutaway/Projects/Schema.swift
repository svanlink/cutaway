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

/// The order the app has ever stored data in. Append; never reorder.
enum CutawayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CutawaySchemaV1.self] }

    /// Empty on purpose. Every change so far has been an added property with
    /// a default, which SwiftData migrates on its own. The plan exists so the
    /// NEXT change — the one that cannot be lightweight — has somewhere to go.
    static var stages: [MigrationStage] { [] }
}
