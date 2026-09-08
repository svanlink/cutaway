import SwiftUI

/// The payment part at the foot of a Swiss invoice.
///
/// The geometry here is specified, not designed. IG v2.3 §3.1: "It is
/// mandatory that the payment part must be positioned on the lower edge of
/// the QR-bill... The payment part and receipt together come to the same
/// length as the shorter side of DIN-A4 format." §3.3 fixes the two halves
/// at 62 × 105 mm and 148 × 105 mm, giving 210 × 105 mm flush to the bottom.
///
/// It used to inherit the page's 56 pt padding, which made it 170 mm wide
/// floating 20 mm above the edge — a block that reads as a QR-bill, is not
/// one, and that a client will try to pay.
///
/// This is a faithful arrangement of the required elements at the required
/// sizes. It is still not a certified one: only the scheme's own validator
/// can answer that, and `InvoiceSheet` says so before printing.
struct PaymentPartView: View {
    let invoice: Invoice
    let payload: String
    let iban: String
    let reference: String

    /// 1 mm at 72 dpi.
    static let mm: CGFloat = 72.0 / 25.4

    /// §3.3. The receipt, the payment part, and the two together.
    static let receiptWidthMM: CGFloat = 62
    static let paymentWidthMM: CGFloat = 148
    static let heightMM: CGFloat = 105
    /// §3.5 and §3.6: a 5 mm margin inside each half, and §3.5.2's unprinted
    /// border around the code.
    static let marginMM: CGFloat = 5
    /// The separation instruction and its line, above the bill and outside it.
    static let separationHeight: CGFloat = 11

    /// What the whole block occupies on the sheet.
    ///
    /// Published because the page has to divide A4 by an exact number:
    /// ImageRenderer proposes an UNSPECIFIED size, so `Spacer` and
    /// `maxHeight: .infinity` both collapse to nothing and every attempt to
    /// push this to the foot of the page silently left it at the top,
    /// overlapping the invoice. Nothing here may depend on a flexible
    /// proposal.
    static var totalHeight: CGFloat { separationHeight + heightMM * mm }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // §3.7: for a QR-bill delivered as a PDF, each separation line
            // must carry the scissors symbol or the instruction, ABOVE the
            // line and outside the payment part.
            Text("✂ Separate before paying in")
                .font(DT.QRBill.separationNote)
                .padding(.leading, Self.marginMM * Self.mm)
                .frame(height: Self.separationHeight - 2, alignment: .bottom)
            Rectangle().fill(Color.black).frame(height: 0.5)
            HStack(alignment: .top, spacing: 0) {
                receipt
                    .frame(width: Self.receiptWidthMM * Self.mm,
                           height: Self.heightMM * Self.mm, alignment: .topLeading)
                Rectangle().fill(Color.black).frame(width: 0.5)
                payment
                    .frame(width: Self.paymentWidthMM * Self.mm - 0.5,
                           height: Self.heightMM * Self.mm, alignment: .topLeading)
            }
        }
        .frame(width: (Self.receiptWidthMM + Self.paymentWidthMM) * Self.mm,
               height: Self.totalHeight, alignment: .top)
    }

    // MARK: - Receipt (62 mm)

    private var receipt: some View {
        VStack(alignment: .leading, spacing: Self.marginMM * Self.mm) {
            Text("Receipt").font(DT.QRBill.title)
            VStack(alignment: .leading, spacing: 3) {
                block(String(localized: "Account / Payable to"),
                      [iban, invoice.supplierBlock].joined(separator: "\n"), receipt: true)
                if !reference.isEmpty {
                    block(String(localized: "Reference"), reference, receipt: true)
                }
                block(String(localized: "Payable by"), invoice.clientBlock, receipt: true)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                labelled(String(localized: "Currency"), invoice.currency.rawValue, receipt: true)
                labelled(String(localized: "Amount"),
                         SwissQRBill.amountString(invoice.total), receipt: true)
            }
            // §3.6.4. Right-aligned, and the scheme reserves at least 2 cm of
            // height for the bank to stamp. Blank by design — the heading is
            // the whole of it.
            Text("Acceptance point")
                .font(DT.QRBill.receiptHeading)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 20 * Self.mm - 8)
        }
        .padding(Self.marginMM * Self.mm)
    }

    // MARK: - Payment part (148 mm)

    private var payment: some View {
        HStack(alignment: .top, spacing: Self.marginMM * Self.mm) {
            VStack(alignment: .leading, spacing: Self.marginMM * Self.mm) {
                Text("Payment part").font(DT.QRBill.title)
                if let qr = SwissQRCode.image(payload: payload,
                                              sidePoints: SwissQRCode.sideMM * Self.mm) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .frame(width: SwissQRCode.sideMM * Self.mm,
                               height: SwissQRCode.sideMM * Self.mm)
                        // §3.5.2: an unprinted border around the code. The
                        // ISO floor is 4 modules (~1.6 mm); the scheme asks
                        // for 5 mm and that is what a scanner is given.
                        .padding(Self.marginMM * Self.mm)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    labelled(String(localized: "Currency"), invoice.currency.rawValue, receipt: false)
                    labelled(String(localized: "Amount"),
                             SwissQRBill.amountString(invoice.total), receipt: false)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 51 * Self.mm, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                block(String(localized: "Account / Payable to"),
                      [iban, invoice.supplierBlock].joined(separator: "\n"), receipt: false)
                if !reference.isEmpty {
                    block(String(localized: "Reference"), reference, receipt: false)
                }
                block(String(localized: "Additional information"), invoice.number, receipt: false)
                block(String(localized: "Payable by"), invoice.clientBlock, receipt: false)
                Spacer(minLength: 0)
            }
        }
        .padding(Self.marginMM * Self.mm)
    }

    // MARK: - Elements

    private func block(_ title: String, _ value: String, receipt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(receipt ? DT.QRBill.receiptHeading : DT.QRBill.paymentHeading)
            Text(value).font(receipt ? DT.QRBill.receiptValue : DT.QRBill.paymentValue)
        }
    }

    private func labelled(_ title: String, _ value: String, receipt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(receipt ? DT.QRBill.receiptHeading : DT.QRBill.paymentHeading)
            Text(value).font(receipt ? DT.QRBill.receiptValue : DT.QRBill.paymentValue)
        }
    }
}
