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
                    Text(line.kind == .time ? hours(line.quantity) : "")
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

    private func hours(_ value: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.2f", rounded)
    }

    private func amount(_ value: Decimal) -> String {
        currency.format(NSDecimalNumber(decimal: value).doubleValue)
    }
}
