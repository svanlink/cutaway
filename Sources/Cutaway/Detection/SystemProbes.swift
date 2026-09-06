import AppKit
import CoreGraphics
import Darwin

/// Live system probes behind a protocol so DetectionEngine is testable
/// with fake values.
protocol SystemProbing: Sendable {
    func frontmostBundleID() -> String?
    func secondsSinceLastInput() -> TimeInterval
    /// Whether the frontmost app currently owns a full-screen window. Asked
    /// LAZILY — only when an idle warning is otherwise about to show — so the
    /// window-list walk is not a per-second cost.
    func frontmostWindowIsFullScreen() -> Bool
    /// CUMULATIVE cpu time burned by every running anchor app, in nanoseconds.
    /// Cumulative rather than a percentage so the probe stays stateless — the
    /// engine owns the two samples it takes to make a rate.
    func workAppCPUNanos(matching prefixes: [String]) -> UInt64
}

extension SystemProbing {
    /// Probes that don't care about render detection (test fakes, the
    /// scenario driver) read as "nothing is burning cpu".
    func workAppCPUNanos(matching prefixes: [String]) -> UInt64 { 0 }
    /// And as "no window is full-screen".
    func frontmostWindowIsFullScreen() -> Bool { false }
}

protocol FrontmostApplication { var bundleIdentifier: String? { get } }
extension NSRunningApplication: FrontmostApplication {}

/// The frontmost app, kept current by NSWorkspace's own notification
/// instead of asked for every tick — Apple's "subscribe, don't poll".
@MainActor
final class FrontmostTracker {
    private(set) var bundleID: String?
    private var token: NSObjectProtocol?

    init(initial: String?, center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        bundleID = initial
        token = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                   object: nil, queue: .main) { [weak self] n in
            // Read the id here; only the String (Sendable) crosses into the actor.
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? FrontmostApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.bundleID = id }
        }
    }
}

/// A class, not a struct: it owns the tracker's subscription. The engine
/// ticks on the main actor, so the nonisolated protocol read is safe.
final class SystemProbes: SystemProbing {
    private let frontmost = MainActor.assumeIsolated {
        FrontmostTracker(initial: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func frontmostBundleID() -> String? {
        MainActor.assumeIsolated { frontmost.bundleID }
    }

    func secondsSinceLastInput() -> TimeInterval {
        // ~0 = "any input event type" — keyboard, mouse, scroll, tablet.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func frontmostWindowIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        // Heuristic: a window whose size equals a screen's size is
        // full-screen on that screen. Sizes rather than origins, because
        // CGWindow uses top-left coordinates and NSScreen bottom-left — and
        // a size match is appearance-enough for "do not float a card over
        // this". Window BOUNDS need no screen-recording permission; window
        // titles would, and are not needed.
        let screenSizes = NSScreen.screens.map(\.frame.size)
        let pid = front.processIdentifier
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let size = CGSize(width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if screenSizes.contains(size) { return true }
        }
        return false
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
