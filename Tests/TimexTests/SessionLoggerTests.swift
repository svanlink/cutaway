import XCTest
@testable import Cutaway

/// Two defects in one file: verification runs appended to the user's real
/// log (the scenario STORE was quarantined, the log never was), and the log
/// grew forever — 3.1 MB and 39,705 lines on the development machine from a
/// few days, most of it 15-second checkpoints.
final class SessionLoggerTests: XCTestCase {

    private var dir: URL!
    private var fm: FileManager { .default }

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("logger-tests-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? fm.removeItem(at: dir) }

    private var logFile: URL { dir.appendingPathComponent("detection-log.jsonl") }
    private var rolled: URL { dir.appendingPathComponent("detection-log.1.jsonl") }

    // MARK: - Quarantine

    func testAScenarioRunWritesToItsOwnDataDirectory() {
        let scenario = SessionLogger.directory(scenarioDataDir: "/tmp/some-scenario-run")
        XCTAssertEqual(scenario.path, "/tmp/some-scenario-run")
        XCTAssertFalse(scenario.path.contains("Application Support"),
                       "a verification run must not touch the user's data directory")
    }

    func testARealRunStillUsesApplicationSupport() {
        let real = SessionLogger.directory(scenarioDataDir: nil)
        XCTAssertTrue(real.path.contains("Application Support"))
        XCTAssertEqual(real.lastPathComponent, "Cutaway")
    }

    // MARK: - Growth

    func testAnOversizedLogIsRolledAtLaunch() throws {
        try Data(repeating: 0x41, count: 5000).write(to: logFile)
        _ = SessionLogger(directory: dir, maxBytes: 1000)

        XCTAssertTrue(fm.fileExists(atPath: rolled.path), "the old log is kept, once")
        XCTAssertFalse(fm.fileExists(atPath: logFile.path),
                       "the live log restarts empty rather than growing forever")
        let keptSize = (try fm.attributesOfItem(atPath: rolled.path)[.size]) as? Int
        XCTAssertEqual(keptSize, 5000, "rolling must not truncate what it keeps")
    }

    func testRollingTwiceKeepsOnlyOnePreviousFile() throws {
        try Data(repeating: 0x41, count: 5000).write(to: logFile)
        _ = SessionLogger(directory: dir, maxBytes: 1000)
        try Data(repeating: 0x42, count: 5000).write(to: logFile)
        _ = SessionLogger(directory: dir, maxBytes: 1000)

        let entries = try fm.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(entries, ["detection-log.1.jsonl"],
                       "at most one previous log — the cost is bounded, not merely slowed")
        XCTAssertEqual(try Data(contentsOf: rolled).first, 0x42, "the newer log is the one kept")
    }

    func testASmallLogIsLeftAlone() throws {
        try Data("one line\n".utf8).write(to: logFile)
        _ = SessionLogger(directory: dir, maxBytes: SessionLogger.defaultMaxBytes)
        XCTAssertFalse(fm.fileExists(atPath: rolled.path))
        XCTAssertEqual(try Data(contentsOf: logFile), Data("one line\n".utf8))
    }

    func testAFreshInstallHasNothingToRoll() {
        _ = SessionLogger(directory: dir, maxBytes: 1000)
        XCTAssertFalse(fm.fileExists(atPath: rolled.path))
    }

    // MARK: - Still a working log

    func testEventsAreWrittenAsJSONLines() throws {
        let logger = SessionLogger(directory: dir)
        logger.log(event: "transition", detail: "recording")
        logger.log(event: "checkpoint", detail: "activeSeconds=42")
        logger.flush()

        let lines = try String(contentsOf: logFile, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: String]
        XCTAssertEqual(first?["event"], "transition")
        XCTAssertEqual(first?["detail"], "recording")
        XCTAssertNotNil(first?["t"], "an event without a timestamp is not a log entry")
    }
}
