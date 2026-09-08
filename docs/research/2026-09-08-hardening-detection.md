# Hardening audit — detection after the "Resolve is the source of truth" change

Date: 2026-09-08 · HEAD `648d6aa` · scope: `Sources/Cutaway/Detection/*`,
`Sources/Cutaway/App/AppModel.swift`, `Sources/Cutaway/MenuBar/PromptPanel.swift`,
`Sources/Cutaway/MenuBar/MenuBarPanel.swift`, `Sources/Cutaway/Projects/ProjectsModel.swift`.

Nothing in `Sources/` was modified. This is a read-only audit.

## What changed today, and what it actually bought

Two commits landed under incident pressure:

- `14ddd77` — an unknown project name raises a card instead of silently creating a project.
- `648d6aa` — `PauseReason.projectMismatch`, evaluated in `DetectionState.evaluate`
  before frontmost and idle (`DetectionState.swift:157`); Adobe document-name
  detection deleted.

The pure state machine is correct. `DetectionState.evaluate` orders the reasons
exactly as the doctrine requires — manual, sleep, noProject, mismatch, frontmost,
idle (`DetectionState.swift:150-163`) — and `ProjectMismatchTests` pins that
ordering properly.

Everything wrong is in the wiring *around* it: what sets `projectMismatch`, what
clears it, and what is still allowed to run once it is true. The engine obeys a
flag that the app computes from a value that is never allowed to expire, and that
the app stops updating at exactly the moment it matters.

---

## A. Can it still bill the WRONG project?

Yes. Five paths, ranked.

### A1. Tier 2 never says "I don't know" — it replays a stale name as live truth

`ProjectDetector.detectProjectName()` returns `lastDetectedName` on **all four**
failure paths:

- `ProjectDetector.swift:50` — Accessibility not granted, or Resolve not running
- `ProjectDetector.swift:55` — no focused window
- `ProjectDetector.swift:59` — no title attribute
- `ProjectDetector.swift:65` — title present but unparseable

`AppModel.detected()` then promotes whatever came back to the source of truth,
unconditionally, for any `.resolve` source:

```swift
// AppModel.swift:271-273
if case .resolve = source {
    resolveProject = name.trimmingCharacters(in: .whitespaces)
}
```

**Input:** Resolve moves from project A to project B while its focused window is
the Project Manager, the Fusion page, or any window whose title has no `" - "`
separator (`ProjectDetector.projectName(fromWindowTitle:)` returns nil, line 147-158).

**Outcome:** every fifth tick, Cutaway re-asserts **A** as `resolveProject`.
`projectMismatch` (`AppModel.swift:262-266`) stays false. The clock keeps billing A
while B is open — until Tier 1 corrects it, which is up to 120 active ticks with
Accessibility granted and 30 without (`ProjectAutoSwitcher.swift:18-19`).

This is the 2026-09-08 incident with a shorter fuse, not a fixed one. A cached
answer presented as a current one is the same class of defect that caused the
twelve minutes: something reported a name, nothing checked whether the name was
still true.

The shape of the fix (not applied): a tier that cannot answer must return `nil`,
and `resolveProject` must carry a freshness stamp that expires rather than a value
that persists.

### A2. `DetectionFollower` is dead code — steady-state re-assertion is back

`ProjectsModel.autoDetected` (`ProjectsModel.swift:149`) and `switchOrCreate`
(`ProjectsModel.swift:160`) have **no production caller**. The only live path is:

```
ProjectAutoSwitcher.onDetected → AppModel.autoDetected (AppModel.swift:332) → AppModel.detected()
```

which never consults `follower`. So the protection documented at
`DetectionFollower.swift:17-25` — "acting on steady state means … a manual switch
survives at most five seconds" — is no longer installed. `follower.reset()`
(`DetectionFollower.swift:42`) likewise has no caller outside
`DetectionFollowerTests.swift:57`, so Resolve quitting never clears the tier cache
that A1 depends on.

**Input:** the owner manually selects project Y in the picker while Resolve holds
known project X.

**Outcome:** a coin flip decided by tick parity.

- If the next tick is a Tier-2 tick (1 in 5): `decide` returns `.select(X)`,
  `AppModel.swift:281-285` calls `projectsModel.select(match)` — note `select`, not
  `selectManually`, so `intent.userChose()` is never stamped — the running span is
  force-closed (`ProjectsModel.swift:182`) and the owner's explicit choice is
  reverted within one second.
