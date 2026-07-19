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

    /// "≈ N working days left at current pace". Nil when there is no pace
    /// to extrapolate from or the budget is already exhausted.
    static func forecastDaysLeft(remaining: Double, avgDailySeconds: TimeInterval, hourlyRate: Double) -> Double? {
        guard remaining > 0, avgDailySeconds > 0, hourlyRate > 0 else { return nil }
        let dailyBurn = earnings(activeSeconds: avgDailySeconds, hourlyRate: hourlyRate)
        guard dailyBurn > 0 else { return nil }
        return remaining / dailyBurn
    }

    // MARK: - Daily goal

    struct GoalProgress: Equatable {
        var fraction: Double        // 0…1, capped
        var overtimeSeconds: TimeInterval
        var reached: Bool
    }

    static func goalProgress(activeSeconds: TimeInterval, goalSeconds: TimeInterval) -> GoalProgress {
        guard goalSeconds > 0 else { return GoalProgress(fraction: 0, overtimeSeconds: 0, reached: false) }
        let reached = activeSeconds >= goalSeconds
        return GoalProgress(
            fraction: min(activeSeconds / goalSeconds, 1),
            overtimeSeconds: reached ? activeSeconds - goalSeconds : 0,
            reached: reached
        )
    }
}

/// The four supported currencies with deterministic, design-locked formatting.
/// Fixed separators (not locale lookups) so output can never drift with OS
/// locale-data updates: CHF 2'329.25 · COP 1.395.000 · € 900.00 · $ 393.75
enum TimexCurrency: String, CaseIterable, Codable, Sendable {
    case chf = "CHF"
    case cop = "COP"
    case eur = "EUR"
    case usd = "USD"

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
        return f.string(from: NSNumber(value: decimals == 0 ? amount.rounded(.down) : amount)) ?? "\(amount)"
    }
}
