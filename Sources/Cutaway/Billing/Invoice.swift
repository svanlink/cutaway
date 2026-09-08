import Foundation
import SwiftData

enum InvoiceStatus: String, Codable, Sendable, CaseIterable {
    case draft, issued, paid, void
}

/// What a line on the invoice is FOR. Time is the only kind the app can
/// derive by itself; the rest are things a person decides and types.
enum InvoiceLineKind: String, Codable, Sendable {
    case time, dayRate, minimum, manual, deposit
}

/// A frozen document.
///
/// Every printed field is a COPY, never a reference: a view over live
/// sessions cannot survive a rate edit, a day correction, or the owner
/// moving from Zurich to Bogotá — and an invoice a client already holds must
/// not change when any of those happen. The client and supplier are text
/// blocks for the same reason.
///
/// The one thing that is NOT copied is provenance: each line carries the
/// UIDs of the sessions behind it, so the app can always answer "where did
/// this figure come from" and can detect when a document has drifted from
/// the work it describes. UIDs rather than a relationship, deliberately —
/// a relationship's inverse would pull live sessions back into the invoice
/// and drag invoices into every session fetch.
@Model
final class Invoice {
    /// INV-YYYY-NNNN. Allocated at issue, never reused, gapless within a year.
    var number: String = ""
    var statusRaw: String = InvoiceStatus.draft.rawValue
    var issueDate: Date = Date.distantPast
    var dueDate: Date = Date.distantPast
    var periodStart: Date = Date.distantPast
    var periodEnd: Date = Date.distantPast
    var currencyRaw: String = BillingCurrency.chf.rawValue
    var taxModeRaw: String = TaxMode.none.rawValue
    /// The rate that was in force when this was issued, copied. A VAT change
    /// next year must not restate a document from this one.
    var taxRate: Double = 0
    var supplierBlock: String = ""
    var clientBlock: String = ""
    var projectName: String = ""
    /// Stored as strings: SwiftData has no Decimal support, and a Double here
    /// would undo the exactness the lines were built with.
    var subtotalString: String = "0"
    var taxAmountString: String = "0"
    var totalString: String = "0"
    /// The zone the days were grouped in. A day is a local-calendar fact;
    /// without this, reopening the document elsewhere regroups it.
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var qrReference: String?
    /// The account the payment part prints. Copied like everything else on
    /// the page: changing bank must not restate a document already sent.
    var creditorIBAN: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
    var lines: [InvoiceLine] = []

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    var currency: BillingCurrency {
        get { BillingCurrency(rawValue: currencyRaw) ?? .chf }
        set { currencyRaw = newValue.rawValue }
    }
    var taxMode: TaxMode {
        get { TaxMode(rawValue: taxModeRaw) ?? .none }
        set { taxModeRaw = newValue.rawValue }
    }
    var subtotal: Decimal { Decimal(string: subtotalString) ?? 0 }
    var taxAmount: Decimal { Decimal(string: taxAmountString) ?? 0 }
    var total: Decimal { Decimal(string: totalString) ?? 0 }

    /// The lines in the order they are printed. A SwiftData relationship has
    /// no inherent order, so the document carries its own — anything that
    /// renders or checks an invoice must go through this, not `lines`.
    var orderedLines: [InvoiceLine] { lines.sorted { $0.sortIndex < $1.sortIndex } }

    /// Hours on this invoice that were typed rather than tracked. Drives the
    /// footnote — an invoice may carry typed time; it may not hide it.
    var adjustedHours: Decimal {
        lines.reduce(Decimal(0)) { $0 + (Decimal(string: $1.adjustedHoursString) ?? 0) }
    }

    init() {}
}

@Model
final class InvoiceLine {
    var kindRaw: String = InvoiceLineKind.time.rawValue
    /// The day this line bills, for time lines. Nil for a manual line.
    var day: Date?
    var text: String = ""
    var quantityString: String = "0"
    var unit: String = ""
    var unitPriceString: String = "0"
    var amountString: String = "0"
    var adjustedHoursString: String = "0"
    /// Provenance. Not a relationship — see Invoice.
    var sessionUIDs: [String] = []
    var sortIndex: Int = 0
    var invoice: Invoice?

    var kind: InvoiceLineKind {
        get { InvoiceLineKind(rawValue: kindRaw) ?? .time }
        set { kindRaw = newValue.rawValue }
    }
    var quantity: Decimal { Decimal(string: quantityString) ?? 0 }
    var unitPrice: Decimal { Decimal(string: unitPriceString) ?? 0 }
    var amount: Decimal { Decimal(string: amountString) ?? 0 }

    init() {}
}