- Otherwise: the mismatch flag reaches the engine first and the state becomes
  `.paused(.projectMismatch)`, which triggers B1 below.

Both outcomes are new since `648d6aa`. Neither is what the commit message promises.

### A3. Tier 2's "may only SELECT" ban is not enforced

`ProjectAutoSwitcher.swift:71-76` passes `canCreate: false` with a comment
explaining that letting titles create projects "would spawn duplicate projects that
silently split one job's billing". `AppModel.autoDetected` discards the parameter:

```swift
// AppModel.swift:332-337
private func autoDetected(_ name: String, canCreate: Bool) {
    detected(name, source: .resolve)
}
```

`detected()` has no notion of `canCreate` at all. So a Tier-2 title artefact — a
modal dialog title containing a hyphen, a window titled
`"DaVinci Resolve - Project Manager"` — reaches the card, and the card's
**New project** button (`PromptPanel.swift:165`) creates a real billable project
from a parse artefact. The comment describes an invariant the code dropped one file
away.

### A4. The mismatch reaches the engine one evaluation late

`AppModel.swift:168` assigns `engine.projectMismatch` from inside `onTick`, and
`onTick?()` is the **last** statement of `DetectionEngine.tick()`
(`DetectionEngine.swift:305`) — after `DetectionState.evaluate` (line 215) and after
`accumulator.tick` (line 294).

**Outcome:** every mismatch bills exactly one more second to the wrong project
before the guard engages. One second is small next to A1's 120, but it means the
"evaluated before frontmost and idle" guarantee is one tick weaker than it reads,
and it is the kind of gap that compounds if the cadence is ever loosened.

### A5. The card's `current` is frozen; the answer is not

`pendingAttribution = (n, src, current)` captures the selected project's name at
ask time (`AppModel.swift:288`) and is never refreshed. `attachDetectedName` writes
to whatever is selected **now**:

```swift
// AppModel.swift:301-308
func attachDetectedName(_ name: String) {
    defer { pendingAttribution = nil; engine.projectMismatch = projectMismatch }
    guard let p = selectedProject else { return }
    storeErrors.attempt("remember that name") { p.remember(name); try store.context.save() }
}
```

**Input:** card appears reading `Yes, Alpina`; the owner switches to Nyx in the
picker (the card is a non-activating panel, so the picker is reachable while it is
up); the owner then clicks the card.

**Outcome:** `BuildingBridges` is permanently remembered as an alias of **Nyx**
(`Models.swift:49-52`). A button labelled with one project name wrote a lasting
attribution rule for another. Every future session on that Resolve project bills to
Nyx, silently and correctly-looking.

### A6. Answering the card does not count as intent

Neither `attachDetectedName` (`AppModel.swift:301`) nor
`createProjectForDetectedName` (`AppModel.swift:311`) bumps
`projectsModel.intent`; `createProject` only stamps it when `isManual` is true
(`ProjectsModel.swift:194-205`), and auto-creation passes the default `false`.

**Outcome:** a Tier-1 request that was already in flight when the card was answered
passes the staleness guard at `ProjectAutoSwitcher.swift:95` (`hasMovedSince` sees
an unchanged token) and lands on top of the owner's answer — the exact
"automation beats intent" race `ManualIntent` exists to prevent
(`DetectionFollower.swift:48-56`). `DetectionWiringTests` cannot catch this: it
greps for the presence of `intent.userChose()` in the source
(`DetectionWiringTests.swift:46-49`), not for its presence on the card path.

---

## B. Can the clock be held when it should NOT be?

Yes, and this is the larger number.

### B1. The mismatch is self-latching — the pause kills the detection that lifts it

```swift
// ProjectAutoSwitcher.swift:67
let active = engine.state == .recording || engine.state == .paused(.noProject)
guard active else { return }
```

`.paused(.projectMismatch)` is neither. So once the mismatch stops the clock,
**Tier 1 and Tier 2 stop running**, `resolveProject` freezes at the name that caused
the mismatch, and the condition can no longer clear itself. Three concrete inputs:

