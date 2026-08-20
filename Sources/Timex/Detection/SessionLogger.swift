import Foundation
import os

/// JSON-lines event log — the milestone (a) checkpoint proof. Also mirrors
/// to os.Logger so `log stream` works. Lives in Application Support.
final class SessionLogger: @unchecked Sendable {
    private let osLog = Logger(subsystem: "com.vaneickelen.cutaway", category: "detection")
    private let fileURL: URL
    private let iso = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "session-logger")

    /// Roll at 2 MB, keeping one previous file — so the log costs at most
    /// ~4 MB forever instead of growing for as long as the app is used. It
    /// is a diagnostic, not an archive.
    static let defaultMaxBytes = 2 * 1024 * 1024

    /// Where the log belongs, given whether this is a verification run.
    /// Pure so the rule is testable without an environment.
    static func directory(scenarioDataDir: String?,
                          isTestRun: Bool = ProcessInfo.processInfo
                              .environment["XCTestConfigurationFilePath"] != nil) -> URL {
        // A scenario run must not write into the user's real data directory.
        // The scenario STORE has always been quarantined; the log never was,
        // so every smoke run appended to the file a real user accumulates.
        if let scenarioDataDir { return URL(fileURLWithPath: scenarioDataDir) }
        // Nor may the unit suite. Engine tests construct DetectionEngine
        // without a logger, so the DEFAULT logger was writing fake probe
        // transitions — idle 300.0, four state changes in one second — into
        // the log a real user's crash forensics come from. Same leak as the
        // scenario one, one layer further in.
        if isTestRun {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cutaway-tests", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cutaway", isDirectory: true)
    }

    init(directory: URL? = nil, maxBytes: Int = SessionLogger.defaultMaxBytes) {
        let dir = directory ?? Self.directory(scenarioDataDir: ScenarioMode.dataDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("detection-log.jsonl")
        rollIfOversized(maxBytes: maxBytes)
    }

    /// Rolled at launch rather than per write: the check costs one stat call
    /// once, instead of one on every checkpoint for the life of the process.
    private func rollIfOversized(maxBytes: Int) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size]) as? Int,
              size > maxBytes else { return }
        let previous = fileURL.deletingLastPathComponent()
            .appendingPathComponent("detection-log.1.jsonl")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: fileURL, to: previous)
    }

    /// Test hook: the writer is asynchronous, and a test that reads the file
    /// before the queue drains is a flaky test, not a fast one.
    func flush() {
        queue.sync {}
    }

    func log(event: String, detail: String = "", input: DetectionInput? = nil) {
        var entry: [String: String] = [
            "t": iso.string(from: Date()),
            "event": event,
        ]
        if !detail.isEmpty { entry["detail"] = detail }
        if let input {
            entry["frontmost"] = input.frontmostBundleID ?? "none"
            entry["idle"] = String(format: "%.1f", input.secondsSinceInput)
        }
        osLog.info("\(event, privacy: .public) \(detail, privacy: .public)")
        queue.async { [fileURL, entry] in
            guard let data = try? JSONSerialization.data(withJSONObject: entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: fileURL)
            }
        }
    }

    var logPath: String { fileURL.path }
}
