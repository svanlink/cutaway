# Detection audit and rulings — 2026-09-07

*Verified against the installed builds (Resolve 21.0.4, AE 26.3.0, PS 27.10.0, AI 30.8.1, ID 21.5.1, PPro 26.3.2) and Apple's docs. Floor: macOS 14.0. Unsandboxed; Hardened Runtime NO (`project.pbxproj:824`).*

## 1. Audit — where the clock is wrong

### Bills time the owner was not present for

**A. The render exemption, four leaks.**
- `SystemProbes.swift:97-110` sums CPU across **every** running anchor and hard-codes `resolveBundleIDs` on top of the project's prefixes → an InDesign-only project (whose `AnchorSet` deliberately excludes Resolve) bills Resolve's background render.
- `DetectionState.swift:137` gates on `isWorkContext`, not `frontmostIsAnchor` → Safari frontmost inside the research window + Resolve rendering + owner asleep = billed.
- `DetectionEngine.swift:328` clears `renderExemptStart` on any fresh input, so the 30-minute cap is **per idle stretch, not per day** → one keystroke an hour overnight bills 30 min a touch, unbounded.
- `DetectionState.swift:188` suppresses the idle warning while exempt — the one rule that bills unattended time is also the only silent one.

**B. Fast user switching is unobserved.** Nothing observes `NSWorkspace.sessionDidResignActiveNotification` ("before a user session switches out" — Apple); while switched out `frontmostBundleID()` still reports Resolve. `.combinedSessionState` is scoped to "the current user login session" (Apple), so the other user's typing does not leak in — exposure is capped at `idleThreshold` (120 s) per switch. **With the render exemption on, uncapped.**

**C. Display sleep and lid close are unobserved.** `NSWorkspace.screensDidSleepNotification` (10.6+) is never registered, and clamshell on external power keeps the system awake so `willSleepNotification` never fires. Same 120 s / unbounded split as (B).

**D. Synthetic input counts as presence.** `SystemProbes.swift:71` uses `.combinedSessionState` — "all event sources posting to the current user login session" (Apple) — which includes CGEvents *posted by software*: a jiggler, Keyboard Maestro, screen sharing, an Adobe script. `.hidSystemState` ("all hardware event sources posting from the HID system") is honest but loses FUS isolation; fix is `.hidSystemState` **plus** (B).

**E. Forgotten-pause resume fires on one event, not 45 s of input.** `DetectionEngine.swift:359-367`: `resumeSignalStart` is set when input is <10 s old and cleared only at ≥60 s, so the 10–60 s band *holds* the signal. Manual pause, owner clicks Resolve once at 12:00:00 and leaves → in `.auto`, resume at 12:00:45, idle pause at 12:02:00: 75 s billed to an empty chair, and a pause the owner set lifted by one click. `.ask` (default) is safe. Fix: `guard sustained, input.secondsSinceInput < 10`.

### Loses time the owner *was* present for

**F. InDesign is not an anchor** (`DetectionState.swift:76-82` lists AE, Photoshop, PremierePro, illustrator, Audition; installed InDesign 2026 is `com.adobe.InDesign`). Every InDesign hour is `paused(.notFrontmost)`; Media Encoder likewise. The largest silent loss in the file.

**G. `hasPrefix` is case-sensitive** (`:114`) while `sanitizedPrefixes` dedupes case-*insensitively* (`:104`) — typing `com.adobe.indesign` in Settings gives a list that looks right and matches nothing.

**H. Tier 2 polls AX on the main thread every 5 s** (`AppModel.swift:180` → `ProjectDetector.swift:54,58`, synchronous, no `AXUIElementSetMessagingTimeout`). Resolve mid-render or showing a modal does not answer; ticks missed beyond 5 s are truncated by the delta cap (`:298`) → under-bill, plus a beachball.

**I. `resolveEdition()` lies** (`ProjectDetector.swift:38-40`): `…/Developer/Scripting` is the Studio marker, but that directory **exists on this machine, which runs the free edition**.

