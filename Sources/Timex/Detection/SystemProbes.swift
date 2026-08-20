import AppKit
import CoreGraphics
import Darwin

/// Live system probes behind a protocol so DetectionEngine is testable
/// with fake values.
protocol SystemProbing: Sendable {
    func frontmostBundleID() -> String?
    func secondsSinceLastInput() -> TimeInterval
    /// CUMULATIVE cpu time burned by every running anchor app, in nanoseconds.
    /// Cumulative rather than a percentage so the probe stays stateless — the
    /// engine owns the two samples it takes to make a rate.
    func workAppCPUNanos(matching prefixes: [String]) -> UInt64
}

extension SystemProbing {
    /// Probes that don't care about render detection (test fakes, the
    /// scenario driver) read as "nothing is burning cpu".
    func workAppCPUNanos(matching prefixes: [String]) -> UInt64 { 0 }
}

struct SystemProbes: SystemProbing {
    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func secondsSinceLastInput() -> TimeInterval {
        // ~0 = "any input event type" — keyboard, mouse, scroll, tablet.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func workAppCPUNanos(matching prefixes: [String]) -> UInt64 {
        NSWorkspace.shared.runningApplications.reduce(into: UInt64(0)) { total, app in
            guard let id = app.bundleIdentifier,
                  DetectionInput.resolveBundleIDs.contains(id) || prefixes.contains(where: id.hasPrefix)
            else { return }
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V4, $0)
                }
            }
            if ok == 0 { total += info.ri_user_time + info.ri_system_time }
        }
    }
}
