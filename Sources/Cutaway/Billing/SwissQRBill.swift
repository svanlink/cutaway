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
        /// Every field held to the scheme's character set and maximum. A
        /// bill that carries an impossible character is refused here rather
        /// than printed and handed to a client.
        func structuredLines() throws -> [String] {
            [ "S",
              try schemeText(name, max: 70, field: String(localized: "name")),
              try schemeText(street, max: 70, field: String(localized: "street")),
              try schemeText(buildingNumber, max: 16, field: String(localized: "building number")),
              try schemeText(postalCode, max: 16, field: String(localized: "postcode")),
              try schemeText(town, max: 35, field: String(localized: "town")),
              country ]
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

    /// The scheme's permitted character set, and what to do about the rest.
    ///
    /// IG v2.3 §4.1.1 allows Basic Latin (U+0020-U+007E), Latin-1 Supplement
    /// (U+00A0-U+00FF), Latin Extended-A (U+0100-U+017F), the four Romanian
    /// comma-below letters, and the euro sign. Nothing else — and macOS
    /// TextField turns an apostrophe into U+2019 and a double hyphen into an
    /// em dash as you type, so the owner's own name is the likeliest source
    /// of a character that makes a bank's scanner refuse the bill. The
    /// validator lists this as its most common rejection.
    ///
    /// Typography folds to its ASCII equivalent, because "Sebastian's" and
    /// "Sebastian's" are the same name. Anything left that the scheme does
    /// not permit REFUSES: silently deleting a character out of a payee's
    /// name on a payment instruction is worse than printing no bill.
    enum CharacterSet1 {
        static let folds: [Character: String] = [
            "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'",
            "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
            "\u{2013}": "-", "\u{2014}": "-", "\u{2015}": "-", "\u{2212}": "-",
            "\u{2026}": "...", "\u{00A0}": " ", "\u{202F}": " ", "\u{2009}": " ",
            "\u{2022}": "-", "\u{00AD}": "",
        ]

        static func permits(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x20...0x7E, 0xA0...0xFF, 0x100...0x17F: return true
            case 0x218, 0x219, 0x21A, 0x21B: return true   // Ș ș Ț ț
            case 0x20AC: return true                        // €
            default: return false
            }
        }
    }

    /// Folds what can be folded, refuses what cannot, and cuts to the field's
    /// maximum. `max` comes from IG §4.2.2: Name 70, Street 70,
    /// BuildingNumber 16, PstCd 16, TwnNm 35, unstructured message 140.
    static func schemeText(_ value: String, max: Int, field: String) throws -> String {
        var folded = ""
        for character in value {
            if let replacement = CharacterSet1.folds[character] {
                folded += replacement
            } else {
                folded.append(character)
            }
        }
        if let bad = folded.unicodeScalars.first(where: { !CharacterSet1.permits($0) }) {
            throw Refusal(what: String(localized: "The \(field) contains a character a QR-bill cannot carry (\(String(bad))). Use plain Latin text."))
        }
        return String(folded.prefix(max))
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

        // IG §4.2.2: the amount must be between 0.01 and 999999999.99. A
        // period holding only a sub-minute day rounds to nothing, and "0.00"
        // is rejected outright by the scheme — a bill nobody can pay.
        guard amount >= Decimal(string: "0.01")!, amount <= Decimal(string: "999999999.99")! else {
            throw Refusal(what: String(localized: "A QR-bill must be for at least 0.01 and at most 999999999.99. This invoice is for \(amountString(amount))."))
        }

        var lines: [String] = []
        lines += ["SPC", "0200", "1"]              // header: type, version, coding
        lines += [account]
        lines += try creditor.structuredLines()    // creditor
        lines += Array(repeating: "", count: 7)    // ultimate creditor: reserved, always empty
        lines += [amountString(amount), currency.rawValue]
        lines += try debtor?.structuredLines() ?? Array(repeating: "", count: 7)
        lines += [referenceType.rawValue, reference]
        lines += [try schemeText(message, max: 140, field: String(localized: "message"))]
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
