import XCTest
import SwiftData
import PDFKit
@testable import Cutaway

/// The PDF is the artefact a client actually receives — the thing that makes
/// "exactly how much to charge" checkable by someone other than the owner.
@MainActor
final class InvoicePDFTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!
    private var dir: URL!

    override func setUpWithError() throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { [dir] in if let dir { try? FileManager.default.removeItem(at: dir) } }
    }

    private func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    private func invoiceWithADay(taxMode: TaxMode = .notRegistered, vat: String = "") throws -> Invoice {
        let p = try store.createProject(name: "Atelier Presentation", client: "Aurora",
                                        mode: .hourly, hourlyRate: 120, currency: .chf)
        p.clientAddress = "Rue du Rhône 1\n1204 Genève"
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 13), activeSeconds: 14_400),
                         to: p, calendar: cal)
        return try store.issueInvoice(for: p, from: date(1, 0), to: date(30, 0),
                                      taxMode: taxMode,
                                      supplier: "Sebastian van Eickelen\nZürich",
                                      supplierVATNumber: vat,
                                      clientBlock: p.clientBlock,
                                      now: date(8, 10), calendar: cal)
    }

    func testItWritesARealPDF() throws {
        let invoice = try invoiceWithADay()
        let url = dir.appendingPathComponent("out.pdf")
        try InvoicePDF.write(invoice, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1_000, "a page with content, not an empty shell")
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
        // Vector, not a screenshot: a rasterised page carries an image XObject
        // and no font resources at all.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("/Font"), "text must stay text — a picture of an invoice is not an invoice")
    }

    /// Everything a Swiss invoice is judged on has to actually be on the page.
    func testThePageCarriesWhatAClientNeeds() throws {
        let invoice = try invoiceWithADay()
        let url = dir.appendingPathComponent("out.pdf")
        try InvoicePDF.write(invoice, to: url)
        let doc = try XCTUnwrap(pageText(url: url))

        XCTAssertTrue(doc.contains(invoice.number), "the invoice number")
        XCTAssertTrue(doc.contains("Aurora"), "the client")
        XCTAssertTrue(doc.contains("Sebastian"), "the supplier")
        XCTAssertTrue(doc.contains("480.00"), "4 h at 120 = 480.00")
    }

    func testTheFilenameNamesTheClientAndTheNumber() throws {
        let invoice = try invoiceWithADay()
        XCTAssertEqual(InvoicePDF.filename(for: invoice), "\(invoice.number) Aurora.pdf")
    }

    /// Under MWSTG Art. 27 stating a tax means owing it. A VAT invoice
    /// without a UID must not come into existence at all.
    func testAVATInvoiceWithoutAUIDIsRefused() throws {
        XCTAssertThrowsError(try invoiceWithADay(taxMode: .swissVAT, vat: "")) { error in
            XCTAssertTrue("\(error)".contains("UID"), "the refusal says what is missing")
        }
    }

    func testAVATInvoiceWithAUIDPrintsTheTax() throws {
        let invoice = try invoiceWithADay(taxMode: .swissVAT, vat: "CHE-123.456.789")
        XCTAssertEqual(invoice.taxRate, 8.1, accuracy: 0.001)
        XCTAssertEqual(invoice.subtotal, Decimal(string: "480.00"))
        XCTAssertEqual(invoice.taxAmount, Decimal(string: "38.88"), "480 × 8.1 %")
        XCTAssertEqual(invoice.total, Decimal(string: "518.88"))

        let url = dir.appendingPathComponent("vat.pdf")
        try InvoicePDF.write(invoice, to: url)
        let doc = try XCTUnwrap(pageText(url: url))
        XCTAssertTrue(doc.contains("518.88"), "the total the client pays")
    }

    /// A period too long for one page must say so, not crop a client's bill.
    func testTooManyLinesRefusesRatherThanCropping() throws {
        let p = try store.createProject(name: "Long", client: "C", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        for day in 1...(InvoicePDF.maxLinesPerPage + 2) {
            let d = cal.date(from: DateComponents(year: 2026, month: 7, day: day, hour: 9))!
            try store.record(SessionRecord(start: d, end: d.addingTimeInterval(3600), activeSeconds: 3600),
                             to: p, calendar: cal)
        }
        let from = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let to = cal.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let invoice = try store.issueInvoice(for: p, from: from, to: to, taxMode: .notRegistered,
                                             supplier: "S\nZürich", supplierVATNumber: "",
                                             clientBlock: "C", now: to, calendar: cal)
        XCTAssertThrowsError(try InvoicePDF.write(invoice, to: dir.appendingPathComponent("long.pdf")))
    }
}

