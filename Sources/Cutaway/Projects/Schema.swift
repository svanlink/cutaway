import Foundation
import SwiftData

/// Why this store's schema is INFERRED, not staged.
///
/// On 2026-09-08 a `VersionedSchema` + `SchemaMigrationPlan` was added here,
/// because an arbitration reasoned that adding the invoice entities to an
/// undeclared schema changes the store's identity with no origin to migrate
/// from. The reasoning was sound; the implementation was not, and running it
/// against a COPY of the owner's real store — before installing — is what
/// caught it:
///
///     CoreData: error 134504
///     "Cannot use staged migration with an unknown model version."
///
/// Two things were wrong, and both matter for whoever tries this next:
///
/// 1. `CutawaySchemaV1.models` pointed at `Project.self` and
///    `WorkSession.self` — the LIVE types, which by then had gained `uid`,
///    `invoiceNumber`, `clientAddress`, `taxModeRaw` and the rest. So "V1"
///    described today's shape, not what shipped. A real versioned schema
///    contains FROZEN copies of the old model definitions, nested inside it.
/// 2. Declaring a plan makes SwiftData REFUSE any store whose model version
///    it does not recognise — and every store written before the declaration
///    is exactly that. The owner's billing store, holding 51 hours of work,
///    would have failed to open and the app would have run in memory behind
///    a banner.
///
/// The unit test that was supposed to prevent this asserted the entity
/// NAMES ("Project", "WorkSession") and passed, because names were never
/// the thing that changed.
///
/// Inference has migrated every change this app has ever made — all of them
/// added properties with defaults, plus two new entities — and it accepts a
/// store it has never seen a declaration for. Doing versioning properly
/// means freezing the current shape as V1 *first*, on a build that still
/// opens the old stores, and only then adding V2. That is a deliberate piece
/// of work for the next schema change, not something to retrofit onto a
/// store that already exists.
///
/// Before any future change here: copy a real store and run
/// `RealStoreMigrationCheck` against the copy. It is the only check that
/// looks at the shape actually on disk.
enum CutawaySchemaNotes {}
