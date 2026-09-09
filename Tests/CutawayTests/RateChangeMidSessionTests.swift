import XCTest
@testable import Cutaway

/// A raise today must not reprice this morning.
///
/// `record()` stamps the rate at the moment a session CLOSES, which is right
/// — a raise next month must not reprice last month's work. But it made an
/// open session a hostage: work 09:00–17:00, raise the rate at 15:00, and
/// all eight hours billed at the new rate, including the six worked at the
/// old one. Over-billing, and the direct opposite of the sentence printed
/// above the field: "Work already recorded keeps the rate it was worked at."
@MainActor
final class RateChangeMidSessionTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    private var store: SessionStore!
    private var engine: DetectionEngine!
    private var probes: FakeProbes!
    private var clock: Date!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        probes = FakeProbes()
        engine = DetectionEngine(probes: probes, defaults: scratchDefaults())
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [unowned self] in self.clock }
    }

    func testBankingAnOpenSessionKeepsTheHoursAtTheRateTheyWereWorkedAt() throws {
        let project = try store.createProject(name: "Maisons", client: "Richemont",
                                              mode: .hourly, hourlyRate: 120, currency: .chf)
        var closed: [SessionRecord] = []
        engine.onSessionClosed = { record in
            closed.append(record)
            try? self.store.record(record, to: project)
            return true
        }
        engine.hasActiveProject = true
        probes.frontmost = "com.blackmagic-design.DaVinciResolve"
        engine.workAppPrefixes = DetectionInput.resolveBundleIDs
        engine.anchorNamedAProject = true
        for _ in 0..<3600 { clock += 1; engine.tick() }      // an hour at 120

        engine.bankOpenSession(reason: "rate-change")
        XCTAssertEqual(closed.count, 1, "the open session is banked before the rate moves")
        XCTAssertEqual(closed[0].activeSeconds, 3600, accuracy: 2)

        let banked = try XCTUnwrap(store.projects().first?.sessions.first)
        XCTAssertEqual(banked.hourlyRate, 120,
                       "the hour worked at 120 is stamped 120, whatever happens next")

        // The raise lands after the hour is safely on disk.
        try store.update(project) { $0.hourlyRate = 150 }
        XCTAssertEqual(banked.hourlyRate, 120, "and stays 120")
    }
}
