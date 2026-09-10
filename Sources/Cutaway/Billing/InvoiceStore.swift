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
        case budgetFullyInvoiced

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
            case .budgetFullyInvoiced:
                return String(localized: "This project's budget is fully invoiced. Agree more with the client, or void the earlier invoice.")
            }
        }
    }

    /// What this project has already been invoiced, excluding voided
    /// documents — a void keeps its number but claims nothing.
    func invoicedTotal(for project: Project) throws -> Decimal {
        try invoices(of: project)
            .filter { $0.status != .void }
            .reduce(Decimal(0)) { $0 + $1.subtotal }
    }

    /// Every document belonging to this project, newest first — voids
    /// included, because a void is still a document someone may need to see.
    ///
    /// Identity first; the name only for documents issued before projects had
    /// one. This rule used to live inside `invoicedTotal` alone, so the
    /// invoice sheet's own list joined on the name and a rename emptied it:
    /// the documents still existed, still locked their days, still counted
    /// against the budget, and could no longer be voided, marked paid or
    /// re-saved from anywhere in the app. One predicate, one place.
    func invoices(of project: Project) throws -> [Invoice] {
        let uid = project.uid
        return try invoices().filter { invoice in
            if !uid.isEmpty, !invoice.projectUID.isEmpty { return invoice.projectUID == uid }
            return invoice.projectName == project.name
        }
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
            let remaining = Money.decimal(project.budget) - alreadyBilled
            // A ceiling that is spent is still a ceiling. budgetCapped only
            // caps while `budget > 0`, so a fully-invoiced job used to fall
            // through UNCAPPED and bill hourly time on top of an agreed fixed
            // price. Refusing is the under-billing answer, and it is the one
            // the owner can act on: raise it with the client, or void.
            if project.budget > 0, remaining <= 0 {
                throw InvoiceError.budgetFullyInvoiced
            }
            draft = InvoiceBuilder.budgetCapped(draft, budget: remaining,
                                                taxRate: taxMode.rate,
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
        invoice.projectUID = project.ensureUID()
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
        try commit()
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
        try commit()
        invalidateTodayCache()
    }

    /// No date is recorded, because `Invoice` has no field for one. The
    /// parameter took a date and dropped it, which reads like the app
    /// remembers when a client paid. It does not.
    func markPaid(_ invoice: Invoice) throws {
        guard invoice.status == .issued else { return }
        invoice.status = .paid
        try commit()
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
    func unbilledTotal(for project: Project) throws -> Decimal {
        let accrued = Money.total(project.sessions
            .filter { !$0.isInvoiced }
            .map { Money.rounded(Money.decimal($0.earned(projectRate: project.hourlyRate)),
                                 currency: project.currency) })
        // A fixed price is a ceiling, and `InvoiceBuilder.budgetCapped`
        // enforces it — so a budget job worked past its budget accrued time
        // the invoice sheet will refuse to bill, and the panel advertised it
        // as money owed. "CHF 2'329 unbilled" beside a job that will pay
        // nothing more is the panel's most-read line telling its worst lie.
        //
        // Throws rather than swallowing: a figure this one is derived from
        // cannot be read means the answer is unknown, and reporting unknown
        // as a number is how a reporting failure becomes a billing decision.
        guard project.mode == .budget, project.budget > 0 else { return accrued }
        let headroom = Money.rounded(Money.decimal(project.budget), currency: project.currency)
            - (try invoicedTotal(for: project))
        return max(min(accrued, headroom), 0)
    }
}
