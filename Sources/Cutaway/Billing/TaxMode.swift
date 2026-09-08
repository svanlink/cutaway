import Foundation

/// How a client is taxed. Not a preference — a fact about a business
/// relationship, and in Switzerland a legally consequential one.
///
/// Under MWSTG Art. 27 a person who is NOT registered for VAT may not state
/// a tax amount on an invoice: stating it means owing it, registered or not.
/// So `notRegistered` is the only mode that can produce a document with no
/// tax line, and no mode may produce a tax line without a UID to print
/// beside it. That is enforced in `canIssue`, not left to a checkbox.
enum TaxMode: String, Codable, Sendable, CaseIterable {
    /// Below the CHF 100'000 threshold and not voluntarily registered.
    case notRegistered
    /// Swiss VAT at the standard rate, with a UID.
    case swissVAT
    /// EU business client: the client accounts for the tax, not the supplier.
    case euReverseCharge
    /// Outside the scope — a client with no Swiss or EU tax consequence.
    case none

    /// The rate this mode prints. Copied onto the invoice at issue so a
    /// future rate change cannot restate an old document.
    static let swissStandardRate = 8.1

    var rate: Double { self == .swissVAT ? Self.swissStandardRate : 0 }

    /// Does an invoice in this mode show a tax LINE at all?
    var showsTaxLine: Bool { self == .swissVAT }

    /// The sentence the law expects on the page.
    var note: String {
        switch self {
        case .notRegistered:
            return String(localized: "No VAT — not registered for Swiss VAT (below the CHF 100'000 threshold).")
        case .swissVAT:
            return String(localized: "Swiss VAT at \(String(format: "%.1f", Self.swissStandardRate)) %.")
        case .euReverseCharge:
            return String(localized: "Reverse charge — VAT to be accounted for by the recipient.")
        case .none:
            return ""
        }
    }

    /// Refuses to let a document exist that would state a tax the owner does
    /// not owe, or claim a registration they do not have.
    func issueRefusal(supplierVATNumber: String) -> String? {
        switch self {
        case .swissVAT where supplierVATNumber.trimmingCharacters(in: .whitespaces).isEmpty:
            return String(localized: "A Swiss VAT invoice must print your UID. Add it in Settings, or choose a different tax mode.")
        case .euReverseCharge where supplierVATNumber.trimmingCharacters(in: .whitespaces).isEmpty:
            return String(localized: "A reverse-charge invoice must print your UID alongside the client's.")
        default:
            return nil
        }
    }
}
