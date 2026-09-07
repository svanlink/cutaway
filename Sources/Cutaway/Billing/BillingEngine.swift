import Foundation

/// Pure billing math. No I/O, no state — everything unit-testable.
enum BillingEngine {

    // MARK: - Hourly

    static func earnings(activeSeconds: TimeInterval, hourlyRate: Double) -> Double {
        activeSeconds / 3600 * hourlyRate
    }

    // MARK: - Budget

    enum BudgetWarning: Equatable {
        case none, warn75, warn90, over
    }

    struct BudgetStatus: Equatable {
        var percentUsed: Double
        var remaining: Double
        var warning: BudgetWarning
    }

    static func budgetStatus(usedAmount: Double, budget: Double) -> BudgetStatus {
        let pct = budget > 0 ? usedAmount / budget * 100 : 0
        let warning: BudgetWarning
        switch pct {
        case ..<75: warning = .none
        case ..<90: warning = .warn75
        case ..<100: warning = .warn90
        default: warning = .over
        }
        return BudgetStatus(percentUsed: pct, remaining: budget - usedAmount, warning: warning)
    }

    /// What can honestly be said about how long a budget will last.
    ///
    /// A rate divided by a near-zero pace is arithmetically fine and
    /// practically a lie: twenty-two seconds of tracked work against a 4'500
    /// budget extrapolates to 10,858 working days — forty-three years,
    /// printed to one decimal place as though it meant something. A forecast
    /// has to know when it does not have enough to forecast from.
    enum BudgetForecast: Equatable {
        /// Enough worked history to extrapolate from.
        case days(Double)
        /// Too little tracked work to claim a pace. Say nothing.
        case paceUnknown
        /// The pace is real but so slow the number stops being information.
        case beyondHorizon
    }

    /// A working year. Past this, "how many days" is not the useful answer.
    static let forecastHorizonDays: Double = 250
    /// Below a quarter hour a day, a "pace" is noise being amplified.
    static let forecastMinimumDailySeconds: TimeInterval = 15 * 60
    /// One day is a sample of one. Two is the least that can trend.
    static let forecastMinimumDaysWorked = 2

    static func forecast(remaining: Double, avgDailySeconds: TimeInterval,
                         hourlyRate: Double, daysWorked: Int) -> BudgetForecast {
        guard remaining > 0, hourlyRate > 0 else { return .paceUnknown }
        guard daysWorked >= forecastMinimumDaysWorked,
              avgDailySeconds >= forecastMinimumDailySeconds else { return .paceUnknown }
        let dailyBurn = earnings(activeSeconds: avgDailySeconds, hourlyRate: hourlyRate)
        guard dailyBurn > 0 else { return .paceUnknown }
        let days = remaining / dailyBurn
        return days > forecastHorizonDays ? .beyondHorizon : .days(days)
    }

    /// The sentence the budget card prints, or nil when there is nothing
    /// honest to say yet.
    static func forecastLine(_ forecast: BudgetForecast) -> String? {
        switch forecast {
        case .paceUnknown:
            return nil
        case .beyondHorizon:
            return "More than a year left at current pace"
        case .days(let d):
            return d < 1.0
                ? "Less than a working day left at current pace"
                : "≈ \(String(format: "%.1f", d)) working days left at current pace"
        }
    }
}

/// The four supported currencies with deterministic, design-locked formatting.
/// Fixed separators (not locale lookups) so output can never drift with OS
/// locale-data updates: CHF 2'329.25 · COP 1.395.000 · € 900.00 · $ 393.75
enum BillingCurrency: String, CaseIterable, Codable, Sendable {
    case chf = "CHF"
    case cop = "COP"
    case eur = "EUR"
    case usd = "USD"

    /// The currency to start a first-run user on. Cutaway supports four; a
    /// Mac set to anything else falls back to CHF rather than inventing an
    /// unsupported one. Only ever a STARTING point — the pref, once written,
    /// outranks the locale.
    static func fromLocale(_ locale: Locale = .current) -> BillingCurrency {
        guard let code = locale.currency?.identifier,
              let match = BillingCurrency(rawValue: code.uppercased())
        else { return .chf }
        return match
    }

    var symbol: String {
        switch self {
        case .chf: return "CHF"
        case .cop: return "COP"
        case .eur: return "€"
        case .usd: return "$"
        }
    }

    private var groupingSeparator: String {
        switch self {
        case .chf, .eur: return "'"
        case .cop: return "."
        case .usd: return ","
        }
    }

    private var decimals: Int {
        self == .cop ? 0 : 2
    }

    func format(_ amount: Double) -> String {
        "\(symbol) \(number(amount, decimals: decimals))"
    }

    /// Stat-row style: no decimal places.
    func formatWhole(_ amount: Double) -> String {
        "\(symbol) \(number(amount, decimals: 0))"
    }

    private func number(_ amount: Double, decimals: Int) -> String {
        let f = NumberFormatter()
        // POSIX base locale: explicit separators below already pin the
        // shape, but this stops any OS-locale property (digits, minus sign)
        // from leaking into billing output.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.groupingSeparator = groupingSeparator
        f.decimalSeparator = "."
        f.usesGroupingSeparator = true
        // Match Money.round2 exactly. The formatter's default is half-EVEN;
        // the exporter rounds ties down. One of them printing 45.13 while the
        // other printed 45.12 for the same day is the bug this closes.
        f.roundingMode = .halfDown
        return f.string(from: NSNumber(value: decimals == 0 ? amount.rounded(.down) : amount)) ?? "\(amount)"
    }
}
