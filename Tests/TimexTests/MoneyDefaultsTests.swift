import XCTest
@testable import Cutaway

/// A first-run user should not have to notice a currency picker on a form
/// they were shown before they understood the app. And every path that
/// creates a project must agree about what the defaults are — the sheet used
/// to say 85 CHF while auto-creation read the prefs.
@MainActor
final class MoneyDefaultsTests: XCTestCase {

    private func locale(_ id: String) -> Locale { Locale(identifier: id) }

    override func tearDown() async throws {
        Prefs.removeObject(forKey: "defaultCurrency")
        Prefs.removeObject(forKey: "defaultHourlyRate")
    }

    func testLocaleMapsToEachSupportedCurrency() {
        XCTAssertEqual(TimexCurrency.fromLocale(locale("de_CH")), .chf)
        XCTAssertEqual(TimexCurrency.fromLocale(locale("de_DE")), .eur)
        XCTAssertEqual(TimexCurrency.fromLocale(locale("fr_FR")), .eur)
        XCTAssertEqual(TimexCurrency.fromLocale(locale("en_US")), .usd)
        XCTAssertEqual(TimexCurrency.fromLocale(locale("es_CO")), .cop)
    }

    func testUnsupportedLocaleFallsBackRatherThanInventing() {
        XCTAssertEqual(TimexCurrency.fromLocale(locale("ja_JP")), .chf, "JPY is not supported")
        XCTAssertEqual(TimexCurrency.fromLocale(locale("en_GB")), .chf, "GBP is not supported")
    }

    func testStoredPreferenceOutranksTheLocale() {
        Prefs.set("USD", forKey: "defaultCurrency")
        XCTAssertEqual(AppModel.defaultCurrency, .usd,
                       "an explicit choice must survive whatever the Mac's locale says")
    }

    func testGarbagePreferenceFallsBackToLocale() {
        Prefs.set("XYZ", forKey: "defaultCurrency")
        XCTAssertEqual(AppModel.defaultCurrency, TimexCurrency.fromLocale(),
                       "an unreadable pref must not crash or pin a wrong currency")
    }

    func testDefaultRateIsClampedLikeEveryOtherRate() {
        Prefs.set(-40.0, forKey: "defaultHourlyRate")
        XCTAssertEqual(AppModel.defaultHourlyRate, 0, "negative rates are typos, everywhere")
        Prefs.set(1_000_000.0, forKey: "defaultHourlyRate")
        XCTAssertEqual(AppModel.defaultHourlyRate, 99_999)
    }

    func testUnsetRateHasAStartingValue() {
        Prefs.removeObject(forKey: "defaultHourlyRate")
        XCTAssertEqual(AppModel.defaultHourlyRate, 85, "a first run still needs a number")
    }

    /// The regression this goal exists for: the sheet hardcoded 85.00/CHF as
    /// @State while auto-creation read the prefs, so one Mac created projects
    /// two different ways. Both now read the same accessors.
    func testEveryCreationPathReadsTheSameDefaults() {
        Prefs.set("EUR", forKey: "defaultCurrency")
        Prefs.set(120.0, forKey: "defaultHourlyRate")
        XCTAssertEqual(AppModel.defaultCurrency, .eur)
        XCTAssertEqual(AppModel.defaultHourlyRate, 120)
        XCTAssertEqual(String(format: "%.2f", AppModel.defaultHourlyRate), "120.00",
                       "the sheet seeds its rate field from this exact string")
    }
}
