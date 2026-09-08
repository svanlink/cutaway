import Foundation

/// The Swiss QR-bill payload — the 30-odd lines a bank's scanner reads.
///
/// Implemented to the Swiss Implementation Guidelines for the QR-bill
/// (v2.3, and unchanged in the fields below by v2.4). The payload is a
/// fixed ORDER of fields separated by CRLF; a field that does not apply is
/// still an empty line, because position is what identifies it. Get the
/// order wrong and the bill scans as a different bill.
///
/// Only the payload is generated here. It is deterministic, so it can be
/// tested exactly — which the visual layout cannot be, and which is why the
/// layout carries the warning it does in `InvoiceDocumentView`.
enum SwissQRBill {

    struct Address: Equatable {
        var name: String
        var street: String
        var buildingNumber: String
        var postalCode: String
        var town: String
        /// ISO 3166-1 alpha-2.
        var country: String

        /// "S" — structured. The combined form ("K") is being retired; new
        /// implementations are expected to use structured addresses.
        var structuredLines: [String] {
            [ "S", name, street, buildingNumber, postalCode, town, country ]
        }
    }

    /// Split a Swiss address block — street and number on one line, postcode
    /// and town on the next — into the structured fields the scheme requires.
    ///
    /// The payload carried an empty postal code and the street in the town
    /// field until 2026-09-08 — a bill that looks right on paper and is
    /// rejected by the scheme. Anything this cannot parse returns nil, and
    /// the caller prints no payment part at all: an invalid QR-bill is worse
    /// than none, because the client tries to pay it.
    static func address(name: String, block: String, country: String = "CH") -> Address? {
        let lines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                         .filter { !$0.isEmpty }
        guard lines.count >= 2, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // Last line: a postcode, a space, then a town.
        let townLine = lines[lines.count - 1]
        let townParts = townLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard townParts.count == 2, townParts[0].allSatisfy(\.isNumber) else { return nil }
        // Line before it: a street name, a space, then a number.
        let streetLine = lines[lines.count - 2]
        let streetParts = streetLine.split(separator: " ")
        guard streetParts.count >= 2, let number = streetParts.last,
              number.contains(where: \.isNumber) else { return nil }
        return Address(name: name,
                       street: streetParts.dropLast().joined(separator: " "),
                       buildingNumber: String(number),
                       postalCode: townParts[0],
                       town: townParts[1],
                       country: country)
    }

    enum ReferenceType: String {
        /// QR-IBAN with a 27-digit QR reference.
        case qrr = "QRR"
        /// Creditor Reference (ISO 11649).
        case scor = "SCOR"
        /// No reference — a plain IBAN.
        case non = "NON"
    }

    struct Refusal: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    /// CHF and EUR only — the scheme carries no other currency.
    static func assertSupported(_ currency: BillingCurrency) throws {
        guard currency == .chf || currency == .eur else {
            throw Refusal(what: String(localized: "A QR-bill can only be issued in CHF or EUR. This invoice is in \(currency.rawValue)."))
        }
    }

    /// Spaces are how humans write an IBAN and not how the payload carries it.
    static func normalisedIBAN(_ iban: String) -> String {
        iban.uppercased().filter { !$0.isWhitespace }
    }

    /// A Swiss or Liechtenstein IBAN, 21 characters, mod-97 valid.
    static func isValidIBAN(_ iban: String) -> Bool {
        let value = normalisedIBAN(iban)
        guard value.count == 21, value.hasPrefix("CH") || value.hasPrefix("LI") else { return false }
        // Move the first four characters to the end, letters become numbers,
        // and the whole thing mod 97 must be 1.
        let rearranged = String(value.dropFirst(4) + value.prefix(4))
        var remainder = 0
        for character in rearranged {
            let part: String
            if let digit = character.wholeNumberValue, character.isNumber {
                part = String(digit)
            } else if let ascii = character.asciiValue, character.isLetter {
                part = String(Int(ascii - 55))
            } else {
                return false
            }
            for digit in part {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    /// A QR-IBAN carries its institution id in positions 5–9, in 30000–31999.
    static func isQRIBAN(_ iban: String) -> Bool {
        let value = normalisedIBAN(iban)
        guard value.count == 21, let iid = Int(value.dropFirst(4).prefix(5)) else { return false }
        return (30_000...31_999).contains(iid)
    }

    /// The payload, in the order the specification fixes.
    ///
    /// `amount` is printed with a decimal point and two places, no grouping —
    /// the format the scheme requires, not a locale's idea of it.
    static func payload(iban: String,
                        creditor: Address,
                        amount: Decimal,
                        currency: BillingCurrency,
                        debtor: Address?,
                        referenceType: ReferenceType,
                        reference: String,
                        message: String) throws -> String {
        try assertSupported(currency)
        let account = normalisedIBAN(iban)
        guard isValidIBAN(account) else {
            throw Refusal(what: String(localized: "That IBAN is not a valid Swiss or Liechtenstein IBAN."))
        }
        if referenceType == .qrr && !isQRIBAN(account) {
            throw Refusal(what: String(localized: "A QR reference needs a QR-IBAN. Use a Creditor Reference or none."))
        }
        if referenceType != .qrr && isQRIBAN(account) {
            throw Refusal(what: String(localized: "A QR-IBAN requires a QR reference."))
        }

        var lines: [String] = []
        lines += ["SPC", "0200", "1"]              // header: type, version, coding
        lines += [account]
        lines += creditor.structuredLines          // creditor
        lines += Array(repeating: "", count: 7)    // ultimate creditor: reserved, always empty
        lines += [amountString(amount), currency.rawValue]
        lines += debtor?.structuredLines ?? Array(repeating: "", count: 7)
        lines += [referenceType.rawValue, reference]
        lines += [String(message.prefix(140))]
        lines += ["EPD"]                           // end of payment data
        return lines.joined(separator: "\r\n")
    }

    /// Two decimals, a point, no grouping — scheme format, not locale format.
    static func amountString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
    }

    /// An ISO 11649 Creditor Reference built from an invoice number: RF,
    /// two check digits, then the reference itself.
    static func creditorReference(from invoiceNumber: String) -> String {
        let body = invoiceNumber.uppercased().filter { $0.isLetter || $0.isNumber }
        let rearranged = body + "RF00"
        var remainder = 0
        for character in rearranged {
            let part: String
            if character.isNumber {
                part = String(character.wholeNumberValue ?? 0)
            } else if let ascii = character.asciiValue {
                part = String(Int(ascii - 55))
            } else { continue }
            for digit in part {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        let check = 98 - remainder
        return "RF" + String(format: "%02d", check) + body
    }
}
