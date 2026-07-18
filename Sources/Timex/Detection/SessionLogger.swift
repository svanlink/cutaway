import Foundation
import os

/// JSON-lines event log — the milestone (a) checkpoint proof. Also mirrors
/// to os.Logger so `log stream` works. Lives in Application Support.
final class SessionLogger: @unchecked Sendable {
    private let osLog = Logger(subsystem: "com.vaneickelen.cutaway", category: "detection")
    private let fileURL: URL
    private let iso = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "session-logger")

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cutaway", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("detection-log.jsonl")
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
