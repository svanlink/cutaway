import AppKit
import Combine
import Observation

/// Drives the 1s evaluation loop: probes → DetectionState → accumulation.
/// Owns sleep/wake observation and manual pause. UI observes `state`,
/// `todayActiveSeconds`, and `sessionElapsed`.
@Observable
@MainActor
final class DetectionEngine {
    private(set) var state: DetectionState = .paused(.notFrontmost)
    private(set) var accumulator = SessionAccumulator()
    /// Closed sessions this run — milestone (b) moves these into SwiftData.
    private(set) var closedSessions: [SessionRecord] = []

    var manuallyPaused = false
    /// When the current manual pause began — nil while not paused.
    private(set) var manualPauseStart: Date?
    /// Flips true once a manual pause exceeds 15 minutes — the pill shows
    /// a hint so a forgotten pause doesn't silently eat a billable day.
    private(set) var pausedLong = false
    static let longPauseThreshold: TimeInterval = 900
    var idleThreshold: TimeInterval = Prefs.object(forKey: "idleThreshold") as? TimeInterval ?? 120
    var hasActiveProject = true
    var workAppPrefixes: [String] = Prefs.stringArray(forKey: "workApps") ?? DetectionInput.defaultWorkAppPrefixes
    var satellitePrefixes: [String] = Prefs.stringArray(forKey: "satelliteApps") ?? DetectionInput.defaultSatellitePrefixes
    var bridgeGrace: TimeInterval = Prefs.object(forKey: "bridgeGrace") as? TimeInterval ?? 180
    /// Research window: satellite apps sustain recording only this long after
    /// the last anchor (Resolve/Adobe) activity.
    var satelliteWindow: TimeInterval = Prefs.object(forKey: "satelliteWindow") as? TimeInterval ?? 1200
    /// Last moment an anchor app was frontmost with fresh input.
    private var lastAnchorActive: Date?
    /// When we left the work context while recording — the bridge window.
    private var awayGapStart: Date?
    /// Injectable clock so engine behavior is deterministic under test.
    var now: () -> Date = { Date() }
    private var lastTick: Date?
    /// Fired whenever a recording span closes — AppModel persists it.
    var onSessionClosed: ((SessionRecord) -> Void)?

    private let probes: any SystemProbing
    private let logger: SessionLogger
    private var isAsleep = false
    private var timer: Timer?
    private var lastCheckpoint = Date()

    init(probes: any SystemProbing = SystemProbes(), logger: SessionLogger = SessionLogger()) {
        self.probes = probes
        self.logger = logger
        observeSleepWake()
        // Flush the open session before the process dies — Quit must not
        // lose recorded time (spec: ≤15s loss, and clean quit loses zero).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func start() {
        guard timer == nil else { return }
        lastTick = now()
        logger.log(event: "engine-start")
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Generous tolerance lets macOS coalesce wakeups (energy win). Billing
        // accuracy is unaffected: accumulation uses real wall-clock deltas,
        // so a late tick credits exactly the elapsed time.
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closeSessionIfOpen(reason: "engine-stop")
    }

    func togglePause() {
        manuallyPaused.toggle()
        manualPauseStart = manuallyPaused ? now() : nil
        pausedLong = false
        // Re-evaluate immediately but do NOT accumulate — only the 1 Hz
        // timer adds seconds, otherwise every toggle injects phantom time.
        tick(accumulate: false)
    }