**J. Resolve quitting is unhandled.** `DetectionFollower.reset()` has no caller (`:42`) and nothing observes `didTerminateApplicationNotification`, so `ProjectDetector.swift:50` returns `lastDetectedName` forever.

**K. Midnight is correct but lossy.** `:189-192` force-closes properly and `:253`'s guard correctly refuses a bridge credit across the rollover, dropping up to 3 min of real work — acceptable, but say it out loud. `lastAnchorActive`, `awayGapStart` and `renderExemptStart` all survive it.

**L. Four tunables read the global `Prefs`, not the injected store** (`:63`, `:69`, `:72`, `:76`) — the defect `:65-68` warns about for the app lists.

## 2. Ruling: delete the render exemption

**Delete it.** Not "swap the evidence".

1. The only rule that bills without a presence signal; everything else needs a HID event inside the threshold or an explicit human act.
2. **CPU is evidence about the machine, not the man.** Resolve generates Smart User Cache, optimized media, waveforms and transcriptions by itself — Blackmagic ships `Resolve.DisableBackgroundTasksForCurrentResolveSession` (Scripting README, 21.0 Beta) precisely because those run unattended. A 50 %-of-one-core threshold is a Resolve-is-open detector.
3. Four independent implementation leaks (§1A), each of which alone bills a night.
4. **The idle-threshold picker already covers the stated need** — 30 minutes is honest, symmetric (it protects reading and thinking too), and needs no new machinery.
5. No surveyed tracker uses render CPU. Not an oversight.

**On the 2026-09-05 counter-proposal, `kIOPMAssertionTypePreventUserIdleDisplaySleep`: reject.** It answers "does some app want the display awake", not "is the owner in front of it". Resolve holds it *during renders and playback* — the exact unattended case. Cheaper to read than CPU, equally blind. Timing can use it because Timing is a diary; Cutaway is an invoice.

**If overruled, the only version I sign is a prompt, not a billing rule:** when input goes stale while the **frontmost** anchor's own pid holds `PreventUserIdleDisplaySleep`, show the existing "still working?" card *without a timeout* instead of pausing silently, and bill only from the answer forward. Evidence: that assertion, that pid, frontmost. Ceiling: none needed — a human answered.

## 3. Energy and correctness upgrades, ranked

1. **Delete `evaluateRenderExemption`.** `DetectionEngine.swift:322-325` calls `workAppCPUNanos` **before** the `guard renderExemption` at `:326`: every user pays an `NSWorkspace.runningApplications` allocation plus a `proc_pid_rusage` per anchor, 86,400×/day, for a toggle almost nobody sets. Biggest energy win and §2's correctness win in one diff.
2. **AXObserver for Resolve's title.** `AXObserverCreate` + `AXObserverAddNotification` (10.2+) on the **app** element for `kAXFocusedWindowChangedNotification` (10.2+), re-subscribing `kAXTitleChangedNotification` (10.5+) on the focused window at each focus change — Apple's caveat: the *system-wide* element supports no notifications. Permission: Accessibility (`AXIsProcessTrusted`); denied → `kAXErrorAPIDisabled` / `kAXErrorCannotComplete`, fall back to Tier 3 manual, never Screen Recording. Replaces ~17,280 AX round trips/day with one per project switch and removes §1H.
3. **Stop the 1 Hz timer when nothing can be lost.** 1 Hz is needed only in `.recording` and during the 30 s warning lead. In `.paused(.manual)`, `.paused(.systemSleep)`, `.paused(.noProject)` and `.paused(.notFrontmost)` outside a bridge window, 5 s is exact — the 45 s forgotten-pause signal and the 15-minute hint tolerate it, and accumulation uses wall deltas (`:298`), so cadence never changes a number. On `willSleepNotification`, `invalidate()` rather than let a timer wake the machine. Tolerance at `0.5` on 1 s (`:146`) is already right — Apple: it "increases the ability of the system to optimize for increased power savings"; go to 0.9× on the paused cadence only.
4. **Hard boundaries for the three unobserved transitions.** `screensDidSleep`/`screensDidWake` and `sessionDidResignActive`/`sessionDidBecomeActive`, treated exactly like `willSleep`/`didWake` (close the session, kill `awayGapStart`); plus `didTerminateApplicationNotification` for Resolve → `follower.reset()`, clear `lastDetectedName` (§1J).
5. **Cache the repeated probes.** `frontmostWindowIsFullScreen()` runs every second for the whole 30 s lead though it cannot change without a window event — compute once per warning. Memoize `resolveEdition()` (a `fileExists` + app scan, read from SwiftUI at `SettingsView.swift:128`) and fix its Studio marker (§1I): the only honest test is whether `fuscript` answers.
6. **Add `com.adobe.InDesign`** and lowercase both sides of `hasPrefix` (§1F, §1G).