/// The page's text as a reader's software would extract it.
///
/// Reading the raw bytes does NOT work — content streams are Flate-compressed,
/// so a grep finds only the metadata dictionary. That mistake made an early
/// version of these tests pass on the invoice number (metadata) while missing
/// the client name and the total (page content), which is exactly backwards.
private func pageText(url: URL) -> String? {
    PDFDocument(url: url)?.string
}

/// The payment part: the payload is exact and testable even though the
/// layout is not.
@MainActor
final class PaymentPartTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUpWithError() throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func project() throws -> Project {
        let p = try store.createProject(name: "Atelier", client: "Aurora",
                                        mode: .hourly, hourlyRate: 120, currency: .chf)
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))!
        try store.record(SessionRecord(start: start, end: start.addingTimeInterval(14_400),
                                       activeSeconds: 14_400), to: p, calendar: cal)
        return p
    }

    private func issue(_ p: Project, iban: String) throws -> Invoice {
        try store.issueInvoice(for: p, from: cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                               to: cal.date(from: DateComponents(year: 2026, month: 9, day: 30))!,
                               taxMode: .notRegistered,
                               supplier: "Sebastian van Eickelen\nBadenerstrasse 12\n8004 Zürich",
                               supplierVATNumber: "", clientBlock: p.clientBlock,
                               iban: iban, now: Date(), calendar: cal)
    }

    func testAnInvoiceWithAnIBANCarriesAReference() throws {
        let invoice = try issue(try project(), iban: "CH93 0076 2011 6238 5295 7")
        XCTAssertEqual(invoice.creditorIBAN, "CH9300762011623852957", "stored without spaces")
        XCTAssertTrue((invoice.qrReference ?? "").hasPrefix("RF"), "an ISO 11649 creditor reference")
    }

    /// Cutaway cannot invent a QR reference, so it refuses rather than
    /// printing a bill that bounces.
    func testAQRIBANIsRefusedWithAReason() throws {
        let p = try project()
        XCTAssertThrowsError(try issue(p, iban: "CH44 3199 9123 0008 8901 2")) { error in
            XCTAssertTrue("\(error)".contains("QR-IBAN"))
        }
    }

    func testAUSDInvoiceCannotCarryAPaymentPart() throws {
        let p = try store.createProject(name: "US", client: "C", mode: .hourly,
                                        hourlyRate: 100, currency: .usd)
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))!
        try store.record(SessionRecord(start: start, end: start.addingTimeInterval(3600),
                                       activeSeconds: 3600), to: p, calendar: cal)
        XCTAssertThrowsError(try issue(p, iban: "CH93 0076 2011 6238 5295 7"))
    }

    func testTheQRCodeIsGeneratedAtTheSpecifiedSize() throws {
        let invoice = try issue(try project(), iban: "CH93 0076 2011 6238 5295 7")
        let side = SwissQRCode.sideMM * PaymentPartView.mm
        let image = SwissQRCode.image(payload: "SPC\r\n0200\r\n1\r\n\(invoice.creditorIBAN)", sidePoints: side)
        let unwrapped = try XCTUnwrap(image)
        XCTAssertEqual(unwrapped.size.width, side, accuracy: 0.5, "46 mm at 72 dpi")
        XCTAssertEqual(unwrapped.size.height, side, accuracy: 0.5)
    }

    /// An address the scheme would reject prints NO payment part. A bill
    /// that looks right and cannot be paid is worse than no bill.
    func testAnUnparseableSupplierAddressPrintsNoPaymentPart() throws {
        let p = try project()
        let invoice = try store.issueInvoice(
            for: p, from: cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
            to: cal.date(from: DateComponents(year: 2026, month: 9, day: 30))!,
            taxMode: .notRegistered, supplier: "Sebastian\nZürich",
            supplierVATNumber: "", clientBlock: p.clientBlock,
            iban: "CH93 0076 2011 6238 5295 7", now: Date(), calendar: cal)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noqr-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try InvoicePDF.write(invoice, to: url)
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertFalse(text.contains("Payment part"),
                       "no structured address, no payment part")
    }

    func testThePaymentPartReachesThePage() throws {
        let invoice = try issue(try project(), iban: "CH93 0076 2011 6238 5295 7")
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qr-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try InvoicePDF.write(invoice, to: url)
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("Payment part"))
        XCTAssertTrue(text.contains("CH93 0076"), "the IBAN, grouped as a human reads it")
        XCTAssertTrue(text.contains(invoice.qrReference ?? "—"))
    }
}
