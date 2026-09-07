import XCTest
import SwiftData
@testable import Cutaway

/// Manual corrections: a day's total is set as a number, the store keeps
/// the spans honest, and the running session is never double-counted.
@MainActor
final class DayEditTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!
    private var p: Project!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        p = try store.createProject(name: "Nyx", client: "", mode: .hourly, hourlyRate: 85, currency: .chf)
    }

    private func date(_ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: d, hour: h, minute: mi))!
    }

    func testGrowingADayKeepsItsSpan() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 11), activeSeconds: 6000), to: p, calendar: cal)
        try store.setActiveSeconds(9000, on: date(17, 15), for: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.activeSeconds, 9000, accuracy: 0.01)
        XCTAssertEqual(day.firstStart, date(17, 9), "first activity must survive an upward edit")
        XCTAssertEqual(day.lastEnd, date(17, 11), "adjustment pins to the last real activity")
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).count, 1, "no stray day rows")
    }

    /// A day whose last part ended exactly at midnight (DaySplitter's
    /// overnight split) must still take its adjustment on THAT day.
    func testGrowingAMidnightEndedDayStaysOnThatDay() throws {
        try store.record(SessionRecord(start: date(17, 22, 40), end: date(18, 0), activeSeconds: 4800), to: p, calendar: cal)
        try store.setActiveSeconds(7200, on: date(17, 15), for: p, calendar: cal)
        let days = store.dayTotals(for: p, calendar: cal)
        XCTAssertEqual(days.count, 1, "no phantom next-day row")
        XCTAssertEqual(days.first?.activeSeconds ?? 0, 7200, accuracy: 0.01)
        XCTAssertEqual(cal.startOfDay(for: days.first!.day), date(17, 0))
    }

    /// Asking for less than the running session alone must be refused, not
    /// clamped to zero — the clamp deleted every banked session of the day.
    func testATargetBelowTheLiveSessionIsRefused() {
        XCTAssertNil(AppModel.persistedTarget(requested: 3600, live: 10800))
        XCTAssertEqual(AppModel.persistedTarget(requested: 3600 * 8, live: 10800), 3600 * 5)
        XCTAssertEqual(AppModel.persistedTarget(requested: 3600, live: 0), 3600)
    }

    func testShrinkingTrimsNewestSessionsFirst() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(17, 13), end: date(17, 14), activeSeconds: 1800), to: p, calendar: cal)
        try store.setActiveSeconds(3000, on: date(17, 12), for: p, calendar: cal)
        XCTAssertEqual(store.totalActiveSeconds(for: p), 3000, accuracy: 0.01)
        let left = try store.context.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(left.count, 1, "zeroed session is deleted, not kept as a ghost")
        XCTAssertEqual(left[0].start, date(17, 9), "the older session absorbs the remainder")
    }

    func testEditingOneDayLeavesOthersAlone() throws {
        try store.record(SessionRecord(start: date(16, 9), end: date(16, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.setActiveSeconds(0, on: date(17, 9), for: p, calendar: cal)
        let days = store.dayTotals(for: p, calendar: cal)
        XCTAssertEqual(days.map(\.activeSeconds), [3600])
        XCTAssertEqual(days[0].day, cal.startOfDay(for: date(16, 9)))
    }

    func testAddingAnUnseenDayCreatesIt() throws {
        try store.setActiveSeconds(7200, on: date(15, 8), for: p, calendar: cal, now: date(20, 8))
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.day, cal.startOfDay(for: date(15, 8)))
        XCTAssertEqual(day.activeSeconds, 7200)
        XCTAssertEqual(day.firstStart, date(15, 12), "a day with no trace is pinned at noon")
    }

    func testNegativeTargetClampsToZero() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.setActiveSeconds(-500, on: date(17, 9), for: p, calendar: cal)
        XCTAssertEqual(store.totalActiveSeconds(for: p), 0)
    }

    func testHoursTextParsing() {
        XCTAssertEqual(AppModel.seconds(fromHoursText: "1:30"), 5400)
        XCTAssertEqual(AppModel.seconds(fromHoursText: "1.5"), 5400)
        XCTAssertEqual(AppModel.seconds(fromHoursText: "1,5 h"), 5400)
        XCTAssertEqual(AppModel.seconds(fromHoursText: "90m"), 5400)
        XCTAssertEqual(AppModel.seconds(fromHoursText: "0"), 0)
        XCTAssertNil(AppModel.seconds(fromHoursText: "1:75"), "minutes past 59 are a typo")
        XCTAssertNil(AppModel.seconds(fromHoursText: "-2"))
        XCTAssertNil(AppModel.seconds(fromHoursText: "abc"))
        XCTAssertNil(AppModel.seconds(fromHoursText: ""))
        XCTAssertEqual(AppModel.hoursText(5400), "1:30")
        XCTAssertEqual(AppModel.hoursText(59.6 * 60), "1:00", "rounds to the minute")
    }

    func testProjectUpdatePersistsEveryBillingField() throws {
        try store.update(p) {
            $0.name = "Nyx v2"; $0.client = "Nyx Studios"; $0.mode = .budget
            $0.hourlyRate = 120; $0.budget = 4500; $0.currency = .eur
        }
        let f = try store.projects()[0]
        XCTAssertEqual(f.name, "Nyx v2")
        XCTAssertEqual(f.client, "Nyx Studios")
        XCTAssertEqual(f.mode, .budget)
        XCTAssertEqual(f.hourlyRate, 120)
        XCTAssertEqual(f.budget, 4500)
        XCTAssertEqual(f.currency, .eur)
    }

    func testGrowingADayIsFlaggedAsAdjusted() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 11), activeSeconds: 6000), to: p, calendar: cal)
        try store.setActiveSeconds(9000, on: date(17, 15), for: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 3000, accuracy: 0.01, "the typed part is separable from the tracked part")
        let adjusted = try store.context.fetch(FetchDescriptor<WorkSession>()).filter { $0.isAdjusted }
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted[0].hourlyRate, 85, "an adjustment bills at the rate in force, like any session")
    }

    func testShrinkingIsNotAnAdjustment() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.setActiveSeconds(1800, on: date(17, 9), for: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 0, "removing time invents nothing — no flag")
    }

    func testUntouchedDayHasNoAdjustment() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 0)
    }
}