## 4. Adobe project names via Automation — per-app reality

**Permission (all four):** Automation, one prompt per (Cutaway → target) pair, macOS 10.14+. Requires `NSAppleEventsUsageDescription` in `Info.plist` — **currently absent**; without it every event is refused `errAEEventNotPermitted` (−1743) and **no prompt appears at all**. Once Hardened Runtime is on for notarization, add `com.apple.security.automation.apple-events`. Probe silently with `AEDeterminePermissionToAutomateTarget` (10.14+). The alert names Cutaway and the target, says allowing control provides access to that app's documents and data, and shows Cutaway's usage string. **Denied → −1743 on every later event, permanently, until flipped in System Settings ▸ Privacy & Security ▸ Automation.** The grant also dies when Cutaway's code signature changes. On failure: fall back to the manual selection, never loop, never re-prompt.

Verified from each app's own dictionary (`sdef`, today, on the installed 2026 builds):

| App | Build | Route | No document open |
|---|---|---|---|
| **After Effects** | 26.3.0 | **Only** `DoScript` / `DoScriptFile` — no `document` class. Send `DoScript` with ExtendScript reading `app.project.file`. | AE always has a project (launches into Untitled), so `app.project.file` is **null** when unsaved. Treat null and "Untitled Project" as no name. |
| **Photoshop** | 27.10.0 | `application.current document` ("the frontmost document") → `document.name`, `document.file path`. | Object-not-found OSA error (−1728). |
| **Illustrator** | 30.8.1 | `application.current document` ("The active document") → `document.name`, `document.file path`. | Same −1728. |
| **InDesign** | 21.5.1 | `application.active document` ("The front-most document") → `document.name`, `document.full name`, `document.saved`. | Same −1728. |

Implementation rules: read **only** on `didActivateApplicationNotification`, one query per activation, cached by pid, off the main thread with a watchdog — `DoScript` blocks while AE has a modal sheet up. Keep the ExtendScript a compile-time constant; `DoScript` is a write-capable channel. Treat *any* error, empty string or "Untitled" as no name. Adobe names may **select** an existing project, never create one.

**Premiere Pro — confirmed twice.** Its full dictionary today is two commands, `capture` and `editoriginal`: no document, project or application class at all. Timing's current FAQ says plainly that "Some apps, such as Adobe Premiere Pro, do not share their window title through the Accessibility API", naming Screen Recording as the only route; UXP `Project.name` runs only inside a panel. **Premiere stays an anchor with no project name, permanently.** Say so in the UI rather than looking broken.

## 5. DaVinci Resolve scripting reality, 21.0.4

Verified against the installed bundle and Blackmagic's own `Developer/Scripting/README.txt` (last updated **24 Jul 2026**):

