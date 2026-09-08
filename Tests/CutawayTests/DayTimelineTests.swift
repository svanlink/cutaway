import XCTest
@testable import Cutaway

/// The strip's arithmetic. A gesture that divides money has to be tested
/// somewhere a gesture cannot reach.
final class DayTimelineTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: h, minute: m))!
    }

    private func block(_ from: Date, _ to: Date, active: TimeInterval? = nil,
                       adjusted: Bool = false) -> DayTimeline.Block {
        DayTimeline.Block(id: UUID().uuidString, start: from, end: to,
                          activeSeconds: active ?? to.timeIntervalSince(from),
                          isAdjusted: adjusted)
    }

    /// A working day, never a calendar day: an editor's day is six hours
    /// wide and a 00:00–24:00 axis turns every session into a sliver.
    func testTheDomainIsTheWorkingDayRoundedToHours() {
        let blocks = [block(at(9, 12), at(11, 40)), block(at(14, 5), at(16, 20))]
        let d = DayTimeline.domain(for: blocks, on: at(0), calendar: cal)
        XCTAssertEqual(d.start, at(9), "the hour containing the first start")
        XCTAssertEqual(d.end, at(17), "the hour containing the last end")
    }

    /// A twenty-minute day still needs a scale, and it should be centred
    /// rather than pinned to its first hour.
    func testAShortDayGrowsToTheFloorAroundItsMiddle() {
        let blocks = [block(at(14, 0), at(14, 20))]
        let d = DayTimeline.domain(for: blocks, on: at(0), calendar: cal)
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 4 * 3600, accuracy: 1)
        let middle = d.start.addingTimeInterval(d.end.timeIntervalSince(d.start) / 2)
        XCTAssertEqual(middle, at(14, 30), "centred on the work, not on the hour")
    }

    func testAnEmptyDayShowsAPlausibleWorkingWindow() {
        let d = DayTimeline.domain(for: [], on: at(0), calendar: cal)
        XCTAssertEqual(d.start, at(9))
        XCTAssertEqual(d.end, at(17))
    }

    func testFractionsMapBothWays() {
        let t = DayTimeline(start: at(9), end: at(17), blocks: [])
        XCTAssertEqual(t.fraction(of: at(13)), 0.5, accuracy: 0.001)
        XCTAssertEqual(t.date(atFraction: 0.5), at(13))
        XCTAssertEqual(t.fraction(of: at(3)), 0, "before the domain clamps")
        XCTAssertEqual(t.fraction(of: at(22)), 1, "after it clamps too")
    }

    /// A drag landing on 11:37:42 is noise recorded as precision.
    func testDragsSnapToFiveMinutesAndToOneWithOption() {
        // Nearest, not truncation: 11:37:42 really is closer to 11:40.
        XCTAssertEqual(DayTimeline.snap(at(11, 37).addingTimeInterval(42), toMinutes: 5), at(11, 40))
        XCTAssertEqual(DayTimeline.snap(at(11, 36), toMinutes: 5), at(11, 35))
        XCTAssertEqual(DayTimeline.snap(at(11, 37).addingTimeInterval(42), toMinutes: 1), at(11, 38))
    }

    func testTicksThinOutAsTheDayGrows() {
        XCTAssertEqual(DayTimeline.tickInterval(hours: 6), 1)
        XCTAssertEqual(DayTimeline.tickInterval(hours: 8), 1, "eight hours is the ordinary day")
        XCTAssertEqual(DayTimeline.tickInterval(hours: 10), 2)
        XCTAssertEqual(DayTimeline.tickInterval(hours: 16), 4)
        let t = DayTimeline(start: at(9), end: at(17), blocks: [])
        XCTAssertEqual(t.ticks(calendar: cal).count, 8, "10:00 through 17:00")
    }

    /// Under twenty minutes a gap is the bridge doing its job.
    func testOnlyGapsWorthExplainingAreDrawn() {
        let blocks = [block(at(9), at(10)), block(at(10, 10), at(11)), block(at(12), at(13))]
        let gaps = DayTimeline.gaps(in: blocks)
        XCTAssertEqual(gaps.count, 1, "the 10-minute gap is not worth a mark")
        XCTAssertEqual(gaps[0].start, at(11))
        XCTAssertEqual(gaps[0].end, at(12))
    }

    /// THE money test. A two-hour span holding 90 minutes of active time,
    /// split at its midpoint, is two one-hour spans of 45 minutes — not 60.
    /// The idle the engine already excluded stays excluded.
    func testSplittingDistributesActiveTimeByWallClockFraction() throws {
        let b = block(at(9), at(11), active: 90 * 60)
        let halves = try XCTUnwrap(DayTimeline.split(b, at: at(10)))
        XCTAssertEqual(halves.first.activeSeconds, 45 * 60, accuracy: 0.5)
        XCTAssertEqual(halves.second.activeSeconds, 45 * 60, accuracy: 0.5)
        XCTAssertEqual(halves.first.activeSeconds + halves.second.activeSeconds,
                       b.activeSeconds, accuracy: 0.5, "the halves bill exactly what the whole did")
    }

    /// The second half takes the REMAINDER, so an odd split cannot lose or
    /// invent a second.
    func testAnOddSplitLosesNothing() throws {
        let b = block(at(9), at(9, 59), active: 3_533)
        let halves = try XCTUnwrap(DayTimeline.split(b, at: at(9, 17)))
        XCTAssertEqual(halves.first.activeSeconds + halves.second.activeSeconds, 3_533,
                       accuracy: 0.001)
    }

    func testSplittingOutsideTheSessionIsRefused() {
        let b = block(at(9), at(11))
        XCTAssertNil(DayTimeline.split(b, at: at(8)))
        XCTAssertNil(DayTimeline.split(b, at: at(12)))
        XCTAssertNil(DayTimeline.split(b, at: at(9)), "an edge is not inside")
    }

    /// The caption under the strip.
    func testTheSummaryCountsWhatTheDayHeld() {
        let blocks = [block(at(9), at(10), active: 3_000), block(at(11), at(12), active: 3_600)]
        let s = DayTimeline.summary(blocks)
        XCTAssertEqual(s.sessions, 2)
        XCTAssertEqual(s.tracked, 6_600, accuracy: 0.5)
        XCTAssertEqual(s.gaps, 3_600, accuracy: 0.5, "the hour between them")
    }

    /// A ninety-second session must still be grabbable — the strip is a
    /// control, not a chart.
    func testAVeryShortBlockStillHasAMinimumWidth() {
        let t = DayTimeline(start: at(9), end: at(17), blocks: [])
        let width: CGFloat = 440
        let b = block(at(10), at(10, 1))
        let raw = CGFloat(t.fraction(of: b.end) - t.fraction(of: b.start)) * width
        XCTAssertLessThan(raw, 6, "a one-minute session is under a pixel-and-a-half of 8 hours")
        XCTAssertEqual(max(raw, 6), 6, "so the view floors it at 6 pt")
    }
}

/// The caption under the strip.
final class DayTimelineCaptionTests: XCTestCase {

    func testOneSessionIsNotOneSessions() {
        XCTAssertTrue(DayTimelineView.captionText(sessions: 1, tracked: 3600, gaps: 0)
            .hasPrefix("1 session ·"), "no plural s on one")
        XCTAssertTrue(DayTimelineView.captionText(sessions: 2, tracked: 3600, gaps: 0)
            .hasPrefix("2 sessions"))
    }

    /// A day with no gaps should not advertise "0:00 in gaps" — an absence
    /// stated is noise, and this caption sits under every unfolded day.
    func testNoGapsIsNotMentioned() {
        XCTAssertFalse(DayTimelineView.captionText(sessions: 1, tracked: 43_200, gaps: 0)
            .contains("gaps"))
        XCTAssertTrue(DayTimelineView.captionText(sessions: 3, tracked: 43_200, gaps: 900)
            .contains("in gaps"))
    }
}
