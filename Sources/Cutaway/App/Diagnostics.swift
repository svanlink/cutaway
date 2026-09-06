import Foundation
import MetricKit
import os

/// Crash and hang reports, on disk, nowhere else. MetricKit delivers them
/// on the next launch; the user copies them into a bug report by choice.
final class DiagnosticsStore: @unchecked Sendable {
    let directory: URL
    let keep: Int
    init(directory: URL, keep: Int = 10) { self.directory = directory; self.keep = keep }

    static let `default` = DiagnosticsStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Cutaway/Diagnostics"))

    func write(_ data: Data, stamp: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // MetricKit hands over a BATCH at launch; a second-resolution name
        // alone made them overwrite each other. Sorting stays by the stamp.
        let name = ISO8601DateFormatter().string(from: stamp).replacingOccurrences(of: ":", with: "-")
            + "-" + UUID().uuidString.prefix(8) + ".json"
        try data.write(to: directory.appendingPathComponent(name))
        for old in try reports().dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    /// Newest first.
    func reports() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func combinedReport() throws -> String {
        try reports().map {
            "== \($0.lastPathComponent) ==\n" + ((try? Data(contentsOf: $0)).flatMap { String(data: $0, encoding: .utf8) } ?? "")
        }.joined(separator: "\n\n")
    }
}

final class DiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber {
    let store: DiagnosticsStore
    init(store: DiagnosticsStore = .default) {
        self.store = store
        super.init()
        MXMetricManager.shared.add(self)
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            do { try store.write(p.jsonRepresentation()) } catch {
                // MetricKit delivers once; at least the unified log keeps it.
                Logger(subsystem: "com.vaneickelen.cutaway", category: "diagnostics")
                    .error("could not store diagnostic payload: \(error, privacy: .public)")
            }
        }
    }
    // Metric (not diagnostic) payloads reached macOS with the macOS 26 SDK;
    // older SDKs mark the type unavailable and refuse the override.
    #if compiler(>=6.2)
    func didReceive(_ payloads: [MXMetricPayload]) {}
    #endif
}