1. **Manual switch away from what Resolve has open** (A2's other branch). Owner
   selects Y while Resolve is on X → mismatch → detection halts. The owner then
   opens Y in Resolve. Cutaway never sees it. The clock is dead for the rest of the
   session.

2. **"Not billable".** `ignoreDetectedName` (`AppModel.swift:325-328`) appends to
   `ignoredNames` and clears `pendingAttribution` — but leaves `resolveProject`
   set, because line 271-273 assigns it *before* the `.ignore` branch is ever
   reached. `projectMismatch` (line 262-266) is then permanently true: no project can
   ever `answersTo` a name the owner has declared unbillable. The clock is dead
   until Resolve quits (`AppModel.swift:166`) or Cutaway is relaunched. The comment
   at line 322-324 says this is deliberate ("the clock stays stopped"), but the
   deliberate part is only "do not bill this to the previous project" — it also
   stops billing *every other* project for the rest of the evening, including a
   perfectly legitimate After Effects afternoon on the selected job.

3. **Timeline closed in Resolve.** Owner closes the project to the Project Manager
   and works in After Effects. Tier 1 returns nil (no current project → the Lua
   prints nothing → `ProjectDetector.swift:136` returns nil), so `resolveProject`
   keeps the stale name, mismatch holds, and the whole billable Adobe block records
   nothing. This is the exact case the new contract claims to support: "an Adobe app
   being frontmost proves someone is working" (`ProjectAutoSwitcher.swift:53-61`).

There is no UI route out. `mismatchBanner` (`MenuBarPanel.swift:205-228`) is
informational — an icon, two `Text` views, an accessibility label, and no button.

**Ranking:** unbounded lost hours, silent, and the failure looks identical to a
correctly idle app. This is the most expensive finding in the audit.

### B2. The re-raise that was supposed to prevent B1 is unreachable

```swift
// AppModel.swift:279-296
case .stay, .ignore:
    return                                    // ← returns first, always
...
// The card is a question, not a dismissal: while Resolve sits on a
// name nobody has placed, it comes back.
if projectMismatch, pendingAttribution == nil, let unplaced = resolveProject {
    pendingAttribution = (unplaced, .resolve, selectedProject?.name)
}
```

The block at line 294-296 is dead in every realistic path:

- `.stay` and `.ignore` `return` at line 280 before reaching it.
- `.ask` sets `pendingAttribution` at line 288, so the `== nil` guard fails.
- `.select` succeeds and the mismatch resolves.

The only way in is a `.select` whose `projects.first(where: { $0.name == projectName })`
lookup fails — which cannot happen, because `AttributionPolicy.decide` returned
`owner.project`, sourced from that same list (`AppModel.swift:274`).

So the stated safety net — "while Resolve sits on a name nobody has placed, it
comes back" — does not exist. Combined with B1, the manual-switch case produces a
held clock with **no card on screen and no route back except quitting**, which is
literally the state the comment promises is impossible.

### B3. On the configurations that most need it, the guard is silently absent

Primary source: Blackmagic Design, *DaVinci Resolve Scripting API* README, last
updated 31 Aug 2026, shipped at
`/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/README.md`.

Verified statements from that file:

- Prerequisites (§Prerequisites): "An active instance of DaVinci Resolve. **Scripts
  may fail if the app is not fully loaded, or is starting up or quitting.**" and "A
  correctly configured application preference for external scripting."
- Configuration (§Configuration): "**In DaVinci Resolve Studio**, Preferences >
  System > General, you can configure: External scripting, i.e. whether external
  scripts can connect to Resolve (None, Local, or Network)."
- Network access (§Network and Headless Access): "**DaVinci Resolve Studio and
  Fusion Studio** scripting listens on port 1144."
- Editions (§Studio and AI Scripting APIs): the API surface is "a common superset of
  functions for both the Free and Studio versions", but "API calls can return with a
  False status … [when] the function references a Studio function from the free
  DaVinci Resolve version."
- The `fuscript` path Cutaway spawns (`ProjectDetector.swift:81`,
  `Contents/Libraries/Fusion/fuscript`) matches the README's documented macOS
  location exactly. That part is right.

The operative consequence: **external scripting is a Studio preference, and its
default is not Local.** Tier 1 therefore returns nil on Resolve Free, on Studio
before the owner enables external scripting, and during Resolve's own launch.

Tier 2's requirement, from the SDK headers rather than a blog:

- `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions()` —
  `AXUIElement.h:64,74`, available macOS 10.9+ / 10.4+ respectively; used at
  `ProjectDetector.swift:23,28`.
- Denial failure mode: `kAXErrorAPIDisabled = -25211` (`AXError.h:70`), documented
  at `AXUIElement.h:40` as "The accessibility API is disabled. **All functions that
  perform messaging can return this error code.**" So `AXUIElementCopyAttributeValue`
  at `ProjectDetector.swift:54,58` fails for every attribute — Tier 2 goes dark
  entirely, not partially.
- Permission sentence, one line, honest: *"Cutaway reads the title of DaVinci
  Resolve's window to learn which project is open."*

**Input:** Resolve Free (or Studio with external scripting at None) plus
Accessibility denied.

**Outcome:** `resolveProject` stays `nil` forever, so `projectMismatch` returns
`false` at `AppModel.swift:263` — the app bills exactly as the pre-`648d6aa` build
did. No banner (it requires `model.resolveProject != nil`,
`MenuBarPanel.swift:206`), no card, no log line, no indication that the protection
the owner now relies on is switched off. **A safety rule that fails open and says
nothing is the one shape that produces this incident a third time.**

No Screen Recording is involved anywhere and none is needed:
`CGWindowListCopyWindowInfo` with `kCGWindowBounds` and `kCGWindowOwnerPID`
(`SystemProbes.swift:72-93`) is unrestricted; only `kCGWindowName` sits behind
Screen Recording, and the code correctly reads neither. That hard limit is honoured.

### B4. The scenario harness runs with the new rule switched off

```swift
// AppModel.swift:155
guard !ScenarioMode.isActive else { return }
```

This sits **above** line 168 (`engine.projectMismatch = self.projectMismatch`) and
line 169 (`autoSwitcher?.tick()`). Under the scenario driver, the mismatch flag is
never written to the engine and no tier ever runs. Every scenario run therefore
proves the engine with `projectMismatch == false` permanently. `scenarioDetect`
(`AppModel.swift:231-234`) auto-answers the card ("yes, new project"), so it does not
exercise the held state either.

### B5. The mismatch tests assert about a copy of the logic

`MismatchReleaseTests` (`ProjectMismatchTests.swift:95-115`) re-implements the rule
inline —

```swift
let mismatch = resolveProject.map { !$0.isEmpty && $0 != selected } ?? false
```

— rather than calling `AppModel.projectMismatch` (`AppModel.swift:262`). It would
stay green if line 262 were deleted, and it does not use `answersTo`, so it does not
even test the same comparison. Nothing covers the `ProjectAutoSwitcher` gate (B1),
the ignore latch (B1.2), the dead re-raise (B2), or the `canCreate` drop (A3).

This is the same failure `DetectionWiringTests` was written to catch and documents
in its own header: "A part that is tested but not installed passes every test it
has." The mismatch rule now has that property.

---

## C. The card

- **Can it be dismissed into a held state with no way back?** Yes — but not by
  dismissing it. The card has no dismiss affordance (`PromptPanel.swift:156-178`:
  three action buttons, no close). The trap is **"Not billable"** (B1.2) and the
  **manual switch** (B1.1), both of which reach a held clock with no card at all.
- **Is there a loop where it reappears forever?** No. `askedNames.insert(n)`
  precedes the raise (`AppModel.swift:287`) and `AttributionPolicy.decide` returns
  `.stay` for an already-asked name (`AttributionPolicy.swift:54`). The opposite
  problem is the real one: it appears at most once per name per run, and the
  re-raise meant to fix that is dead (B2).
- Hiding behaviour is sane: `PromptArbiter.visible` (`PromptPanel.swift:22-31`)
  suppresses the attribution card during a manual pause and behind an idle warning,
  and `pendingAttribution` survives, so it returns when the higher-priority prompt
  clears.
- One inconsistency: `askedNames` is per-run and in memory; `ignoredNames` is
  persisted to `Prefs` (`AppModel.swift:244-247`). A restart re-asks about a name the
  owner ignored a card for, which is fine, but it also means B1.2's latch clears on
  relaunch — restarting Cutaway is currently an undocumented workaround for a
  deadlocked clock.

---

## D. Energy and correctness of the tick

### D1. A process-table enumeration and a disk stat, every second

```swift
// AppModel.swift:166
if self.detector.resolveEdition() == nil { self.resolveProject = nil }
```

`resolveEdition()` (`ProjectDetector.swift:33-41`) walks
`NSWorkspace.shared.runningApplications` and then calls `FileManager.fileExists` on
a fixed path. Per second. ~86,400 process-table enumerations and ~86,400 disk stats
a day, to answer a boolean that changes twice a day and a path test that cannot
change while the app runs.

Apple's own guidance, from the SDK header rather than a blog —
`NSRunningApplication.h`, declaration of `NSWorkspace.runningApplications`:

> "Similar to `NSRunningApplication`'s properties, this property will only change
> when the main run loop is run in a common mode. **Instead of polling, use
> key-value observing to be notified of changes to this array property.**"

Event-driven replacements, all of which this codebase already knows how to use
(`FrontmostTracker`, `SystemProbes.swift:34-49`, is exactly this pattern):

| API | Header | Permission | macOS | Failure when denied |
|---|---|---|---|---|
| `NSWorkspaceDidLaunchApplicationNotification` | `NSWorkspace.h:290` | none | 10.0+ | n/a — no TCC gate |
| `NSWorkspaceDidTerminateApplicationNotification` | `NSWorkspace.h:291` | none | 10.0+ | n/a — no TCC gate |
| `NSWorkspaceApplicationKey` (userInfo → `NSRunningApplication`) | `NSWorkspace.h:287` | none | 10.6+ | n/a |
| `NSRunningApplication.runningApplications(withBundleIdentifier:)` | `NSRunningApplication.h:161` | none | 10.6+ | returns empty array |

Both notifications post on `NSWorkspace.shared.notificationCenter` — the same centre
`observeSleepWake` (`DetectionEngine.swift:436`) and `FrontmostTracker`
(`SystemProbes.swift:42`) already subscribe to. The edition string itself should be
computed once and cached; it cannot change without a relaunch.

### D2. An unconditional write to an `@Observable` property, every second

```swift
// AppModel.swift:168
self.engine.projectMismatch = self.projectMismatch
```

`DetectionEngine` is `@Observable` (`DetectionEngine.swift:8`) and
`projectMismatch` is a stored property (`DetectionEngine.swift:311`). The macro's
generated setter calls `withMutation` on assignment without comparing old and new,
so every observer of the engine is invalidated once a second regardless of change.

The engine is otherwise disciplined about exactly this and says so:
`if isLong != pausedLong` (line 181), `if source != recordingSource` (line 271),
`if warning != idleWarning` (line 286), and the comment at line 176-177 ("so the
observable churns once, not every second"). Line 168 is the one write that broke the
rule, and it arrived with `648d6aa`.

### D3. Three new wall-clock reads bypass the injectable clock

`AppModel.swift:160` (`BackupPolicy.isDue(last:now: Date())`),
`ProjectAutoSwitcher.swift:88` and `:94` (`Date()`, `Date().timeIntervalSince`) all
read the wall clock directly. `DetectionEngine` deliberately routes every time read
through `now: () -> Date` (`DetectionEngine.swift:87`) and the comment at line
417-421 records the last time this exact leak was closed. The mismatch path
reopened it three times, which is why none of these paths is reachable from a
deterministic test.

### D4. The Tier-1 cadence is counted in billed seconds, not wall seconds

`schedule.advance()` runs only while active (`ProjectAutoSwitcher.swift:69`), and
`tier1FirstAt` is a one-shot equality check (`tick == 3`,
`ProjectAutoSwitcher.swift:27`) that can never fire again. After the first pass,
Tier 1's next chance is `tick % interval == 0` counted in **active ticks only**.

**Consequence:** the correction window in A1 is not "up to 120 seconds of wall
clock" but "up to 120 seconds *of billing*" — every second of that window is a
second credited to the wrong project. The cadence and the exposure are the same
quantity.

### D5. What the tick does right

Worth keeping, so nobody "optimises" it away: `Timer.tolerance = 0.5` with real
wall-clock deltas and a 5 s cap (`DetectionEngine.swift:141, 291-294`) is the
correct trade — coalesced wakeups without accuracy loss.
`frontmostWindowIsFullScreen()` is asked lazily, only inside the warning window
(`DetectionEngine.swift:283`, `SystemProbes.swift:13-15`). Frontmost comes from
`NSWorkspaceDidActivateApplicationNotification` (`NSWorkspace.h:294`, macOS 10.6+,
no permission) rather than a poll. Sleep and wake come from
`NSWorkspace.willSleepNotification` / `didWakeNotification`. None of these needs
hardening.

---

## E. Ranked summary

**Loses time (unbounded, silent):**

1. B1 — mismatch self-latches; `ProjectAutoSwitcher.swift:67` stops the detection
   that would clear it. Three entry points: manual switch, "Not billable"
   (`AppModel.swift:325-328` + `271-273`), closed timeline.
2. B2 — the re-raise at `AppModel.swift:294-296` is unreachable behind the `return`
   at line 280, so B1 produces a held clock with no card and no route back.
3. B3 — on Resolve Free, on Studio with external scripting off, or with
   Accessibility denied, `resolveProject` is never set and the entire guard is off
   with no user-visible signal.

**Bills the wrong project:**

4. A1 — `ProjectDetector.swift:50/55/59/65` return a cached name as current truth;
   up to 120 billed seconds on the wrong project per Resolve switch.
5. A2 — `DetectionFollower` / `ProjectsModel.autoDetected` are dead code; steady-state
   re-assertion silently reverts a manual selection via
   `AppModel.swift:281-285` → `ProjectsModel.select`.
6. A5 — frozen `current` in `pendingAttribution` (`AppModel.swift:288` vs `301-308`)
   writes a permanent alias to the wrong project.
7. A3 — `canCreate` dropped at `AppModel.swift:332-337`; a Tier-2 title artefact can
   become a billable project.
8. A6 — answering the card does not stamp `ManualIntent`; an in-flight Tier-1 answer
   overrides it.
9. A4 — one-tick lag at `AppModel.swift:168`.

**Energy / testability:**

10. D1 — per-second `runningApplications` walk + disk stat (`AppModel.swift:166`).
11. D2 — per-second unconditional `@Observable` write (`AppModel.swift:168`).
12. D3 — three wall-clock reads bypassing `engine.now`.
13. B4/B5 — the scenario harness runs with the rule disabled; `MismatchReleaseTests`
    asserts about a copy of the logic.

---

## F. What detection must never do

Stated as invariants so this contract is not re-litigated a third time. Each one has
a violation above; each is checkable.

1. **Never treat a cached or unverified name as current truth.** A tier that cannot
   answer returns `nil`. A `nil` answer expires `resolveProject`; it does not
   preserve it. Truth about the world carries a timestamp or it is not truth.
   *(violated by A1)*

2. **Never let a pause suppress the detection that would lift it.** Any state whose
   exit condition is observed by detection must keep detection running. A guard that
   disables its own release is a deadlock, not a guard. *(violated by B1)*

3. **Never hold the clock without a visible, actionable route out.** A held clock
   with an informational banner is a bug report, not an interface. Every hold names
   its cause and offers the one click that ends it. *(violated by B1 + `MenuBarPanel.swift:205-228`)*

4. **Never re-assert over a person who has already spoken.** Explicit selection,
   "not billable", and manual pause outrank every tier. Detection acts on
   *transitions*, never on steady state; polling the same fact again is not new
   information. *(violated by A2)*

5. **Never fail open in silence.** If Tier 1 and Tier 2 are both unavailable, the app
   says the guard is off. It must never behave like the pre-incident build while
   looking like the hardened one. *(violated by B3)*

6. **Never let an unconfirmed name create a billable project.** Tier 2 selects;
   only Tier 1 and the owner create. A parse artefact must not be able to become an
   invoice line. *(violated by A3)*

7. **Never bill time the machine cannot prove a person was present for.** Manual
   pause and system sleep stay sacred. No CPU sample, render heuristic, or display
   assertion may substitute for input — that rule was deleted on 2026-09-08
   (`DetectionEngine.swift:73-81`) and must stay deleted.

8. **Never poll for a fact the system will announce.** Frontmost app, app launch and
   termination, sleep/wake and display state are notifications
   (`NSWorkspace.h:287-294`; `NSRunningApplication.h`: "Instead of polling, use
   key-value observing"). Only idle seconds are read at 1 Hz, because
   `CGEventSource.secondsSinceLastEventType` has no event form. *(violated by D1)*

9. **Never read the wall clock outside the injectable clock.** A time source a test
   cannot move is a behaviour a test cannot check. *(violated by D3)*

10. **Never ship a rule the harness cannot exercise.** If the scenario driver
    disables the rule (`AppModel.swift:155`), the rule is unverified no matter how
    many scenarios pass. *(violated by B4)*
