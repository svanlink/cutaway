import Foundation
import SwiftData

/// Issuing, locking and voiding. The rules a document imposes on the work
/// behind it.
@MainActor
extension SessionStore {

    enum InvoiceError: LocalizedError {
        case dayIsInvoiced(String)
        case sessionsAreInvoiced(String)
        case nothingToBill
        case taxRefused(String)

        var errorDescription: String? {
            switch self {
            case .dayIsInvoiced(let number):
                return String(localized: "That day is on invoice \(number). Void the invoice to change it.")
            case .sessionsAreInvoiced(let number):
                return String(localized: "This work is on invoice \(number). Void the invoice first.")
            case .nothingToBill:
                return String(localized: "There is no unbilled work in that period.")
            case .taxRefused(let why):
                return why
            }
        }
    }

    /// What this project has already been invoiced, excluding voided
    /// documents — a void keeps its number but claims nothing.
    func invoicedTotal(for project: Project) throws -> Decimal {
        try invoices()
            .filter { $0.projectName == project.name && $0.status != .void }
            .reduce(Decimal(0)) { $0 + $1.subtotal }
    }

    func invoices() throws -> [Invoice] {
        try context.fetch(FetchDescriptor<Invoice>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    /// The sessions a period would bill: unlocked work only. Work already on
    /// an invoice is never billed twice, and new work recorded inside an
    /// invoiced period lands here unlocked — it bills NEXT period rather than
    /// being folded silently into a document already sent.
    func billableSessions(for project: Project, from: Date, to: Date,
                          calendar: Calendar = .current) -> [WorkSession] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return project.sessions
            .filter { !$0.isInvoiced }
            .filter {
                let day = calendar.startOfDay(for: $0.start)
                return day >= start && day <= end
            }
            .sorted { $0.start < $1.start }
    }

    /// Build and freeze. Everything printed is copied; only the session UIDs
    /// point outward, and they point at identity, not at live figures.
    @discardableResult
    func issueInvoice(for project: Project, from: Date, to: Date,
                      taxMode: TaxMode, supplier: String, supplierVATNumber: String,
                      clientBlock: String, dueInDays: Int = 30,
                      iban: String = "",
                      now: Date = Date(), calendar: Calendar = .current) throws -> Invoice {
        if let refusal = taxMode.issueRefusal(supplierVATNumber: supplierVATNumber) {
            throw InvoiceError.taxRefused(refusal)
        }
        // Refuse before anything is written: a payment part that a bank
        // rejects is worse than no payment part.
        if !iban.isEmpty {
            try SwissQRBill.assertSupported(project.currency)
            guard SwissQRBill.isValidIBAN(iban) else {
                throw InvoiceError.taxRefused(String(localized: "That IBAN is not a valid Swiss or Liechtenstein IBAN."))
            }
            guard !SwissQRBill.isQRIBAN(iban) else {
                // A QR-IBAN demands a 27-digit QR reference with a recursive
                // mod-10 check digit, issued per-customer by the bank.
                // Cutaway cannot invent one, and a wrong one is a bill that
                // bounces — so it says so instead of guessing.
                throw InvoiceError.taxRefused(String(localized: "That is a QR-IBAN, which needs a bank-issued QR reference. Use your ordinary IBAN instead."))
            }
        }
        let sessions = billableSessions(for: project, from: from, to: to, calendar: calendar)
        guard !sessions.isEmpty else { throw InvoiceError.nothingToBill }

        var uidsByDay: [Date: [String]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.start)
            uidsByDay[day, default: []].append(session.ensureUID())
        }
        // Over the BILLABLE sessions only. Grouping the project's whole
        // history here billed a partly-invoiced day again in full.
        let days = Self.dayTotals(from: sessions, projectRate: project.hourlyRate, calendar: calendar)

        let built = InvoiceBuilder.lines(for: days, sessionUIDsByDay: uidsByDay,
                                         currency: project.currency, calendar: calendar)
        var draft = InvoiceBuilder.totals(built, taxMode: taxMode, currency: project.currency)
        if project.mode == .budget {
            // What is LEFT of the budget, not the whole budget again. Capping
            // each invoice at the full figure let a CHF 4'500 job bill 4'500
            // and then 2'400 on top.
            let alreadyBilled = try invoicedTotal(for: project)
            draft = InvoiceBuilder.budgetCapped(draft,
                                                budget: Money.decimal(project.budget) - alreadyBilled,
                                                currency: project.currency)
        }

        let year = calendar.component(.year, from: now)
        let number = InvoiceBuilder.nextNumber(existing: try invoices().map(\.number), year: year)

        let invoice = Invoice()
        invoice.number = number
        invoice.status = .issued
        invoice.issueDate = now
        invoice.dueDate = calendar.date(byAdding: .day, value: dueInDays, to: now) ?? now
        invoice.periodStart = calendar.startOfDay(for: from)
        invoice.periodEnd = calendar.startOfDay(for: to)
        invoice.currency = project.currency
        invoice.taxMode = taxMode
        invoice.taxRate = taxMode.rate
        invoice.supplierBlock = supplier
        invoice.clientBlock = clientBlock
        invoice.projectName = project.name
        invoice.subtotalString = "\(draft.subtotal)"
        invoice.taxAmountString = "\(draft.taxAmount)"
        invoice.totalString = "\(draft.total)"
        invoice.timeZoneIdentifier = calendar.timeZone.identifier
        invoice.creditorIBAN = iban.isEmpty ? "" : SwissQRBill.normalisedIBAN(iban)
        invoice.qrReference = iban.isEmpty ? nil : SwissQRBill.creditorReference(from: number)
        context.insert(invoice)

        for (i, line) in draft.lines.enumerated() {
            let row = InvoiceLine()
            row.kind = line.kind
            row.day = line.day
            row.text = line.text
            row.quantityString = "\(line.quantity)"
            row.unit = line.unit
            row.unitPriceString = "\(line.unitPrice)"
            row.amountString = "\(line.amount)"
            row.adjustedHoursString = "\(line.adjustedHours)"
            row.sessionUIDs = line.sessionUIDs
            row.sortIndex = i
            row.invoice = invoice
            context.insert(row)
        }
        // The lock, last: nothing is locked by a document that failed to build.
        for session in sessions { session.invoiceNumber = number }
        try context.save()
        invalidateTodayCache()
        return invoice
    }

