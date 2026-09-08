import SwiftUI

/// The payment part at the foot of a Swiss invoice.
///
/// The payload inside the QR code is exact and tested. This LAYOUT is a
/// faithful arrangement of the required elements, not a certified one: the
/// specification fixes millimetre positions, type sizes and a perforation
/// line, and none of that can be proven by a unit test. The app says so
/// before it prints one — see `InvoiceSheet` — and points at the scheme's
/// own validator, which is the only thing that can answer the question.
struct PaymentPartView: View {
    let invoice: Invoice
    let payload: String
    let iban: String
    let reference: String

    /// 1 mm at 72 dpi.
    static let mm: CGFloat = 72.0 / 25.4

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            receipt
                .frame(width: 62 * Self.mm)
            Rectangle().fill(Color.black.opacity(0.3)).frame(width: 0.5)
            payment
                .padding(.leading, 5 * Self.mm)
        }
        .frame(height: 105 * Self.mm)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.5)
        }
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Receipt").font(DT.Page.number)
            block(String(localized: "Account / Payable to"),
                  [iban, invoice.supplierBlock].joined(separator: "\n"))
            if !reference.isEmpty { block(String(localized: "Reference"), reference) }
            block(String(localized: "Payable by"), invoice.clientBlock)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                labelled(String(localized: "Currency"), invoice.currency.rawValue)
                labelled(String(localized: "Amount"), SwissQRBill.amountString(invoice.total))
            }
        }
        .padding(.trailing, 5 * Self.mm)
    }

    private var payment: some View {
        HStack(alignment: .top, spacing: 5 * Self.mm) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Payment part").font(DT.Page.number)
                if let qr = SwissQRCode.image(payload: payload,
                                              sidePoints: SwissQRCode.sideMM * Self.mm) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .frame(width: SwissQRCode.sideMM * Self.mm,
                               height: SwissQRCode.sideMM * Self.mm)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    labelled(String(localized: "Currency"), invoice.currency.rawValue)
                    labelled(String(localized: "Amount"), SwissQRBill.amountString(invoice.total))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                block(String(localized: "Account / Payable to"),
                      [iban, invoice.supplierBlock].joined(separator: "\n"))
                if !reference.isEmpty { block(String(localized: "Reference"), reference) }
                block(String(localized: "Additional information"), invoice.number)
                block(String(localized: "Payable by"), invoice.clientBlock)
                Spacer(minLength: 0)
            }
        }
    }

    private func block(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DT.Page.columnHeader)
            Text(value).font(DT.Page.note)
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DT.Page.columnHeader)
            Text(value).font(DT.Page.note)
        }
    }
}
