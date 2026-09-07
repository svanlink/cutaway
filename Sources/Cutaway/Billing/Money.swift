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
}