    /// Void keeps the number — printed VOID, never reused, so the sequence
    /// stays gapless — and releases its sessions so the correction can happen
    /// in the ordinary editing path. Not a credit note (that needs an
    /// accruing cross-document balance) and not an unlock (an issued document
    /// that can silently disagree with the store destroys the whole point).
    func voidInvoice(_ invoice: Invoice) throws {
        let number = invoice.number
        for project in try projects() {
            for session in project.sessions where session.invoiceNumber == number {
                session.invoiceNumber = ""
            }
        }
        invoice.status = .void
        try context.save()
        invalidateTodayCache()
    }

    func markPaid(_ invoice: Invoice, on date: Date = Date()) throws {
        guard invoice.status == .issued else { return }
        invoice.status = .paid
        try context.save()
    }

    /// The invoice locking a day, if any.
    func invoiceNumber(coveringDay day: Date, for project: Project,
                       calendar: Calendar = .current) -> String? {
        let start = calendar.startOfDay(for: day)
        return project.sessions
            .first { calendar.startOfDay(for: $0.start) == start && $0.isInvoiced }?
            .invoiceNumber
    }

    /// Unbilled money across every project — the figure the panel shows.
    func unbilledTotal(for project: Project) -> Decimal {
        Money.total(project.sessions
            .filter { !$0.isInvoiced }
            .map { Money.rounded(Money.decimal($0.earned(projectRate: project.hourlyRate)),
                                 currency: project.currency) })
    }
}
