import XCTest
@testable import Cutaway

final class IntentsTests: XCTestCase {
    func testTodayResultSentence() {
        XCTAssertEqual(IntentText.today(seconds: 2 * 3600 + 14 * 60, money: "CHF 190.00", project: "Nyx"),
                       "2 hours 14 minutes today on Nyx — CHF 190.00")
        XCTAssertEqual(IntentText.today(seconds: 0, money: "—", project: nil), "No project selected")
    }
}
