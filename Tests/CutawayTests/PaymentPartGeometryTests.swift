import XCTest
import SwiftUI
@testable import Cutaway

/// The payment part's geometry is specified, not designed — so it is pinned
/// here rather than left to whatever a layout happens to produce.
///
/// IG v2.3 §3.1: "It is mandatory that the payment part must be positioned
/// on the lower edge of the QR-bill... The payment part and receipt together
/// come to the same length as the shorter side of DIN-A4 format." §3.3 fixes
/// the halves at 62 × 105 mm and 148 × 105 mm.
final class PaymentPartGeometryTests: XCTestCase {

    private var mm: CGFloat { PaymentPartView.mm }

    func testTheBillIsTheFullWidthOfTheSheet() {
        let widthMM = PaymentPartView.receiptWidthMM + PaymentPartView.paymentWidthMM
        XCTAssertEqual(widthMM, 210, "62 + 148 = the short side of A4")
        XCTAssertEqual(widthMM * mm, InvoiceDocumentView.pageSize.width, accuracy: 0.5,
                       "and that is exactly the page width — it cannot sit inside the margins")
    }

    func testTheBillIsFlushToTheLowerEdge() {
        // The page divides A4 by this number. If the invoice half were given
        // the whole page, or the bill were positioned with a Spacer, the bill
        // would not reach the edge — ImageRenderer proposes an unspecified
        // size, so flexible layout collapses to nothing and the bill ends up
        // printed over the invoice header.
        let invoiceHeight = InvoiceDocumentView.pageSize.height - PaymentPartView.totalHeight
        XCTAssertEqual(invoiceHeight + PaymentPartView.totalHeight,
                       InvoiceDocumentView.pageSize.height, accuracy: 0.01,
                       "the two blocks account for the whole sheet, with nothing left over")
        XCTAssertGreaterThan(invoiceHeight, 300, "and the invoice still has a usable page")
    }

    func testTheBillIs105mmTallPlusItsSeparationLine() {
        XCTAssertEqual(PaymentPartView.heightMM, 105)
        XCTAssertEqual(PaymentPartView.totalHeight,
                       PaymentPartView.separationHeight + 105 * mm, accuracy: 0.01,
                       "§3.7's instruction sits ABOVE the line, outside the bill's 105 mm")
    }

    func testTheMarginsAreTheOnesTheSchemeAsksFor() {
        XCTAssertEqual(PaymentPartView.marginMM, 5,
                       "§3.5 section spacing, §3.5.2 border around the code, both 5 mm")
    }

    /// §3.4: "Only the sans-serif fonts Arial, Frutiger, Helvetica and
    /// Liberation Sans are permitted in black." Font.system is SF Pro.
    func testTheBillUsesAPermittedFont() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Cutaway/Design/DesignTokens.swift"),
            encoding: .utf8)
        let qrBill = try XCTUnwrap(source.range(of: "enum QRBill {"))
        let block = String(source[qrBill.lowerBound...].prefix(900))
        XCTAssertTrue(block.contains("Helvetica"), "the bill's type must be a permitted face")
        XCTAssertFalse(block.contains("Font.system"), "SF Pro is not on the permitted list")
    }
}
