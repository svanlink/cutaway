import Foundation

/// Who is sending the invoice. One person, so it lives in preferences rather
/// than in the store — but it is COPIED onto every invoice at issue, because
/// a document must not restate itself when an address changes.
struct Supplier: Equatable, Sendable {
    var name: String
    var address: String
    var vatNumber: String
    var iban: String

    static var current: Supplier {
        Supplier(name: Prefs.string(forKey: "supplierName") ?? "",
                 address: Prefs.string(forKey: "supplierAddress") ?? "",
                 vatNumber: Prefs.string(forKey: "supplierVAT") ?? "",
                 iban: Prefs.string(forKey: "supplierIBAN") ?? "")
    }

    func save() {
        Prefs.set(name, forKey: "supplierName")
        Prefs.set(address, forKey: "supplierAddress")
        Prefs.set(vatNumber, forKey: "supplierVAT")
        Prefs.set(iban, forKey: "supplierIBAN")
    }

    /// Name, address, then UID — the block as it prints.
    var block: String {
        [name, address, vatNumber.isEmpty ? "" : "UID \(vatNumber)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    /// An invoice needs a sender. Says which part is missing rather than
    /// producing a document with a blank corner.
    var missingForInvoice: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "An invoice needs your name — fill in the From block above.")
        }
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "An invoice needs your postal address — fill in the From block above.")
        }
        return nil
    }
}
