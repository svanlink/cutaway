import Foundation
import SwiftData

enum BillingMode: String, Codable, Sendable {
    case hourly
    case budget
}

@Model
final class Project {
    var name: String
    var client: String
    var modeRaw: String
    var hourlyRate: Double
    var budget: Double
    var currencyRaw: String
    var createdAt: Date
    /// Bundle-id prefixes this project is worked in. Empty = use the global
    /// anchor list (legacy projects, and the fallback). See AnchorSet.
    var appBundleIDs: [String] = []
    /// The client's postal address, as it should appear on an invoice.
    ///
    /// `client` stays a String and is NEVER promoted to a `Client?`
    /// relationship: changing a property's TYPE is not a lightweight
    /// migration, and this store holds the only record of what the owner is
    /// owed. A second entity can be added later beside these fields; the
    /// fields themselves stay put.
    var clientAddress: String = ""
    var clientVATNumber: String = ""
    /// How this client is taxed. A fact about the relationship, not a setting.
    var taxModeRaw: String = TaxMode.notRegistered.rawValue

    var taxMode: TaxMode {
        get { TaxMode(rawValue: taxModeRaw) ?? .notRegistered }
        set { taxModeRaw = newValue.rawValue }
    }

    /// The block an invoice prints for this client: name, then address.
    var clientBlock: String {
        [client, clientAddress, clientVATNumber.isEmpty ? "" : "UID \(clientVATNumber)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
    @Relationship(deleteRule: .cascade, inverse: \WorkSession.project)
    var sessions: [WorkSession] = []

    var mode: BillingMode {
        get { BillingMode(rawValue: modeRaw) ?? .hourly }
        set { modeRaw = newValue.rawValue }
    }
    var currency: BillingCurrency {
        get { BillingCurrency(rawValue: currencyRaw) ?? .chf }
        set { currencyRaw = newValue.rawValue }
    }

    init(name: String, client: String, mode: BillingMode, hourlyRate: Double,
         budget: Double = 0, currency: BillingCurrency, appBundleIDs: [String] = []) {
        self.name = name
        self.client = client
        self.modeRaw = mode.rawValue
        self.hourlyRate = hourlyRate
        self.budget = budget
        self.currencyRaw = currency.rawValue
        self.createdAt = Date()
        self.appBundleIDs = appBundleIDs
    }
}

@Model
final class WorkSession {
    var start: Date
    var end: Date
    var activeSeconds: TimeInterval
    /// The rate in force when this work happened. Money already invoiced must
    /// not reprice because the project's rate changed later. 0 means a row
    /// written before this field existed — those fall back to the project
    /// rate, which is exactly the behaviour they were billed under.
    var hourlyRate: Double = 0
    /// True for a span that was TYPED, not tracked — the growth half of a day
    /// edit. Invoices may carry typed time; they may not hide it. Default so
    /// rows written before this field existed migrate as "tracked".
    var isAdjusted: Bool = false
    /// Stable identity, so an invoice line can name the sessions behind its
    /// figure without holding a relationship to them.
    ///
    /// A `String` defaulting to empty rather than `UUID = UUID()`: a SwiftData
    /// default is evaluated once for the migration, so every row that already
    /// exists would inherit the SAME uid — provenance that points at all of
    /// them and none of them. Empty means "not needed yet"; `ensureUID()`
    /// fills one in the first time a session is actually invoiced.
    var uid: String = ""
    /// The invoice this session is locked into. Non-empty = locked: its day
    /// cannot be edited, it cannot be deleted, and its rate cannot change.
    /// Denormalised so the guard is checkable without loading the invoice.
    var invoiceNumber: String = ""
    var project: Project?

    init(start: Date, end: Date, activeSeconds: TimeInterval,
         hourlyRate: Double, project: Project?, isAdjusted: Bool = false) {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.hourlyRate = hourlyRate
        self.project = project
        self.isAdjusted = isAdjusted
    }

    var isInvoiced: Bool { !invoiceNumber.isEmpty }

    /// Gives this session an identity if it does not have one yet.
    @discardableResult
    func ensureUID() -> String {
        if uid.isEmpty { uid = UUID().uuidString }
        return uid
    }

    /// What this session is worth, at the rate it was worked at.
    func earned(projectRate: Double) -> Double {
        BillingEngine.earnings(activeSeconds: activeSeconds,
                               hourlyRate: hourlyRate > 0 ? hourlyRate : projectRate)
    }
}

/// One row of the Daily Breakdown / CSV: a project's totals for one day.
/// `earned` is carried, not recomputed downstream, because the sessions
/// behind it may have been worked at different rates.
struct DayTotal: Equatable, Sendable {
    var day: Date            // startOfDay
    var activeSeconds: TimeInterval
    var sessionCount: Int
    var firstStart: Date
    var lastEnd: Date
    var earned: Double = 0
    /// Seconds of this day that were typed in, not tracked. Part of
    /// `activeSeconds`, never in addition to it.
    var adjustedSeconds: TimeInterval = 0

    /// The rate this day actually billed at — the blended rate when a day
    /// spans a rate change, so `hours × rate` always reconciles with `earned`.
    var effectiveRate: Double {
        activeSeconds > 0 ? earned / (activeSeconds / 3600) : 0
    }
}