/// A manual pause stays sacred while the editor is away; sustained ANCHOR
/// input during the pause is a forgotten pause, and the engine reacts per
/// the chosen mode.
@MainActor
final class AutoResumeTests: XCTestCase {

    private var probes: DetectionEngineTests.FakeProbes!
    private var engine: DetectionEngine!
    private var clock: Date!

    override func setUp() async throws {
        probes = DetectionEngineTests.FakeProbes()
        // Isolated defaults: togglePause() persists the manual pause, and a
        // test must never leave a real pause behind in the app's Prefs.
        let scratch = scratchDefaults()
        engine = DetectionEngine(probes: probes, defaults: scratch)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
        engine.tick()
        engine.togglePause()
        XCTAssertEqual(engine.state, .paused(.manual))
    }

    private func run(_ seconds: Int, app: String? = DetectionInput.resolveBundleIDs[0], idle: TimeInterval = 0) {
        probes.frontmost = app
        probes.idle = idle
        for _ in 0..<seconds { clock = clock.addingTimeInterval(1); engine.tick() }
    }

    func testAutoModeResumesAfterSustainedAnchorWork() {
        engine.autoResume = .auto
        run(Int(DetectionEngine.resumeSignalDuration) - 1)
        XCTAssertTrue(engine.manuallyPaused, "a glance at Resolve must not wake the clock")
        run(2)
        XCTAssertFalse(engine.manuallyPaused)
        XCTAssertEqual(engine.state, .recording, "same tick records — no phantom paused frame")
        XCTAssertEqual(engine.accumulator.activeSeconds, 1, accuracy: 1.1,
                       "the signal window itself is never billed")
    }

    func testAutoModeIgnoresSatellitesAndIdleAnchors() {
        engine.autoResume = .auto
        run(120, app: "com.google.Chrome")
        XCTAssertTrue(engine.manuallyPaused, "browsing is ambiguous — never wakes a pause")
        run(120, idle: 300)
        XCTAssertTrue(engine.manuallyPaused, "Resolve frontmost with nobody home is not work")
    }

    func testLeavingTheAnchorResetsTheSignal() {
        engine.autoResume = .auto
        run(30)
        run(5, app: "com.spotify.client")
        run(30)
        XCTAssertTrue(engine.manuallyPaused, "signal must be continuous, not cumulative")
        run(20)
        XCTAssertFalse(engine.manuallyPaused)
    }

    func testAskModePromptsOncePerCooldownAndFlagsThePanel() {
        engine.autoResume = .ask
        var prompts = 0
        engine.onResumePrompt = { prompts += 1 }
        run(Int(DetectionEngine.resumeSignalDuration) + 5)
        XCTAssertTrue(engine.manuallyPaused, "ask mode never resumes on its own")
        XCTAssertEqual(prompts, 1)
        XCTAssertTrue(engine.workDetectedWhilePaused, "panel banner must be showing")
        run(600)
        XCTAssertEqual(prompts, 1, "'stay paused' is respected inside the cooldown")
        run(Int(DetectionEngine.resumePromptCooldown))
        XCTAssertEqual(prompts, 2, "but a forgotten pause is asked about again")
        engine.resume()
        XCTAssertFalse(engine.manuallyPaused)
        XCTAssertFalse(engine.workDetectedWhilePaused)
    }

    func testOffModeNeverReacts() {
        engine.autoResume = .off
        var prompts = 0
        engine.onResumePrompt = { prompts += 1 }
        run(3600)
        XCTAssertTrue(engine.manuallyPaused)
        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(engine.workDetectedWhilePaused)
    }

    func testResumeIsNoOpWhenNotPaused() {
        engine.togglePause()
        XCTAssertFalse(engine.manuallyPaused)
        engine.resume()
        XCTAssertFalse(engine.manuallyPaused, "resume must never toggle INTO a pause")
    }
}