    // Internal (not private) so engine tests can drive ticks deterministically.
    func tick(accumulate: Bool = true) {
        // Forgotten-pause hint: mutate only on the threshold crossing so the
        // observable churns once, not every second.
        let isLong = manuallyPaused && manualPauseStart.map {
            now().timeIntervalSince($0) >= Self.longPauseThreshold
        } ?? false
        if isLong != pausedLong { pausedLong = isLong }
        // Midnight rollover: force-close a session that started yesterday so
        // the live "TODAY" figure never carries yesterday's seconds.
        if let start = accumulator.sessionStart,
           !Calendar.current.isDate(start, inSameDayAs: now()) {
            closeSessionIfOpen(reason: "midnight-rollover")
        }
        var input = DetectionInput(
            frontmostBundleID: probes.frontmostBundleID(),
            secondsSinceInput: probes.secondsSinceLastInput(),
            idleThreshold: idleThreshold,
            manuallyPaused: manuallyPaused,
            isAsleep: isAsleep,
            hasActiveProject: hasActiveProject,
            workAppPrefixes: workAppPrefixes
        )
        input.satellitePrefixes = satellitePrefixes
        // Anchor activity (anchor app frontmost + fresh input) refreshes the
        // research window; satellites sustain recording only inside it.
        if input.frontmostIsAnchor, input.secondsSinceInput < idleThreshold {
            lastAnchorActive = now()
        }
        input.satelliteWindowOpen = lastAnchorActive.map {
            now().timeIntervalSince($0) <= satelliteWindow
        } ?? false
        let newState = DetectionState.evaluate(input)
        if newState != state {
            logger.log(event: "transition", detail: describe(newState), input: input)
            switch newState {
            case .paused(.manual), .paused(.systemSleep), .paused(.noProject):
                // HARD boundaries: the bridge must never span time the user
                // explicitly paused, slept through, or worked project-less.
                // Close regardless of previous state and kill any open gap.
                closeSessionIfOpen(reason: describe(newState))
                awayGapStart = nil
            case .paused(.notFrontmost) where state == .recording:
                // Bridge window: keep the session open — a quick detour is
                // bridged retroactively on return; closes on grace expiry.
                awayGapStart = now()
            case .paused where state == .recording:
                closeSessionIfOpen(reason: describe(newState))
            default:
                break
            }
            // Returning to work within the grace credits the away-gap.
            if newState == .recording, let gapStart = awayGapStart {
                let gap = now().timeIntervalSince(gapStart)
                if gap <= bridgeGrace, accumulator.sessionStart != nil {
                    accumulator.credit(gap)
                    logger.log(event: "bridge-credit", detail: "gap=\(Int(gap))s")
                }
                awayGapStart = nil
            }
            // Any resume resets the delta clock — otherwise the first
            // recording tick's wall delta overlaps the credited gap and
            // double-counts up to the cap.
            if newState == .recording, state != .recording {
                lastTick = now()
            }
            state = newState
        }
        // Grace expired while away → the session finally closes, gap uncounted.
        if state == .paused(.notFrontmost), let gapStart = awayGapStart,
           now().timeIntervalSince(gapStart) > bridgeGrace {
            closeSessionIfOpen(reason: "bridge-expired")
            awayGapStart = nil
        }
        if accumulate {
            // Real wall-clock delta, not an assumed 1s — RunLoop stalls and
            // App Nap would otherwise silently undercount. Capped so a
            // pathological stall can't over-credit either.
            let t = now()
            let delta = lastTick.map { min(max(t.timeIntervalSince($0), 0), 5) } ?? 1
            lastTick = t
            accumulator.tick(state: newState, interval: delta, now: t)
        }

        // 15s checkpoint = max data loss on crash. Snapshot the open session
        // to UserDefaults; recovered on next launch.
        if newState == .recording, now().timeIntervalSince(lastCheckpoint) >= 15 {
            logger.log(event: "checkpoint", detail: "activeSeconds=\(Int(accumulator.activeSeconds))")
            lastCheckpoint = Date()
            snapshotOpenSession()
        }
        onTick?()
    }

    /// Called after every tick — AppModel hooks project auto-detection here.
    var onTick: (() -> Void)?

    private func snapshotOpenSession() {
        guard let start = accumulator.sessionStart else { return }
        let d = Prefs
        d.set(start.timeIntervalSince1970, forKey: "openSession.start")
        d.set(accumulator.activeSeconds, forKey: "openSession.active")
        d.set(Date().timeIntervalSince1970, forKey: "openSession.updatedAt")
    }

    private func clearOpenSessionSnapshot() {
        let d = Prefs
        d.removeObject(forKey: "openSession.start")
        d.removeObject(forKey: "openSession.active")
        d.removeObject(forKey: "openSession.updatedAt")
    }

    /// If the app (or the Mac) died mid-session, the last checkpoint survives
    /// here. PEEKS only — call `clearCrashedSessionSnapshot()` AFTER the
    /// record has actually been persisted, so a failed recovery can retry on
    /// the next launch instead of silently dropping money.
    static func peekCrashedSession() -> SessionRecord? {
        let d = Prefs
        let start = d.double(forKey: "openSession.start")
        let active = d.double(forKey: "openSession.active")
        let updated = d.double(forKey: "openSession.updatedAt")
        guard start > 0, active >= 1, updated > start else { return nil }
        return SessionRecord(start: Date(timeIntervalSince1970: start),
                             end: Date(timeIntervalSince1970: updated),
                             activeSeconds: active)
    }

    static func clearCrashedSessionSnapshot() {
        let d = Prefs
        d.removeObject(forKey: "openSession.start")
        d.removeObject(forKey: "openSession.active")
        d.removeObject(forKey: "openSession.updatedAt")
    }

    /// Public so AppModel can force-close on project switch — the closed span
    /// belongs to the project that was active while it ran.
    func closeSessionNow(reason: String) {
        closeSessionIfOpen(reason: reason)
    }

    private func closeSessionIfOpen(reason: String) {
        if let record = accumulator.endSession() {
            closedSessions.append(record)
            // In-memory diagnostics only (persistence is via onSessionClosed);
            // cap so a weeks-long run can't grow unboundedly.
            if closedSessions.count > 20 { closedSessions.removeFirst() }
            clearOpenSessionSnapshot()
            logger.log(event: "session-closed", detail: "reason=\(reason) active=\(Int(record.activeSeconds))s")
            onSessionClosed?(record)
        }
    }

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isAsleep = true
                self?.tick(accumulate: false)
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isAsleep = false
                self?.tick(accumulate: false)
            }
        }
    }

    private func describe(_ s: DetectionState) -> String {
        switch s {
        case .recording: return "recording"
        case .paused(let r): return "paused(\(r.rawValue))"
        }
    }
}
