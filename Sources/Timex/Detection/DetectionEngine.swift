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
    /// Why the clock is running, for the UI to say out loud. nil when not
    /// recording.
    private(set) var recordingSource: RecordingSource?
    /// Non-nil during the last seconds before an idle pause — the UI shows
    /// the "still working?" panel from this.
    private(set) var idleWarning: IdleWarning?
    /// A gap the user may reclaim, offered once on resume. nil when there is
    /// nothing to offer or the offer lapsed.
    private(set) var reclaimOffer: ReclaimOffer?
    /// Where a reclaim-eligible gap began: set when an AUTOMATIC pause closes
    /// a session (idle, or bridge expiry), cleared by the sacred boundaries.
    private var reclaimGapStart: Date?
    /// When the user last answered the panel. An attestation counts as
    /// input: the click that delivers it usually IS system input, but a
    /// VoiceOver activation may not synthesise a CGEvent, so the engine
    /// takes the answer directly rather than hoping the probe saw it.
    private var lastPresenceConfirm: Date?
    /// Closed sessions this run — milestone (b) moves these into SwiftData.
    private(set) var closedSessions: [SessionRecord] = []

    /// PERSISTED. A pause the user set must not be lifted by quitting,
    /// crashing, or restarting overnight — that is the one way this boundary
    /// used to un-set itself, silently, in the billing direction, and
    /// invisibly, because a relaunched app looks exactly like one that was
    /// never paused.
    var manuallyPaused: Bool {
        didSet {
            guard manuallyPaused != oldValue else { return }
            defaults.set(manuallyPaused, forKey: PauseState.pausedKey)
        }
    }
    /// When the current manual pause began — nil while not paused. Persisted
    /// alongside the flag so a pause restored at launch reports its real age
    /// and the forgotten-pause hint fires immediately instead of restarting
    /// its 15-minute clock.
    private(set) var manualPauseStart: Date?
    /// Flips true once a manual pause exceeds 15 minutes — the pill shows
    /// a hint so a forgotten pause doesn't silently eat a billable day.
    private(set) var pausedLong = false
    static let longPauseThreshold: TimeInterval = 900
    /// What a manual pause does when anchor work is seen again.
    /// What a manual pause does when anchor work is seen again. Read from the
    /// injected defaults in `init` — never from the global store here.
    var autoResume: AutoResumeMode
    /// Sustained anchor input needed before a paused timer reacts — a glance
    /// at Resolve during a call must not wake the clock.
    static let resumeSignalDuration: TimeInterval = 45
    /// "Stay paused" is respected for this long before asking again.
    static let resumePromptCooldown: TimeInterval = 900
    private var resumeSignalStart: Date?
    private var lastResumePrompt: Date?
    /// Paused by hand, yet the editor is clearly working — panel and pill
    /// surface this so the Resume is one click away.
    private(set) var workDetectedWhilePaused = false
    /// Ask mode: fired when work is detected during a manual pause.
    var onResumePrompt: (() -> Void)?
    var idleThreshold: TimeInterval = Prefs.object(forKey: "idleThreshold") as? TimeInterval ?? 120
    var hasActiveProject = true
    /// Both lists come from the injected defaults in `init` — a property
    /// initializer here would read the global store behind the injection.
    var workAppPrefixes: [String]
    var satellitePrefixes: [String]
    var bridgeGrace: TimeInterval = Prefs.object(forKey: "bridgeGrace") as? TimeInterval ?? 180
    /// Research window: satellite apps sustain recording only this long after
    /// the last anchor (Resolve/Adobe) activity.
    var satelliteWindow: TimeInterval = Prefs.object(forKey: "satelliteWindow") as? TimeInterval ?? 1200
    /// Opt-in: keep billing while a render burns cpu with nobody touching the
    /// keyboard. OFF by default — every other rule in this app resolves
    /// ambiguity toward under-billing, and this one resolves the other way.
    var renderExemption: Bool = Prefs.bool(forKey: "idleRenderExemption")
    /// % of one core, sustained, that counts as "rendering". Machines differ;
    /// this is the knob to turn if idle Resolve trips it (or a render doesn't).
    static let renderCPUThreshold: Double = 50
    /// An unattended overnight render is not a working day. The exemption
    /// expires after this long and the idle pause takes over as usual.
    static let renderExemptionCap: TimeInterval = 1800
    /// Two samples make a rate; the probe stays stateless, the engine remembers.
    private var lastCPUSample: (nanos: UInt64, at: Date)?
    /// When the current exemption started carrying an idle stretch.
    private(set) var renderExemptStart: Date?
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
    /// Injected so the engine never reads global mutable state at
    /// construction — a store that is shared with every other engine ever
    /// built is exactly as testable as a global variable, which is to say
    /// not at all.
    private let defaults: UserDefaults
    private var isAsleep = false
    private var timer: Timer?
    /// nil until the first checkpoint. Optional rather than seeded with
    /// `Date()`, because a seed taken at construction is a wall-clock reading
    /// smuggled past the injectable clock.
    private var lastCheckpoint: Date?

    init(probes: any SystemProbing = SystemProbes(), logger: SessionLogger = SessionLogger(),
         defaults: UserDefaults = Prefs) {
        self.probes = probes
        self.logger = logger
        self.defaults = defaults
        self.workAppPrefixes = AnchorSet.globalList(saved: defaults.stringArray(forKey: "workApps"))
        self.satellitePrefixes = defaults.stringArray(forKey: "satelliteApps") ?? DetectionInput.defaultSatellitePrefixes
        self.autoResume = AutoResumeMode(rawValue: defaults.string(forKey: "autoResume") ?? "") ?? .ask
        // A pause the user set outlives the process that set it.
        self.manuallyPaused = defaults.bool(forKey: PauseState.pausedKey)
        self.manualPauseStart = PauseState.restoredStart(from: defaults)
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

    /// The user said yes: the away time was work. Credited into the running
    /// session at the moment of acceptance — the only path that ever bills a
    /// reclaimed gap, and it requires an explicit click.
    func acceptReclaim() {
        guard let offer = reclaimOffer else { return }
        reclaimOffer = nil
        guard accumulator.sessionStart != nil else { return }
        accumulator.credit(offer.seconds)
        logger.log(event: "reclaim-accepted", detail: "credited=\(Int(offer.seconds))s")
    }

    /// No — or a project switch, which makes the offer meaningless: the gap
    /// belongs to the project that was selected when it opened.
    func declineReclaim() {
        reclaimOffer = nil
    }

    /// The user answered the "still working?" panel.
    func confirmPresence() {
        lastPresenceConfirm = now()
        // Re-evaluate immediately but do NOT accumulate — same rule as
        // togglePause: only the 1 Hz timer adds seconds.
        tick(accumulate: false)
    }

    func togglePause() {
        manuallyPaused.toggle()
        manualPauseStart = manuallyPaused ? now() : nil
        PauseState.persist(start: manualPauseStart, to: defaults)
        pausedLong = false
        resumeSignalStart = nil
        lastResumePrompt = nil
        workDetectedWhilePaused = false
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
        // An attestation is input. Applied before the probes' value is used
        // anywhere, so the idle pause, the research window and the render
        // exemption all see it the same way.
        var sinceInput = probes.secondsSinceLastInput()
        if let confirmed = lastPresenceConfirm {
            sinceInput = min(sinceInput, now().timeIntervalSince(confirmed))
        }
        var input = DetectionInput(
            frontmostBundleID: probes.frontmostBundleID(),
            secondsSinceInput: sinceInput,
            idleThreshold: idleThreshold,
            manuallyPaused: manuallyPaused,
            isAsleep: isAsleep,
            hasActiveProject: hasActiveProject,
            workAppPrefixes: workAppPrefixes
        )
        input.satellitePrefixes = satellitePrefixes
        reactToWorkWhilePaused(&input)
        // Anchor activity (anchor app frontmost + fresh input) refreshes the
        // research window; satellites sustain recording only inside it.
        if input.frontmostIsAnchor, input.secondsSinceInput < idleThreshold {
            lastAnchorActive = now()
        }
        input.satelliteWindowOpen = lastAnchorActive.map {
            now().timeIntervalSince($0) <= satelliteWindow
        } ?? false
        input.renderExemptionActive = evaluateRenderExemption(input)
        let newState = DetectionState.evaluate(input)
        if newState != state {
            logger.log(event: "transition", detail: describe(newState), input: input)
            switch newState {
            case .paused(.manual), .paused(.systemSleep), .paused(.noProject):
                // HARD boundaries: the bridge must never span time the user
                // explicitly paused, slept through, or worked project-less.
                // Close regardless of previous state and kill any open gap.
                // Reclaim follows the same rule: a sacred pause is never
                // offered back — sleeping through the night must not wake up
                // to an "add 8 hours?" card.
                closeSessionIfOpen(reason: describe(newState))
                awayGapStart = nil
                reclaimGapStart = nil
            case .paused(.notFrontmost) where state == .recording:
                // Bridge window: keep the session open — a quick detour is
                // bridged retroactively on return; closes on grace expiry.
                awayGapStart = now()
            case .paused where state == .recording:
                // An idle pause is automatic — the user never asked for it —
                // so the gap it opens is reclaim-eligible. The billed idle
                // tolerance before this moment stays billed; the gap starts
                // where the billing stopped.
                closeSessionIfOpen(reason: describe(newState))
                reclaimGapStart = now()
            case .paused(.inputIdle) where awayGapStart != nil:
                // The bridge was still holding a session open when the idle
                // pause landed — the frontmost app became an anchor with
                // nobody typing (the detour app quit, say). This transition
                // used to fall through: nothing closed, and the expiry check
                // below only fires on notFrontmost, so the session stayed
                // open until midnight and the gap was never offered back.
                closeSessionIfOpen(reason: "bridge-idle")
                reclaimGapStart = awayGapStart
                awayGapStart = nil
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
                // Returning to work is the one moment a reclaim can be
                // offered. Floor: the bridge's own grace — detours shorter
                // than that are already the bridge's business, so the offer
                // starts where the bridge ends. Cap and same-day guard keep
                // a mistaken click from ever moving serious money or
                // bleeding across a day boundary.
                if let gapStart = reclaimGapStart {
                    let gap = now().timeIntervalSince(gapStart)
                    if gap > bridgeGrace, gap <= ReclaimOffer.maximumGap,
                       Calendar.current.isDate(gapStart, inSameDayAs: now()) {
                        reclaimOffer = ReclaimOffer(start: gapStart, end: now())
                        logger.log(event: "reclaim-offered", detail: "gap=\(Int(gap))s")
                    }
                    reclaimGapStart = nil
                }
            }
            state = newState
        }
        // Grace expired while away → the session finally closes, gap uncounted.
        if state == .paused(.notFrontmost), let gapStart = awayGapStart,
           now().timeIntervalSince(gapStart) > bridgeGrace {
            closeSessionIfOpen(reason: "bridge-expired")
            // The reclaimable gap starts when the user LEFT, not when the
            // bridge gave up — the whole away span went unbilled.
            reclaimGapStart = gapStart
            awayGapStart = nil
        }
        let source = RecordingSource.evaluate(state: newState, input: input,
                                              lastAnchorActive: lastAnchorActive,
                                              window: satelliteWindow, now: now())
        if source != recordingSource { recordingSource = source }
        var warning = IdleWarning.evaluate(state: newState,
                                           secondsSinceInput: input.secondsSinceInput,
                                           idleThreshold: idleThreshold,
                                           renderExemptionActive: input.renderExemptionActive)
        // A full-screen ANCHOR is the one place the card is harmful: playback
        // in front of a client generates no input, and a floating "still
        // working?" over the picture is worse than the silent pause the app
        // always had. Suppressed, the pause lands at the threshold exactly as
        // it did before the panel existed. A full-screen BROWSER does not
        // suppress — an evening of full-screen video is precisely what the
        // idle pause exists for. The probe is only consulted inside the
        // warning window, so the window-list walk is not a per-second cost.
        if warning != nil, input.frontmostIsAnchor, probes.frontmostWindowIsFullScreen() {
            warning = nil
        }
        if warning != idleWarning { idleWarning = warning }
        // The offer lives only while the session it would credit is running,
        // and answers itself with No when ignored.
        if reclaimOffer != nil {
            if newState != .recording {
                reclaimOffer = nil
            } else if let offer = reclaimOffer,
                      now().timeIntervalSince(offer.end) > ReclaimOffer.duration {
                logger.log(event: "reclaim-lapsed")
                reclaimOffer = nil
            }
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
        let checkpointDue = lastCheckpoint.map { now().timeIntervalSince($0) >= 15 } ?? true
        if newState == .recording, checkpointDue {
            logger.log(event: "checkpoint", detail: "activeSeconds=\(Int(accumulator.activeSeconds))")
            lastCheckpoint = now()
            snapshotOpenSession()
        }
        onTick?()
    }

    /// Called after every tick — AppModel hooks project auto-detection here.
    var onTick: (() -> Void)?

    /// Is an anchor app provably rendering through this idle stretch?
    /// Sampled every tick so the rate is always fresh, but it can only ever
    /// suppress the idle pause — never start a session, never outrank a
    /// manual pause, and never run past the cap.
    private func evaluateRenderExemption(_ input: DetectionInput) -> Bool {
        let t = now()
        let nanos = probes.workAppCPUNanos(matching: workAppPrefixes)
        let previous = lastCPUSample
        lastCPUSample = (nanos, t)
        guard renderExemption else { renderExemptStart = nil; return false }
        // Below the idle threshold the user is present; nothing to exempt.
        guard input.secondsSinceInput >= idleThreshold else { renderExemptStart = nil; return false }
        guard let previous, nanos >= previous.nanos else { return false }
        let elapsed = t.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return renderExemptStart != nil }
        let percent = Double(nanos - previous.nanos) / 1_000_000_000 / elapsed * 100
        guard percent >= Self.renderCPUThreshold else { renderExemptStart = nil; return false }
        let started = renderExemptStart ?? t
        renderExemptStart = started
        // Cap reached: stop exempting, and do not re-arm until input returns.
        return t.timeIntervalSince(started) <= Self.renderExemptionCap
    }

    /// Resume from the notification / panel — a no-op unless paused by hand.
    func resume() {
        if manuallyPaused { togglePause() }
    }

    /// A manual pause is sacred while the editor is away. Once an ANCHOR app
    /// is frontmost with live input for `resumeSignalDuration`, the pause is
    /// evidently forgotten: auto mode lifts it, ask mode prompts. Satellites
    /// never count — browsing is ambiguous, editing in Resolve is not.
    /// ponytail: the signal window itself stays unbilled (under-billing rule).
    private func reactToWorkWhilePaused(_ input: inout DetectionInput) {
        guard manuallyPaused, autoResume != .off else {
            resumeSignalStart = nil
            if workDetectedWhilePaused { workDetectedWhilePaused = false }
            return
        }
        if input.frontmostIsAnchor, input.secondsSinceInput < 10 {
            if resumeSignalStart == nil { resumeSignalStart = now() }
        } else if !input.frontmostIsAnchor || input.secondsSinceInput >= 60 {
            resumeSignalStart = nil
        }
        let sustained = resumeSignalStart.map {
            now().timeIntervalSince($0) >= Self.resumeSignalDuration
        } ?? false
        if sustained != workDetectedWhilePaused { workDetectedWhilePaused = sustained }
        guard sustained else { return }
        switch autoResume {
        case .auto:
            logger.log(event: "auto-resume", detail: "anchor work during manual pause")
            togglePause()
            // Same tick evaluates as resumed — no phantom paused(.manual) frame.
            input.manuallyPaused = false
        case .ask:
            let due = lastResumePrompt.map {
                now().timeIntervalSince($0) >= Self.resumePromptCooldown
            } ?? true
            if due {
                lastResumePrompt = now()
                logger.log(event: "resume-prompt")
                onResumePrompt?()
            }
        case .off:
            break
        }
    }

    private func snapshotOpenSession() {
        guard let start = accumulator.sessionStart else { return }
        defaults.set(start.timeIntervalSince1970, forKey: "openSession.start")
        defaults.set(accumulator.activeSeconds, forKey: "openSession.active")
        // The engine's clock, like everything else here — this stamp becomes
        // a recovered session's END after a crash.
        defaults.set(now().timeIntervalSince1970, forKey: "openSession.updatedAt")
    }

    private func clearOpenSessionSnapshot() {
        defaults.removeObject(forKey: "openSession.start")
        defaults.removeObject(forKey: "openSession.active")
        defaults.removeObject(forKey: "openSession.updatedAt")
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

    /// Forensics for the detection pipeline. The first live Tier-1 run
    /// failed unexplainedly and the log could not say why, because it only
    /// records STATE transitions — a detection attempt that returns nothing
    /// causes no transition and left no trace. Now every attempt leaves one.
    func logDetection(_ event: String, detail: String = "") {
        logger.log(event: event, detail: detail)
    }

    /// Public so AppModel can force-close on project switch — the closed span
    /// belongs to the project that was active while it ran.
    func closeSessionNow(reason: String) {
        closeSessionIfOpen(reason: reason)
    }

    private func closeSessionIfOpen(reason: String) {
        // The engine's clock decides when a session ended — and therefore,
        // through DaySplitter, which DAY it bills to. This was the one moment
        // in the engine that read the wall clock instead.
        if let record = accumulator.endSession(at: now()) {
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
