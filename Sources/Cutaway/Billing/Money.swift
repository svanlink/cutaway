import Foundation

/// Every rappen the app prints goes through here.
///
/// Two surfaces rounding the same seconds differently is how a CSV and a
/// Stats window come to disagree — they did, on roughly three months in four,
/// until 2026-09-07: `CSVExporter.round2` was half-away-from-zero while
/// `NumberFormatter` defaults to half-even, and a whole-franc rate over
/// whole seconds lands on exact half-rappen ties constantly.
enum Money {
    /// Two decimals, ties DOWN. An ambiguous half-rappen belongs to the
    /// client — the same direction every other rule in the engine resolves.
    /// (Negatives round down too, i.e. away from zero: a budget overrun is
    /// never made to look smaller than it is.)
    static func round2(_ value: Double) -> Double {
        let scaled = value * 100
        let lower = scaled.rounded(.down)
        return ((scaled - lower > 0.5) ? lower + 1 : lower) / 100
    }

    // MARK: - Exact money, for anything that gets frozen or printed

    /// Minor units belong to the CURRENCY, not to a call site. One answer,
    /// used by rounding, formatting and the CSV alike.
    static func minorUnits(_ currency: BillingCurrency) -> Int {
        currency == .cop ? 0 : 2
    }

    /// A Double turned into the decimal number a person would have written.
    /// `Decimal(45.55)` inherits the binary approximation of 45.55; going
    /// through the printed form does not, which is the entire reason for
    /// using Decimal on a document in the first place.
    static func decimal(_ value: Double, places: Int = 6) -> Decimal {
        Decimal(string: String(format: "%.\(places)f", value)) ?? Decimal(value)
    }

    /// Seconds and a rate are measurements and stay `Double`. The moment they
    /// become an AMOUNT — a line on an invoice, a total a client can dispute —
    /// they become `Decimal`. A frozen document must not be built out of
    /// binary floats.
    static func amount(activeSeconds: TimeInterval, hourlyRate: Double) -> Decimal {
        // Multiply FIRST. Dividing by 3600 up front makes 3'610 s a repeating
        // decimal (1.00277…) that Decimal truncates at 38 digits, so an exact
        // half-rappen tie arrives as 45.124999…9 and rounds the wrong way.
        // 3'610 × 45 ÷ 3600 is exactly 45.125.
        decimal(activeSeconds) * decimal(hourlyRate) / 3600
    }

    /// Ties DOWN, at the currency's own precision — the same rule and the
    /// same direction as `round2`, so a Decimal invoice line and a Double
    /// stat row can never print different numbers for the same work.
    static func rounded(_ value: Decimal, currency: BillingCurrency) -> Decimal {
        let places = minorUnits(currency)
        var scale = Decimal(1)
        for _ in 0..<places { scale *= 10 }
        let scaled = value * scale

        // NSDecimalRound's .down is toward ZERO; this needs a floor, so a
        // negative with a fraction steps one further away. Without it a
        // budget overrun would round toward looking smaller than it is.
        var floored = Decimal()
        var input = scaled
        NSDecimalRound(&floored, &input, 0, .down)
        if scaled < 0, floored != scaled { floored -= 1 }

        let half = Decimal(sign: .plus, exponent: -1, significand: 5)   // 0.5
        let result = (scaled - floored > half) ? floored + 1 : floored
        return result / scale
    }

    /// Sum of already-rounded parts. Round once, then add — never the reverse.
    static func total(_ parts: [Decimal]) -> Decimal {
        parts.reduce(Decimal(0), +)
    }
}
