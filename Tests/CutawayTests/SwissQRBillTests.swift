import XCTest
@testable import Cutaway

/// The payload is machine-read by a bank. Field ORDER is what identifies a
/// field — an extra or missing empty line shifts everything after it and the
/// bill scans as a different bill.
final class SwissQRBillTests: XCTestCase {

    private let creditor = SwissQRBill.Address(
        name: "Sebastian van Eickelen", street: "Badenerstrasse", buildingNumber: "12",
        postalCode: "8004", town: "Zürich", country: "CH")
    private let debtor = SwissQRBill.Address(
        name: "Richemont EC", street: "Route des Biches", buildingNumber: "10",
        postalCode: "1752", town: "Villars-sur-Glâne", country: "CH")

    /// A real published example IBAN from the scheme's own documentation.
    private let iban = "CH44 3199 9123 0008 8901 2"

    func testTheHeaderIsExactlyWhatAScannerExpects() throws {
        let payload = try SwissQRBill.payload(
            iban: iban, creditor: creditor, amount: Decimal(string: "518.88")!,
            currency: .chf, debtor: debtor, referenceType: .qrr,
            reference: "210000000003139471430009017", message: "INV-2026-0001")
        let lines = payload.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "SPC")
        XCTAssertEqual(lines[1], "0200", "version 2")
        XCTAssertEqual(lines[2], "1", "UTF-8")
        XCTAssertEqual(lines[3], "CH4431999123000889012", "spaces are how humans write it")
        XCTAssertEqual(lines[4], "S", "structured address")
        XCTAssertEqual(lines[5], "Sebastian van Eickelen")
        XCTAssertEqual(lines[11], "", "ultimate creditor is reserved and stays empty")
    }

    /// The seven reserved lines are load-bearing: drop them and the amount
    /// lands where the scanner looks for an address.
    func testTheAmountAndCurrencyLandInTheirFixedPositions() throws {
        let payload = try SwissQRBill.payload(
            iban: iban, creditor: creditor, amount: Decimal(string: "1234.5")!,
            currency: .chf, debtor: debtor, referenceType: .qrr,
            reference: "210000000003139471430009017", message: "")
        let lines = payload.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[18], "1234.50", "two places, a point, no grouping")
        XCTAssertEqual(lines[19], "CHF")
        XCTAssertEqual(lines.last, "EPD")
    }

    func testAnUnpaidAmountFormatsAsTheSchemeWants() {
        XCTAssertEqual(SwissQRBill.amountString(Decimal(string: "0")!), "0.00")
        XCTAssertEqual(SwissQRBill.amountString(Decimal(string: "1000000")!), "1000000.00",
                       "no thousands separator, ever")
    }

    func testIBANValidation() {
        XCTAssertTrue(SwissQRBill.isValidIBAN(iban))
        XCTAssertTrue(SwissQRBill.isValidIBAN("CH9300762011623852957"))
        XCTAssertFalse(SwissQRBill.isValidIBAN("CH9300762011623852958"), "one digit off fails mod-97")
        XCTAssertFalse(SwissQRBill.isValidIBAN("DE89370400440532013000"), "not a Swiss scheme")
    }

    func testAQRIBANIsRecognisedByItsInstitutionNumber() {
        XCTAssertTrue(SwissQRBill.isQRIBAN(iban), "31999 is inside the QR-IID range")
        XCTAssertFalse(SwissQRBill.isQRIBAN("CH9300762011623852957"), "00762 is an ordinary IID")
    }

    /// The two ways to get this wrong, both refused rather than printed.
    func testReferenceTypeMustMatchTheIBAN() {
        XCTAssertThrowsError(try SwissQRBill.payload(
            iban: "CH9300762011623852957", creditor: creditor, amount: 10, currency: .chf,
            debtor: nil, referenceType: .qrr, reference: "1", message: ""))
        XCTAssertThrowsError(try SwissQRBill.payload(
            iban: iban, creditor: creditor, amount: 10, currency: .chf,
            debtor: nil, referenceType: .non, reference: "", message: ""))
    }

    func testOnlyCHFAndEUR() {
        XCTAssertThrowsError(try SwissQRBill.assertSupported(.usd))
        XCTAssertThrowsError(try SwissQRBill.assertSupported(.cop))
        XCTAssertNoThrow(try SwissQRBill.assertSupported(.chf))
        XCTAssertNoThrow(try SwissQRBill.assertSupported(.eur))
    }

    /// A missing debtor is seven empty lines, not zero — an invoice the payer
    /// fills in themselves is normal, and the positions after it must hold.
    func testAnAbsentDebtorStillOccupiesItsLines() throws {
        let withDebtor = try SwissQRBill.payload(
            iban: iban, creditor: creditor, amount: 10, currency: .chf, debtor: debtor,
            referenceType: .qrr, reference: "210000000003139471430009017", message: "")
        let without = try SwissQRBill.payload(
            iban: iban, creditor: creditor, amount: 10, currency: .chf, debtor: nil,
            referenceType: .qrr, reference: "210000000003139471430009017", message: "")
        XCTAssertEqual(withDebtor.components(separatedBy: "\r\n").count,
                       without.components(separatedBy: "\r\n").count)
    }

    /// ISO 11649 check digits, so a bank accepts the reference.
    func testCreditorReferenceCheckDigits() {
        let reference = SwissQRBill.creditorReference(from: "INV-2026-0001")
        XCTAssertTrue(reference.hasPrefix("RF"))
        XCTAssertEqual(reference.dropFirst(4), "INV20260001", "punctuation is not part of a reference")
        // Round-trip: a valid RF reference passes the same mod-97 test as an IBAN.
        let rearranged = reference.dropFirst(4) + reference.prefix(4)
        var remainder = 0
        for character in rearranged {
            let part = character.isNumber ? String(character.wholeNumberValue ?? 0)
                                          : String(Int((character.asciiValue ?? 65) - 55))
            for digit in part { remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97 }
        }
        XCTAssertEqual(remainder, 1, "the check digits must validate")
    }
}