- **`fuscript` is at `…/DaVinci Resolve.app/Contents/Libraries/Fusion/fuscript`** — present and executable here, so `ProjectDetector.fuscriptCandidates()` is correct. `fusionscript.so` sits beside it as the `RESOLVE_SCRIPT_LIB` for the Python route.
- **The blanket "Studio-only" claim needs correcting.** README §"Studio and AI Scripting APIs": *"The DaVinci Resolve scripting APIs cover a common superset of functions for both the Free and Studio versions"*, with calls returning False when *"the function references a Studio function from the free DaVinci Resolve version."* `GetProjectManager()`, `GetCurrentProject()`, `GetName()` and `GetProjectAttributesInCurrentFolder()` carry **no** Studio marker.
- **The gate that matters is the product switch, not the API.** README: *"By default, scripts can be invoked from the Console window in the Fusion page, or via command line. This permission can be changed in Resolve Preferences…"* — Preferences ▸ System ▸ General ▸ *External scripting using* (None / Local / Network). The 19.1-era reports of Free refusing the external endpoint describe this gate.
- **Not verified, and I will not guess:** whether free 21.0.4 answers `fuscript` externally. Resolve was not running and I did not launch it. One command settles it, with a project open and *External scripting using* = Local: `"/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fuscript" -l lua -x 'r=Resolve(); print(r and r:GetProjectManager():GetCurrentProject():GetName() or "nil")'`. Run that before spending more effort on Tier 1.
- **Sandboxing:** unsandboxed is *required* — App Sandbox suppresses the `AXIsProcessTrustedWithOptions` prompt, forbids `Process` spawning `fuscript`, and blocks reads under `/Library/Application Support/Blackmagic Design/`. Hardened Runtime breaks none of these; it only adds §4's entitlement.

## 6. What detection must never do

1. **Never bill on machine activity** — CPU, GPU, disk, network, render queues, background tasks, power assertions. Presence is a HID event or a human act, nothing else. Standing answer to the render exemption, the display-sleep assertion, and whatever comes next.
2. **Never take Screen Recording** — not for Premiere titles, not for OCR, not "only window names".
3. **Never poll a foreign app's Accessibility tree from the main thread on a timer.** Push, or nothing.
4. **Never resume a paused clock on a single event** — live input across the whole signal window, or a click.
5. **Never let a rule that adds time be silent.** Anything holding the clock past the threshold shows in the pill and says why.
6. **Never let an async detection overrule a choice made since it started** (`ManualIntent`, every path).
7. **Never send a state-changing command to an editing app** — never `open`, `save`, `quit`, or a side-effecting `DoScript`.
8. **Never re-arm a ceiling on the evidence that opened it.** Caps count against the day, not the stretch.
9. **Never create a project from an inferred name** — titles and Adobe names select; only Tier 1 and the user create.
10. **Never keep a per-second cost only an opt-in minority needs.**

## Sources

