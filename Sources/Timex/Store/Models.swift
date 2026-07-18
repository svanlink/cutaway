import Foundation
import SwiftData

enum BillingMode: String, Codable, Sendable {
    case hourly
    case budget
}

@Model
final class Project {
    var name: String
    var client: String
    var modeRaw: String
    var hourlyRate: Double
    var budget: Double
    var currencyRaw: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkSession.project)
    var sessions: [WorkSession] = []

    var mode: BillingMode {
        get { BillingMode(rawValue: modeRaw) ?? .hourly }
        set { modeRaw = newValue.rawValue }
    }
    var currency: TimexCurrency {
        get { TimexCurrency(rawValue: currencyRaw) ?? .chf }
        set { currencyRaw = newValue.rawValue }
    }

    init(name: String, client: String, mode: BillingMode, hourlyRate: Double,
         budget: Double = 0, currency: TimexCurrency) {
        self.name = name
        self.client = client
        self.modeRaw = mode.rawValue
        self.hourlyRate = hourlyRate
        self.budget = budget
        self.currencyRaw = currency.rawValue
        self.createdAt = Date()
    }
}

@Model
final class WorkSession {
    var start: Date
    var end: Date
    var activeSeconds: TimeInterval
    var project: Project?

    init(start: Date, end: Date, activeSeconds: TimeInterval, project: Project?) {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.project = project
    }
}

/// One row of the Daily Breakdown / CSV: a project's totals for one day.
struct DayTotal: Equatable, Sendable {
    var day: Date            // startOfDay
    var activeSeconds: TimeInterval
    var sessionCount: Int
    var firstStart: Date
    var lastEnd: Date
}
