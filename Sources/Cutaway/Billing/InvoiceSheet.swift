import SwiftUI
import AppKit

/// Issue an invoice for a period.
///
/// The supplier block lives here rather than in Settings. It is required by
/// law on the page, so it is a fact about the business, not a preference —
/// and the moment it is actually needed is the moment to ask for it. Same
/// pattern as the resume card: the question goes where it is live. It is
/// remembered afterwards, so this is a first-invoice cost, not a per-invoice
/// one.
struct InvoiceSheet: View {
    @Bindable var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var period: InvoicePeriod = .lastMonth
    @State private var supplier = Supplier.current
    @State private var taxMode: TaxMode = .notRegistered
    @State private var clientAddress = ""
    @State private var clientVAT = ""
    @State private var refusal: String?
    @State private var preview: InvoiceBuilder.Draft?
    /// Bumped after a status change so the list re-reads the store.
    @State private var bump = 0

    var body: some View {
        VStack(spacing: 0) {
            // A sheet with no title is a form someone has to infer. This one
            // creates a legal document; it can say so.
            VStack(alignment: .leading, spacing: 2) {
                Text("New invoice").font(.headline)
                Text(project.name)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
            Form {
                Section("Period") {
                    Picker(selection: $period) {
                        ForEach(InvoicePeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    } label: {
                        labelled("Bill", "Only work that is not already invoiced")
                    }
                    .accessibilityLabel("Period to bill")
                    LabeledContent {
                        Text(summary).monospacedDigit()
                    } label: {
                        labelled("This invoice", "Rounded per day, then added")
                    }
                }
                Section("From") {
                    TextField("Your name", text: $supplier.name)
                        .accessibilityLabel("Your name")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Address").font(.caption).foregroundStyle(.secondary)
                        TextField("Street, postcode and town", text: $supplier.address, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .accessibilityLabel("Your address")
                    }
                    TextField("UID", text: $supplier.vatNumber, prompt: Text("CHE-123.456.789"))
                        .accessibilityLabel("Your VAT number")
                    TextField("IBAN", text: $supplier.iban, prompt: Text("CH93 0076 2011 6238 5295 7"))
                        .accessibilityLabel("Your IBAN")
                    if !supplier.iban.isEmpty {
                        // Said before the first one is printed, not after a
                        // bank rejects it: the payload is exact and tested,
                        // the LAYOUT is a faithful arrangement rather than a
                        // certified one, and only the scheme's own validator
                        // can settle that.
                        Text("A payment part with a QR code will be printed. Validate the first one at validation.iso-payments.ch before sending it to a client.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("To") {
                    LabeledContent("Client") { Text(project.client.isEmpty ? "—" : project.client) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Address").font(.caption).foregroundStyle(.secondary)
                        TextField("Street, postcode and town", text: $clientAddress, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .accessibilityLabel("Client address")
                    }
                    TextField("Client UID", text: $clientVAT)
                        .accessibilityLabel("Client VAT number")
                    Picker(selection: $taxMode) {
                        Text("Not registered for VAT").tag(TaxMode.notRegistered)
                        Text("Swiss VAT 8.1 %").tag(TaxMode.swissVAT)
                        Text("EU reverse charge").tag(TaxMode.euReverseCharge)
                        Text("Outside scope").tag(TaxMode.none)
                    } label: {
                        labelled("Tax", "What this client's invoice must state")
                    }
                    .accessibilityLabel("Tax treatment")
                    Text(taxMode.note).font(.caption).foregroundStyle(.secondary)
                }
                if let refusal {
                    Section {
                        Text(refusal).font(.callout).foregroundStyle(.orange)
                    }
                }
                if !issued.isEmpty {
                    Section("Issued") {
                        ForEach(issued, id: \.persistentModelID) { invoice in
                            issuedRow(invoice)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Issue & Save PDF…") { issue() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.map { $0.lines.isEmpty } ?? true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .frame(width: 560, height: 720)
        .onAppear {
            taxMode = project.taxMode
            clientAddress = project.clientAddress
            clientVAT = project.clientVATNumber
            refresh()
        }
        .onChange(of: period) { _, _ in refresh() }
        .onChange(of: taxMode) { _, _ in refresh() }
    }

    /// `InvoicePeriod.interval` is half-open and optional; the invoice API
    /// takes an inclusive last day. Convert once, here, rather than at three
    /// call sites that could drift apart.
    private func range() -> (from: Date, to: Date) {
        let cal = Calendar.current
        guard let i = period.interval() else {
            return (Date.distantPast, cal.startOfDay(for: Date()))
        }
        return (i.start, cal.date(byAdding: .day, value: -1, to: i.end) ?? i.end)
    }

    /// Past invoices for this project, newest first. They live here rather
    /// than in a window of their own: the app has three surfaces, and the
    /// place you think about invoices is the place you make them.
    private var issued: [Invoice] {
        ((try? model.store.invoices()) ?? [])
            .filter { $0.projectName == project.name }
    }

    @ViewBuilder
    private func issuedRow(_ invoice: Invoice) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                if invoice.status == .issued {
                    Button("Mark paid") { try? model.store.markPaid(invoice); bump += 1 }
                }
                if invoice.status != .void {
                    Button("PDF…") { savePDF(invoice) }
                    // Void keeps the number and releases the work, which is
                    // the only correction path an issued document has.
                    Button("Void") { voidInvoice(invoice) }
                }
            }
            .buttonStyle(.link)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(invoice.number).monospacedDigit()
                Text(statusLine(invoice)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statusLine(_ invoice: Invoice) -> String {
        let total = invoice.currency.format(NSDecimalNumber(decimal: invoice.total).doubleValue)
        let issuedOn = invoice.issueDate.formatted(.dateTime.day().month(.abbreviated).year())
        switch invoice.status {
        case .draft: return String(localized: "Draft · \(total)")
        case .issued: return String(localized: "Issued \(issuedOn) · \(total) · unpaid")
        case .paid: return String(localized: "Issued \(issuedOn) · \(total) · paid")
        case .void: return String(localized: "Issued \(issuedOn) · \(total) · VOID")
        }
    }

    private func voidInvoice(_ invoice: Invoice) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Void \(invoice.number)?")
        alert.informativeText = String(localized: "The number is kept and never reused, so the sequence stays gapless. Its work becomes billable again and the days unlock.")
        alert.addButton(withTitle: String(localized: "Void Invoice"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try model.store.voidInvoice(invoice); bump += 1; refresh() }
        catch { refusal = error.localizedDescription }
    }

    private func savePDF(_ invoice: Invoice) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = InvoicePDF.filename(for: invoice)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do { try InvoicePDF.write(invoice, to: url) }
                catch { refusal = error.localizedDescription }
            }
        }
    }

    private var summary: String {
        guard let preview, !preview.lines.isEmpty else { return String(localized: "Nothing unbilled") }
        let days = preview.lines.filter { $0.kind == .time }.count
        let total = project.currency.format(NSDecimalNumber(decimal: preview.total).doubleValue)
        return "\(days) d · \(total)"
    }

    /// A live preview built from the same pure code that will freeze the
    /// document, so what is agreed to here is what gets issued.
    private func refresh() {
        let span = range()
        let sessions = model.store.billableSessions(for: project, from: span.from, to: span.to)
        var uidsByDay: [Date: [String]] = [:]
        for s in sessions {
            uidsByDay[Calendar.current.startOfDay(for: s.start), default: []].append(s.uid)
        }
        let days = model.store.dayTotals(for: project).filter { uidsByDay[$0.day] != nil }
        let lines = InvoiceBuilder.lines(for: days, sessionUIDsByDay: uidsByDay, currency: project.currency)
        var draft = InvoiceBuilder.totals(lines, taxMode: taxMode, currency: project.currency)
        if project.mode == .budget {
            draft = InvoiceBuilder.budgetCapped(draft, budget: Money.decimal(project.budget),
                                                currency: project.currency)
        }
        preview = draft
    }

    private func issue() {
        refusal = nil
        if let missing = supplier.missingForInvoice { refusal = missing; return }
        if let no = taxMode.issueRefusal(supplierVATNumber: supplier.vatNumber) { refusal = no; return }

        supplier.save()
        project.clientAddress = clientAddress
        project.clientVATNumber = clientVAT
        project.taxMode = taxMode

        let span = range()
        let invoice: Invoice
        do {
            invoice = try model.store.issueInvoice(
                for: project, from: span.from, to: span.to,
                taxMode: taxMode, supplier: supplier.block,
                supplierVATNumber: supplier.vatNumber,
                clientBlock: project.clientBlock,
                iban: supplier.iban)
        } catch {
            refusal = error.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = InvoicePDF.filename(for: invoice)
        panel.message = String(localized: "\(invoice.number) is issued. Save the PDF for your client.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do { try InvoicePDF.write(invoice, to: url) }
                catch {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "The invoice was issued, but the PDF could not be written")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
                dismiss()
            }
        }
    }
}
