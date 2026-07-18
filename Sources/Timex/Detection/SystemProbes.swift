import AppKit
import CoreGraphics

/// Live system probes behind a protocol so DetectionEngine is testable
/// with fake values.
protocol SystemProbing: Sendable {
    func frontmostBundleID() -> String?
    func secondsSinceLastInput() -> TimeInterval
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
}
