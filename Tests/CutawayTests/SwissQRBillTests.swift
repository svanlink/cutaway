import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import Cutaway

/// The payload is machine-read by a bank. Field ORDER is what identifies a
/// field — an extra or missing empty line shifts everything after it and the
/// bill scans as a different bill.
final class SwissQRBillTests: XCTestCase {

    /// A valid bill, with one thing varied per test.
    private func makePayload(amount: Decimal = Decimal(string: "1250.00")!,
                             creditorName: String = "Sebastian van Eickelen") throws -> String {
        try SwissQRBill.payload(
            iban: "CH5604835012345678009",
            creditor: SwissQRBill.Address(name: creditorName, street: "Bahnhofstrasse",
                                          buildingNumber: "1", postalCode: "8001",
                                          town: "Zürich", country: "CH"),
            amount: amount, currency: .chf, debtor: nil,
            referenceType: .non, reference: "", message: "Invoice INV-2026-0001")
    }


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

    func testAnAmountFormatsAsTheSchemeWants() {
        XCTAssertEqual(SwissQRBill.amountString(Decimal(string: "1000000")!), "1000000.00",
                       "no thousands separator, ever")
        XCTAssertEqual(SwissQRBill.amountString(Decimal(string: "0.01")!), "0.01")
    }

    /// The scheme's range is 0.01 to 999999999.99. A day under a minute of
    /// tracked time rounds to nothing, and if it is the only day in the
    /// period the bill carried "0.00" — which the validator rejects outright
    /// ("The provided amount is not valid"). Better to refuse to draw a
    /// payment part than to hand a client one their bank will not scan.
    func testAnAmountOutsideTheSchemesRangeIsRefused() {
        for amount in ["0", "0.001", "1000000000"] {
            XCTAssertThrowsError(try makePayload(amount: Decimal(string: amount)!),
                                 "\(amount) is outside the scheme's range and must be refused")
        }
        XCTAssertNoThrow(try makePayload(amount: Decimal(string: "0.01")!))
        XCTAssertNoThrow(try makePayload(amount: Decimal(string: "999999999.99")!))
    }

    /// macOS turns an apostrophe into U+2019 as you type, and the scheme
    /// permits no such character. The bill looks perfect and the bank's
    /// scanner refuses it — the validator's most common rejection.
    func testTypographicCharactersAreFoldedToWhatTheSchemePermits() throws {
        let payload = try makePayload(creditorName: "Sebastian\u{2019}s Studio \u{2014} Zürich")
        XCTAssertTrue(payload.contains("Sebastian's Studio - Zürich"),
                      "curly quote and em dash folded; the umlaut is permitted and stays")
        XCTAssertFalse(payload.contains("\u{2019}"))
        XCTAssertFalse(payload.contains("\u{2014}"))
    }

    /// A character with no ASCII equivalent cannot be silently dropped into
    /// a bill either — refuse, and say so.
    func testACharacterTheSchemeForbidsIsRefusedNotSmuggled() {
        XCTAssertThrowsError(try makePayload(creditorName: "Studio 東京"),
                             "an unmappable character must refuse, not ship a mangled name")
    }

    /// Field maxima from the implementation guidelines: Name 70, Street 70,
    /// BuildingNumber 16, PstCd 16, TwnNm 35, message 140.
    func testFieldsAreHeldToTheirMaximumLength() throws {
        let payload = try makePayload(creditorName: String(repeating: "a", count: 120))
        let lines = payload.components(separatedBy: "\r\n")
        for line in lines { XCTAssertLessThanOrEqual(line.count, 140, "over-long field: \(line.prefix(20))") }
        XCTAssertTrue(lines.contains(String(repeating: "a", count: 70)), "the name is cut at 70")
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

/// The printed geometry of the code itself.
///
/// IG v2.3 §6.4: "The measurements of the Swiss QR Code for printing must
/// always be 46 x 46 mm (without surrounding quiet space) regardless of the
/// Swiss QR Code version." Not a recommendation — a generation parameter.
final class SwissQRCodeGeometryTests: XCTestCase {

    private let pointsPerMM: CGFloat = 72.0 / 25.4

    /// CoreImage bakes a one-module quiet zone into its output. Scaling the
    /// whole thing into 46 mm printed the CODE at about 44.3 mm — undersized
    /// by 3.6%, and by a different amount for every payload length, since
    /// the module count grows with the data.
    func testTheCodeItselfMeasures46mmWhateverTheVersion() {
        let side = SwissQRCode.sideMM * pointsPerMM
        // 25 modules is the smallest QR version; 177 is the largest.
        for extent in [25, 33, 55, 63, 177].map(CGFloat.init) {
            let step = SwissQRCode.modulePoints(extentWidth: extent, sidePoints: side)
            let printedMM = (extent - 2) * step / pointsPerMM
            XCTAssertEqual(printedMM, SwissQRCode.sideMM, accuracy: 0.01,
                           "a \(Int(extent))-module image must still print 46 mm of code")
        }
    }

    /// And the generator really does bake in that border — if CoreImage ever
    /// stops, this test says so rather than the bill quietly growing.
    func testTheGeneratorStillBakesInAOneModuleQuietZone() throws {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("SPC\r\n0200\r\n1\r\nCH5604835012345678009".utf8)
        filter.correctionLevel = "M"
        let output = try XCTUnwrap(filter.outputImage)
        let modules = try XCTUnwrap(SwissQRCode.readModules(output))

        for i in 0..<modules.side {
            XCTAssertFalse(modules.isDark(i, 0), "top row is quiet zone")
            XCTAssertFalse(modules.isDark(i, modules.side - 1), "bottom row is quiet zone")
            XCTAssertFalse(modules.isDark(0, i), "left column is quiet zone")
            XCTAssertFalse(modules.isDark(modules.side - 1, i), "right column is quiet zone")
        }
        // A finder pattern sits at the top-left corner of the code proper.
        XCTAssertTrue(modules.isDark(1, 1), "the code starts one module in")
    }

    func testTheSwissCrossKeepsItsProportionToTheCode() {
        XCTAssertEqual(SwissQRCode.crossMM / SwissQRCode.sideMM, 7.0 / 46.0, accuracy: 0.0001,
                       "the cross is 7 mm of the code's 46, not of some other width")
    }
}
