import SwiftUI

/// The page a client receives.
///
/// Deliberately plain, deliberately light: this is the one surface that
/// leaves the Mac, so it follows the conventions of a business document
/// rather than the app's dark instrument styling. No blur, no shadow, no
/// material — `ImageRenderer` rasterises anything it cannot express as
/// vectors, and a rasterised invoice is a picture of a document rather than
/// a document.
struct InvoiceDocumentView: View {
    let invoice: Invoice
    /// A4 at 72 dpi.
    static let pageSize = CGSize(width: 595.2, height: 841.8)

    private var currency: BillingCurrency { invoice.currency }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            parties
            table
            totals
            notes
            Spacer(minLength: 0)
            if !invoice.creditorIBAN.isEmpty, let payload = qrPayload {
                PaymentPartView(invoice: invoice, payload: payload,
                                iban: formattedIBAN, reference: invoice.qrReference ?? "")
            }
        }
        .padding(56)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.supplierBlock)
                    .font(DT.Page.meta)
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // A ternary of two string literals resolves to String, which is
                // VERBATIM — it never reaches the String Catalog. Two Texts do.
                (invoice.status == .void ? Text("VOID") : Text("INVOICE"))
                    .font(DT.Page.title)
                    .foregroundStyle(invoice.status == .void ? Color.red : Color.black)
                Text(invoice.number).font(DT.Page.number)
                Text(dateLine).font(DT.Page.meta).foregroundStyle(Color.black.opacity(0.7))
            }
        }
    }

    private var dateLine: String {
        let issued = invoice.issueDate.formatted(.dateTime.day().month(.abbreviated).year())
        let due = invoice.dueDate.formatted(.dateTime.day().month(.abbreviated).year())
        return String(localized: "Issued \(issued) · due \(due)")
    }

    private var parties: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Billed to").font(DT.Page.columnHeader)
                .foregroundStyle(Color.black.opacity(0.5))
            Text(invoice.clientBlock).font(DT.Page.party)
            if !invoice.projectName.isEmpty {
                Text(invoice.projectName).font(DT.Page.meta)
                    .foregroundStyle(Color.black.opacity(0.7))
                    .padding(.top, 6)
            }
            Text(periodLine).font(DT.Page.meta).foregroundStyle(Color.black.opacity(0.7))
        }
    }

    private var periodLine: String {
        let from = invoice.periodStart.formatted(.dateTime.day().month(.abbreviated))
        let to = invoice.periodEnd.formatted(.dateTime.day().month(.abbreviated).year())
        return String(localized: "Work from \(from) to \(to)")
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Day").frame(maxWidth: .infinity, alignment: .leading)
                Text("Hours").frame(width: 60, alignment: .trailing)
                Text("Rate").frame(width: 70, alignment: .trailing)
                Text("Amount").frame(width: 80, alignment: .trailing)
            }
            .font(DT.Page.columnHeader)
            .foregroundStyle(Color.black.opacity(0.5))
            .padding(.bottom, 4)
            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 0.5)

            ForEach(invoice.orderedLines, id: \.persistentModelID) { line in
                HStack {
                    HStack(spacing: 4) {
                        Text(line.text)
                        // Typed time is disclosed on the row it is in, not
                        // only in a footnote a reader can skip.
                        if (Decimal(string: line.adjustedHoursString) ?? 0) > 0 {
                            Text("†").foregroundStyle(Color.black.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(line.kind == .time ? Self.clockHours(line.quantity) : "")
                        .frame(width: 60, alignment: .trailing)
                    Text(line.kind == .time ? amount(line.unitPrice) : "")
                        .frame(width: 70, alignment: .trailing)
                    Text(amount(line.amount)).frame(width: 80, alignment: .trailing)
                }
                .font(DT.Page.row)
                .padding(.vertical, 3)
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5)
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .trailing, spacing: 3) {
            row(String(localized: "Subtotal"), invoice.subtotal, weight: .regular)
            if invoice.taxMode.showsTaxLine {
                row(String(localized: "VAT \(String(format: "%.1f", invoice.taxRate)) %"),
                    invoice.taxAmount, weight: .regular)
            }
            Rectangle().fill(Color.black.opacity(0.25)).frame(width: 220, height: 0.5)
            row(String(localized: "Total"), invoice.total, weight: .semibold)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func row(_ label: String, _ value: Decimal, weight: Font.Weight) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .trailing)
            Text(amount(value)).frame(width: 80, alignment: .trailing)
        }
        .font(weight == .semibold ? DT.Page.totalLead : DT.Page.row)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !invoice.taxMode.note.isEmpty {
                Text(invoice.taxMode.note).font(DT.Page.note)
            }
            if invoice.adjustedHours > 0 {
                // The honesty rule, printed where a client reads it.
                Text("† \(hours(invoice.adjustedHours)) h on this invoice were entered by hand rather than tracked automatically.")
                    .font(DT.Page.note)
            }
            if let reference = invoice.qrReference, !reference.isEmpty {
                Text(String(localized: "Reference \(reference)")).font(DT.Page.note)
            }
        }
        .foregroundStyle(Color.black.opacity(0.7))
    }

    /// Built from the SAME frozen fields the page prints, so the code and
    /// the text beside it can never disagree.
    private var qrPayload: String? {
        // Structured addresses, parsed from the blocks that are printed above
        // — and no payment part at all when they cannot be parsed. The
        // scheme requires a postal code and a street; guessing at them
        // produced a bill that looked right and would be refused.
        guard let creditor = SwissQRBill.address(name: line(invoice.supplierBlock, 0),
                                                 block: invoice.supplierBlock) else { return nil }
        let debtor = SwissQRBill.address(name: line(invoice.clientBlock, 0),
                                         block: invoice.clientBlock)
        return try? SwissQRBill.payload(iban: invoice.creditorIBAN, creditor: creditor,
                                        amount: invoice.total, currency: invoice.currency,
                                        debtor: debtor, referenceType: .scor,
                                        reference: invoice.qrReference ?? "",
                                        message: invoice.number)
    }

    private func line(_ block: String, _ index: Int) -> String {
        let parts = block.split(separator: "\n").map(String.init)
        return index < parts.count ? parts[index] : ""
    }

    /// IBANs are read in fours by humans.
    private var formattedIBAN: String {
        stride(from: 0, to: invoice.creditorIBAN.count, by: 4).map {
            let start = invoice.creditorIBAN.index(invoice.creditorIBAN.startIndex, offsetBy: $0)
            let end = invoice.creditorIBAN.index(start, offsetBy: min(4, invoice.creditorIBAN.count - $0))
            return String(invoice.creditorIBAN[start..<end])
        }.joined(separator: " ")
    }

    /// "8:40", not "8.67".
    ///
    /// A decimal quantity does not multiply back: 8.67 h at CHF 120 is
    /// 1'040.40, while the line said 1'040.00, and a client who checks the
    /// arithmetic finds the invoice wrong. Hours and minutes are exact, and
    /// the amount is computed from the same minutes, so the page adds up.
    /// NEAREST, not down. `quantity` is a whole minute count that was routed
    /// through a 6-decimal string, so 227 minutes arrives as 3.783333 and
    /// times 60 is 226.99998 — flooring printed 3:46 beside an amount for
    /// 3:47, on 488 of the 1440 possible minute counts, always a minute
    /// short. The true value is always an exact minute, so rounding to the
    /// nearest one is exact and flooring is simply wrong.
    static func clockHours(_ value: Decimal) -> String {
        let totalMinutes = Int((NSDecimalNumber(decimal: value).doubleValue * 60).rounded())
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func hours(_ value: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.2f", rounded)
    }

    private func amount(_ value: Decimal) -> String {
        currency.format(NSDecimalNumber(decimal: value).doubleValue)
    }
}
