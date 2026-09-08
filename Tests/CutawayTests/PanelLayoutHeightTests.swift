import XCTest
@testable import Cutaway

/// The panel is as tall as it has reason to be.
final class PanelLayoutHeightTests: XCTestCase {

    func testTwoProjectsDoNotReserveRoomForSix() {
        XCTAssertEqual(PanelLayout.listHeight(rowCount: 2), 2 * PanelLayout.rowHeight,
                       "a ScrollView claims every point offered; this one may not")
        XCTAssertLessThan(PanelLayout.listHeight(rowCount: 2), PanelLayout.maxListHeight)
    }

    func testALongListStopsAtTheCap() {
        XCTAssertEqual(PanelLayout.listHeight(rowCount: 40), PanelLayout.maxListHeight)
    }

    /// Stopping mid-row is the affordance that says "there is more" — a cap
    /// on an exact row boundary looks like the end of the list.
    func testTheCapCutsARowInHalf() {
        let rows = PanelLayout.maxListHeight / PanelLayout.rowHeight
        XCTAssertNotEqual(rows, rows.rounded(), "the cap must not land on a row boundary")
    }

    func testNoProjectsIsNotNegativeSpace() {
        XCTAssertEqual(PanelLayout.listHeight(rowCount: 0), 0)
        XCTAssertEqual(PanelLayout.listHeight(rowCount: -3), 0, "never a negative frame")
    }
}