Apple (documentation JSON, fetched 2026-09-07): [`CGEventSourceStateID`](https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid), [`NSWorkspace.sessionDidResignActiveNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification), [`sessionDidBecomeActiveNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification), [`screensDidSleepNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification), [`AXObserverAddNotification`](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification), [`kAXFocusedWindowChangedNotification`](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowchangednotification), [`kAXTitleChangedNotification`](https://developer.apple.com/documentation/applicationservices/kaxtitlechangednotification), [`Timer.tolerance`](https://developer.apple.com/documentation/foundation/timer/tolerance), [`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription), [`AEDeterminePermissionToAutomateTarget`](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet). Blackmagic Design: `/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/README.txt` and `CHANGELOG.txt`, Resolve 21.0.4, last updated 24 Jul 2026 / 5 May 2026. Adobe: application dictionaries via `sdef` on the installed builds listed above. Timing: [FAQ](https://timingapp.com/help/faq) (Premiere hides its title from Accessibility; Resolve yields no project details).

---

## Arbitration 2026-09-07: who owns the clock

**One repeating timer. The engine tick owns it. Cadence varies; it stops for exactly
one reason.** Architecture wins the timer count, detection the cadence. Neither wins
the thing it asked for.

### 1. The timer inventory

| Timer | Owner | Interval | Tolerance | May stop |
|---|---|---|---|---|
| Engine tick | `DetectionEngine` | 1 s live · 5 s idle | 0.5 · 4.5 | Only on `willSleepNotification` |

Nothing else repeats. `backupTimer` and `startBackupSchedule()` are deleted; Tier 2's
AX read becomes an `AXObserver` (detection §3.2). Notifications are events, not clocks.

**"Live" cadence (1 s) is mandatory whenever any of these is true:** `state ==
.recording`; a bridge window is open (`awayGapStart != nil`); an `idleWarning` is armed
or within its 30 s lead. **Idle cadence (5 s)** applies in `.paused(.manual)`,
`.paused(.noProject)`, `.paused(.systemSleep)`, and `.paused(.notFrontmost)` outside a
bridge. Cadence is derived, never stored — one `applyCadence()` at the end of `tick()`
and after every wake-up event.

### 2. Detection loses "stop entirely"

The tick may not stop on manual pause. Three obligations run only while paused: the
45 s forgotten-pause signal, the 15-minute `pausedLong` hint, the resume prompt. A
stopped clock cannot see the owner come back — that is a lost session, so
**correctness beats energy here explicitly**. 5 s at 4.5 s tolerance is invisible in
Activity Monitor and still watches.

The tick invalidates on `willSleepNotification` only, because the machine itself has
stopped. `screensDidSleep` and `sessionDidResignActive` close the session hard but keep
the slow tick: the Mac is still running, still being written to, still able to wake.

### 3. Architecture loses `tickCount % 1800`

The backup check belongs **on the engine tick, keyed on wall-clock**, never on a tick
counter. Under a variable cadence 1800 ticks is anywhere from 30 minutes to 2.5 hours,
and a counter survives sleep while wall time does not. `BackupPolicy.isDue(last:now:)`
already compares `Date`s; call it when `now() - lastCheck >= checkEvery`.

The dissolution argument — "a stopped engine means nothing to back up" — **fails, and
this is why the tick may not stop on pause.** The store is written by user actions that
need no recording state: creating a project, editing a rate, adjusting a day. A machine
that never quits Cutaway has no other backup path; the launch backup fires once, years
ago. It survives only because the tick keeps running through every pause. During system
sleep the tick is gone but so is the user, and the first post-`didWake` tick evaluates
`isDue` before anything can be lost. Overnight render: recording, 1 Hz, unaffected.

### 4. Wake-up paths that re-arm the clock

`didWakeNotification` → `start()` (resets `lastTick`) + `tick(accumulate:false)`.
`screensDidWake` / `sessionDidBecomeActive` → hard-boundary close, then re-evaluate.
`didActivateApplicationNotification` → escalate to 1 Hz and tick immediately, so an
anchor coming forward starts the clock that second, not five later. `togglePause`,
`resume`, `confirmPresence` already tick; they must re-apply cadence.

**The invariant that makes stopping safe:** accumulation uses the wall delta, clamped to
5 s (`DetectionEngine.swift:298`). That clamp holds only because idle cadence never
covers `.recording` — if it ever did, a coalesced tick would silently under-bill. Live
cadence while recording is a billing invariant, not a preference.

### 5. The status item rides the survivor

Yes. `onEngineTick` redraws a figure that only moves while recording, and recording is
1 Hz. Paused, a 5 s redraw is invisible; the wake tick repaints before any pixel is.
Take the Ice fix (compare string, then measure) so the slow path costs nothing.

### 6. The test that fails if this is built wrong

`BackupScheduleTests.testBackupFiresOncePerDayAcrossCadenceChangesAndSleep`: injected
clock, 26 virtual hours — 8 h recording at 1 Hz, 10 h manual pause at 5 s, a
willSleep/didWake pair spanning 6 h — assert `backUpNow` fired exactly once, that billed
seconds across the sleep boundary are zero, and that no session was closed twice. A
tick-counter implementation fires early and repeatedly; a stop-on-pause implementation
never fires at all.

**Accepted risk:** an anchor becoming frontmost with no accompanying activation
notification (a Space switch to an already-frontmost app) is noticed up to 5 s late.
That direction under-bills, which is the side this app is built to err on.
