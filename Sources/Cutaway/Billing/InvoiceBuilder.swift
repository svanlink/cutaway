import Foundation

/// Turns a period of tracked work into the lines of a document.
///
/// Pure: it takes days and sessions and returns values. Nothing here touches
/// the store, so every arithmetic rule below is testable without a database
/// — and the snapshot it produces is the thing that gets frozen, so a bug in
/// it would be frozen too.
enum InvoiceBuilder {

    struct Line: Equatable {
        var kind: InvoiceLineKind
        var day: Date?
        var text: String
        var quantity: Decimal        // hours, for time lines
        var unit: String
        var unitPrice: Decimal       // the rate the day actually billed at
        var amount: Decimal
        var adjustedHours: Decimal
        var sessionUIDs: [String]
    }

    struct Draft: Equatable {
        var lines: [Line]
        var subtotal: Decimal
        var taxAmount: Decimal
        var total: Decimal
        var adjustedHours: Decimal
    }

    /// One line per worked day, in date order.
    ///
    /// The day's rate is the rate it ACTUALLY billed at — blended when a day
    /// spans a rate change — so `hours × rate` on the page reconciles with
    /// the amount beside it. Rounding happens once per line; the total is
    /// the sum of the printed lines, never a separately rounded figure.
    static func lines(for days: [DayTotal], sessionUIDsByDay: [Date: [String]],
                      currency: BillingCurrency, calendar: Calendar = .current) -> [Line] {
        days.sorted { $0.day < $1.day }.map { day in
            // Billed to the MINUTE, rounded down. The page prints h:mm and the
            // amount is computed from those same minutes, so a client can
            // multiply the row and get the number beside it. Seconds beyond
            // the minute are given away — the direction every other rule in
            // this app resolves toward.
            let minutes = (day.activeSeconds / 60).rounded(.down)
            let hours = Money.decimal(minutes / 60, places: 6)
            let rate = Money.decimal(day.effectiveRate)
            // From the MINUTES, not from `hours`. `hours` is a 6-decimal
            // string for display, and that rounding is not free: 227 minutes
            // becomes "3.783333", which is 0.0000005 h too much. Multiplied
            // by a rate whose sixtieth ends in 5 — CHF 112.50, CHF 187.50 —
            // it lifts an exact half-rappen just above the tie, and half-down
            // then rounds it UP. 480 minute/rate pairs billed a rappen too
            // much, every one of them against the client. Minutes are exact;
            // divide last and the tie stays a tie.
            let amount = Money.rounded(Decimal(Int(minutes)) * rate / 60, currency: currency)
            return Line(kind: .time,
                        day: day.day,
                        text: dayText(day.day, calendar: calendar),
                        quantity: hours,
                        unit: String(localized: "h"),
                        unitPrice: rate,
                        amount: amount,
                        adjustedHours: Money.decimal(day.adjustedSeconds / 3600, places: 4),
                        sessionUIDs: sessionUIDsByDay[day.day] ?? [])
        }
    }

    /// Subtotal, tax and total, in that order and rounded once each.
    static func totals(_ lines: [Line], taxMode: TaxMode, currency: BillingCurrency) -> Draft {
        let subtotal = Money.total(lines.map(\.amount))
        // A mode that shows no tax line contributes no tax — including
        // reverse charge, where the client accounts for it, and
        // notRegistered, where stating an amount would mean owing it.
        let tax = taxMode.showsTaxLine
            ? Money.rounded(subtotal * Money.decimal(taxMode.rate) / 100, currency: currency)
            : 0
        return Draft(lines: lines,
                     subtotal: subtotal,
                     taxAmount: tax,
                     total: subtotal + tax,
                     adjustedHours: lines.reduce(Decimal(0)) { $0 + $1.adjustedHours })
    }

    /// A budget project bills the budget or the accrued time, whichever is
    /// LESS — a fixed price is a ceiling, and under-billing is the direction
    /// this app resolves toward. Overrun is the owner's problem to raise, not
    /// something the app quietly adds to an invoice.
    static func budgetCapped(_ draft: Draft, budget: Decimal, currency: BillingCurrency) -> Draft {
        guard budget > 0, draft.subtotal > budget else { return draft }
        var capped = draft
        let cap = Money.rounded(budget, currency: currency)
        capped.lines.append(Line(kind: .manual, day: nil,
                                 text: String(localized: "Fixed-price adjustment to agreed budget"),
                                 quantity: 1, unit: "",
                                 unitPrice: cap - draft.subtotal,
                                 amount: cap - draft.subtotal,
                                 adjustedHours: 0, sessionUIDs: []))
        capped.subtotal = cap
        capped.taxAmount = draft.taxAmount > 0
            ? Money.rounded(cap * draft.taxAmount / draft.subtotal, currency: currency) : 0
        capped.total = capped.subtotal + capped.taxAmount
        return capped
    }

    static func dayText(_ day: Date, calendar: Calendar = .current) -> String {
        var f = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        return day.formatted(f)
    }

    // MARK: - Numbering

    /// INV-YYYY-NNNN, gapless within a year, never reused — including by a
    /// voided document, which keeps its number precisely so the sequence has
    /// no hole for anyone to wonder about.
    static func nextNumber(existing: [String], year: Int) -> String {
        let prefix = "INV-\(year)-"
        let used = existing.compactMap { number -> Int? in
            guard number.hasPrefix(prefix) else { return nil }
            return Int(number.dropFirst(prefix.count))
        }
        let next = (used.max() ?? 0) + 1
        return prefix + String(format: "%04d", next)
    }
}
