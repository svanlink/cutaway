# Hardening audit — architecture, concurrency, store integrity, resource limits

Date: 2026-09-08
HEAD: `648d6aa` ("fix: never bill the wrong project — Resolve is the source of truth")
Scope: everything except signing/notarization (out of scope by the owner's decision, `docs/PLAN.md`).
Nothing in `Sources/` was modified. Findings only.

Two of the findings below are **proven by measurement on this Mac**, not inferred.
Where a finding is a hypothesis it says so, and names the experiment that kills it.

---

## 0. Method

- Read every file under `Sources/Cutaway` (70 files, ~6.4 kloc).
- Ran the unit suite once under `xcodebuild test` and inspected the artefacts it
  left behind: `$TMPDIR/cutaway-tests/detection-log.jsonl`, the temp store, and
  the **real** `com.vaneickelen.cutaway` preferences domain.
- Ran a controlled before/after `defaults read` around a single test class to
  establish causation for finding #1.
- Ran a standalone SwiftData program to establish the semantics of
  `PersistentIdentifier.storeIdentifier` for finding #2.

---

## 1. CRITICAL — the unit suite writes to the owner's live preferences, and
##    deletes the running app's crash-recovery snapshot

`Sources/Cutaway/App/Prefs.swift:8-15`

```swift
nonisolated(unsafe) let Prefs: UserDefaults = {
    let env = ProcessInfo.processInfo.environment
    if let suite = PrefsPolicy.suiteName(scenario: env["CUTAWAY_SCENARIO"] != nil,
                                         dataDir: env["CUTAWAY_DATA_DIR"]) {
        return UserDefaults(suiteName: suite)!
    }
    return .standard
}()
```

Two other resources already quarantine themselves on `XCTestConfigurationFilePath`:

- `Sources/Cutaway/Projects/StorePath.swift:20-23` — the billing store goes to `$TMPDIR/cutaway-tests/timex.store`.
- `Sources/Cutaway/Detection/SessionLogger.swift:31-34` — the detection log goes to the same temp dir.

`Prefs` does **not**. And `project.yml:48-52` sets
`TEST_HOST: $(BUILT_PRODUCTS_DIR)/Cutaway.app/Contents/MacOS/Cutaway`, so every
unit test runs *inside a fully live copy of the real app*, with the real bundle
id `com.vaneickelen.cutaway`, and therefore the real `UserDefaults` domain.

### Measured, causally

`defaults read com.vaneickelen.cutaway` immediately before and after running one
test class (`-only-testing:CutawayTests/MoneyRoundingTests`):

```
15c15
<     lastBackupAt = "2026-09-08 16:33:25 +0000";
---
>     lastBackupAt = "2026-09-08 16:34:50 +0000";
17,20d16
<     "openSession.active" = "770.829305768013";
<     "openSession.project" = "26_08_AuroraEC_HFAtelierPresentations2026";
<     "openSession.start" = "1788884497.694915";
<     "openSession.updatedAt" = "1788885278.323583";
```

`/Applications/Cutaway.app` was running (pid 50350) at the time, tracking a live
session on the owner's real Resolve project.

Two things happened, both bad:

1. **`lastBackupAt` was rewritten** (`AppModel.swift:209-212`, via
   `recordBackup()` from `AppModel.swift:119` and `:200`). The live app reads
   this at `AppModel.swift:66` and gates its daily snapshot on it
   (`BackupPolicy.isDue`, called from the tick at `AppModel.swift:160`).
   **Running the test suite disarms the owner's store backup for 24 hours.**
   The one safety net this project has been built around, switched off by a
   `Cmd-U`.

2. **`openSession.*` was deleted.** That was the crash-recovery snapshot of a
   *live, in-progress, 12.8-minute* session (`openSession.active = 770.8`) on
   `26_08_AuroraEC_HFAtelierPresentations2026`. The test host's own engine
   closed its own (temp-store) session, `onSessionClosed` returned true, and
   `DetectionEngine.clearOpenSessionSnapshot()` (`DetectionEngine.swift:374-379`)
   removed the keys **from `.standard`**, because
   `DetectionEngine.init(defaults: UserDefaults = Prefs)` (`:111`) defaults to
   the global handle. If the real app had crashed in the next minute, those 13
   minutes were unrecoverable.

The same domain also currently holds `selectedProjectName = "Untitled Project"` —
not one of the owner's projects. That is a name a temp/scratch store produced
and the test host wrote back via `ProjectsModel.select` (`ProjectsModel.swift:188`).
On the next real launch, `restoreSelection()` (`:81-87`) looks for it, does not
find it, and falls through to `all.first` — **a different project than the one
the owner left selected.** Time then bills to whatever that is until noticed.

There is a third writer too: `AppModel.prepareForTermination()`
(`AppModel.swift:215-219`) sets `cleanShutdown = true` in the shared domain, and
`StoreBootstrap.open` (`StoreBootstrap.swift:105-106`) reads and clears it. Two
processes racing on that flag decide whether the *real* launch runs the O(file)
`PRAGMA quick_check` over the real store.

### Why it is not covered

`Tests/CutawayTests/ScratchDefaults.swift` is a careful, well-reasoned piece of
hygiene — it sweeps `cutaway.tests.*` plists so nothing outlives a run. But it
protects against tests that *deliberately* open a suite. The leak here is the
host app doing ordinary app things in the real domain, which no test opts into.

### The shape of the fix (not applied)

One line, in the same style as the two quarantines that already exist:

```swift
// PrefsPolicy.suiteName(scenario:dataDir:) gains the third case the other
// two quarantines already have.
if isTestRun { return "com.vaneickelen.cutaway.tests" }
```

`PrefsPolicy.suiteName` is already pure and already unit-tested
(`Tests/CutawayTests/PrefsPolicyTests.swift`), so the rule is testable without
an environment — same as `StorePath.url(isTestRun:)` and
`SessionLogger.directory(scenarioDataDir:isTestRun:)`.

Blast radius: the owner's backup schedule, their crash snapshot, and which
project the app bills to. Cost of the fix: one branch in a pure function.

---

## 2. CRITICAL — every block on the day timeline shares one identity; a drag,
##    split, delete or reassign always lands on the day's *first* session

`Sources/Cutaway/Stats/DayTimelineView.swift:32-44` and `:201-203`

```swift
DayTimeline.Block(id: $0.persistentModelID.storeIdentifier ?? UUID().uuidString, ...)
...
private func session(for id: String) -> WorkSession? {
    sessions.first { $0.persistentModelID.storeIdentifier == id }
}
```

`PersistentIdentifier.storeIdentifier` is the identifier **of the store**, not of
the object. Proven with a standalone program:

```
a.storeIdentifier = 60FB106F-AEE2-44CD-A8EE-5A3124B3BD6C
b.storeIdentifier = 60FB106F-AEE2-44CD-A8EE-5A3124B3BD6C
EQUAL: true
a.id  = PersistentIdentifier(... x-coredata://60FB106F-…/Row/p1)
```

The object's identity is the `/Row/p1` tail; `storeIdentifier` is the UUID
prefix, identical for every row in the store. The `?? UUID().uuidString`
fallback never fires (a saved object always has a store), so it hides nothing —
it just makes the line look defensive.

Consequences, all on a surface whose entire purpose is editing billing data:

| Call site | Effect |
|---|---|
| `:58` `ForEach(t.blocks)` | duplicate `Identifiable` ids — SwiftUI diffing is undefined |
| `:101` `dragging?.id == block.id` | dragging one block redraws **all** of them as dragged |
| `:122` `selected == block.id` | selecting one selects all |
| `:192` drag `onEnded` → `editSession` | **moves/resizes the day's first session, not the one dragged** |
| `:210` `edit` | opens the sheet on the wrong session |
| `:215` `split` | splits the wrong session |
| `:222` `delete` | **deletes the wrong session** |
| `:247` `assign` | reassigns the wrong session to another client |

On any day with two or more sessions — which is most days — the strip silently
operates on the wrong row. Deleting the third block deletes the first.

`Tests/CutawayTests/DayTimelineTests.swift:20` constructs blocks with
`id: UUID().uuidString`, so the arithmetic is well covered and the *identity
derivation* — the only part that can be wrong — is never exercised. This is the
same failure mode `Sources/Cutaway/Projects/Schema.swift:29-31` already
documents about the schema test: "the unit test that was supposed to prevent
this asserted the entity NAMES… and passed, because names were never the thing
that changed."

Correct identity, same length: `String(describing: $0.persistentModelID)`, or
give `WorkSession` the `uid` it already has (`Models.swift:108`) — though `uid`
is deliberately empty until an invoice needs it, so `persistentModelID`
described in full is the smaller change.

Secondary, same file: `:173` computes the drag edge as
`value.startLocation.x > width - 8`, where `width` is the **whole strip's**
width, not the block's. `startLocation` is in the block's local space, so the
trailing-edge branch is unreachable for any block that is not full-width — the
right-hand grab handle does not work.

---

## 3. HIGH — `assertNothingInvoiced` exists, is correct, and is wired to nothing

`Sources/Cutaway/Projects/SessionStore.swift:61-67`

```swift
/// Deleting work that an invoice claims would leave the document
/// unprovable. Refused by number, so the message says which one.
func assertNothingInvoiced(in project: Project) throws { ... }
```

`grep -rn assertNothingInvoiced Sources/ Tests/` returns **three** hits: the
definition, and two tests. Zero production callers.

The live delete path is:

`ProjectManageSheets.swift:40` → `AppModel.delete` (`AppModel.swift:403`) →
`ProjectsModel.delete` (`ProjectsModel.swift:230-243`) →
`SessionStore.delete` (`SessionStore.swift:81-88`) → `context.delete(project)`
→ the cascade at `Models.swift:61`.

So deleting a project with issued invoices cascade-deletes the `WorkSession`
rows an issued document claims. The `Invoice` survives with
`status == .issued`, its `InvoiceLine.sessionUIDs` (`Invoice.swift:104`) now
pointing at nothing, and `voidInvoice` (`InvoiceStore.swift:146-156`) becomes a
no-op because it unlocks by walking `try projects()` — and the project is gone.

The provenance design is explicitly there so the app "can always answer 'where
did this figure come from'" (`Invoice.swift:22-27`). One unwired guard is the
difference between that promise holding and not.

`DeleteProjectSheet` also offers "Move to <project>" for the sessions, which
silently reassigns invoiced work across projects — the invoice's frozen
`projectName` then names a project that no longer holds the work.

---

## 4. HIGH — undo restores a day by delete-and-reinsert, which strips the
##    invoice lock and the provenance UID

`Sources/Cutaway/Projects/SessionStore.swift:261-272`

```swift
func restore(_ edit: DayEdit, for project: Project, calendar: Calendar = .current) throws {
    let dayStart = calendar.startOfDay(for: edit.day)
    for session in project.sessions where calendar.startOfDay(for: session.start) == dayStart {
        context.delete(session)
    }
    for s in edit.sessions {
        context.insert(WorkSession(start: s.start, end: s.end, activeSeconds: s.activeSeconds,
                                   hourlyRate: s.hourlyRate, project: project, isAdjusted: s.isAdjusted))
    }
    ...
}
```

`DayEdit.Session` (`Sources/Cutaway/Projects/EditHistory.swift:12-18`) carries
`start`, `end`, `activeSeconds`, `hourlyRate`, `isAdjusted` — and **not** `uid`
or `invoiceNumber`. Every other mutating method on `SessionStore` opens with an
invoice check (`:120`, `:146`, `:164`, `:182`, `:210`, `:280`). `restore` has
none.

The sequence:

1. Edit a day (a drag, a split, a total) → `registerUndo(of: before, …)`
   captures the pre-edit shape (`EditHistory.swift:34-47`).
2. Issue an invoice covering that day. `issueInvoice` calls `ensureUID()` and
   sets `invoiceNumber` on every billed session (`InvoiceStore.swift:82`, `:135`).
3. `Cmd-Z`.

`restore` deletes the locked sessions and re-inserts fresh ones with
`invoiceNumber == ""` and `uid == ""`. The work is billable again — the same day
can be put on a second invoice — and the first invoice's `sessionUIDs` are
dangling. The undo stack survives the issue because nothing invalidates it.

A build artefact in DerivedData from an earlier pass on this repo contains a
test literally named `HardeningProbeTests.testProbeUndoBreaksTheInvoiceLock()`
and `testProbeSameDayRebilled()`, which is independent corroboration that this
path has been probed before.

The lazy fix is one guard in `restore`, not one in each of the five callers in
`EditHistory.swift` — all of them route through here.

---

## 5. HIGH — a synchronous Accessibility call into DaVinci Resolve, on the main
##    thread, with no messaging timeout (and the most likely cause of the gate)

`Sources/Cutaway/Detection/ProjectDetector.swift:46-66`

```swift
let axApp = AXUIElementCreateApplication(app.processIdentifier)
var windowRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
      let window = windowRef else { return lastDetectedName }
var titleRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
```

`grep -rn SetMessagingTimeout Sources/` → **never called.**

`AXUIElementCopyAttributeValue` is synchronous IPC serviced by the *target
application's main thread*. Without `AXUIElementSetMessagingTimeout` the caller
inherits the default, and a target that is not servicing its run loop blocks the
caller. The target here is DaVinci Resolve, which the charter correctly calls
"the most CPU-hostile neighbour on the Mac" — and it is at its least responsive
during exactly the renders this app is designed to sit beside.

This runs on the MainActor from `ProjectAutoSwitcher.tick()`
(`ProjectAutoSwitcher.swift:71`), scheduled every 5 ticks
(`DetectionSchedule.tier2Every = 5`, `:12`) — i.e. **every five seconds, for the
life of the process.** A stalled AX round-trip is a frozen menu bar.

Prior art worth copying: `mediar-ai/mcp-server-macos-use`,
`Sources/MCPServer/main.swift`, wraps every element it touches with
`AXUIElementSetMessagingTimeout(appElement, …)` / `AXUIElementSetMessagingTimeout(window, 5.0)`
before reading attributes. `tmandry/AXSwift`, `Sources/UIElement.swift`, exposes
the same as `setMessagingTimeout` and treats it as the default posture for any
cross-process AX read.

Same file, same pattern, two more:

- `:58` `window as! AXUIElement` — a **force-cast on a value that came from
  another process.** `kAXFocusedWindowAttribute` is documented to return an
  `AXUIElement`, but the value is produced by Resolve; a wrong CFType is a crash
  in the owner's menu bar with no recovery. `as?` costs nothing.
- `:92` `Self.fuscriptPath()` runs on the MainActor *before* the detached task —
  it calls `fuscriptCandidates()` (`:75-82`), which makes two
  `NSWorkspace.urlForApplication(withBundleIdentifier:)` LaunchServices
  round-trips plus four `isExecutableFile` stats, synchronously on the main
  thread, on every Tier-1 attempt.
- `:131` `readDataToEndOfFile()` blocks until **every** writer closes the pipe.
  It is reached only after `terminationHandler` fires, but a grandchild that
  inherited the write end keeps it open — and this runs on a `Task.detached`
  cooperative-pool thread, whose width equals the core count. Blocking those
  starves all Swift concurrency in the process, including
  `Task { @MainActor }` continuations.

### The gate: `AppearanceGuardTests.testNoViewForcesItsOwnColorScheme`

**I could not reproduce the stall.** My run of the full unit suite completed in
22.4 s wall clock, with Resolve running but idle. So what follows is a
hypothesis with strong circumstantial support and a two-minute experiment that
settles it — not a proven cause.

What I *did* establish, from `$TMPDIR/cutaway-tests/detection-log.jsonl` written
by the test host itself:

```
{"detail":"recording","event":"transition","frontmost":"com.blackmagic-design.DaVinciResolve","idle":"0.0",...}
{"t":"2026-09-08T12:45:22Z","event":"tier1","detail":"name=26_08_AuroraEC_HFAtelierPresentations2026 took=0.57s"}
```

**During a unit-test run, the test host attaches to the owner's live DaVinci
Resolve, reads its real open project by name, and does so 3–5 seconds after
`engine-start`.** That is not a theory; it is in the log the app wrote.

The mechanism that follows:

- `TEST_HOST` is the real app (`project.yml:50`), so the 1 Hz engine timer
  (`DetectionEngine.swift:135-143`, `RunLoop.main`, `.common`) is live for the
  whole suite.
- XCTest runs unit tests on the host's main thread and services the run loop
  between them; many test classes here are `@MainActor` and are awaited, which
  yields. The timer therefore fires *between tests*, and any block it causes is
  billed to whichever test XCTest is timing.
- `DetectionSchedule.tier1FirstAt = 3` and `tier2Every = 5`
  (`ProjectAutoSwitcher.swift:14-19`) put the **first** detection attempts at
  **3 s and 5 s into every run** — a fixed offset from launch, not a random one.
- That fixed offset pins a fixed victim in the alphabetical class order.
  `AppearanceGuardTests` sits eighth (`AccessibilityOffer`, `AnchorDefaults`,
  `AnchorSet`, `AppCatalog`, `AppIconRow`, `AppIcon`, `AppPicker`,
  **`Appearance`**), which in a ~22 s suite of overwhelmingly sub-millisecond
  tests is right around the 3–5 s mark.
- **Run the class alone and the suite is over in well under a second — tick 3
  never arrives.** That is exactly the reported 0.017 s.
- The blocking call at that moment is a synchronous AX read into Resolve with no
  timeout (or, on the Tier-1 branch, LaunchServices on the main thread). 250–800 s
  is the right order of magnitude for a wedged AX target, and its variance is
  the right *shape* — it tracks what Resolve happens to be doing, not anything
  about the test.

This also explains why the two disproved theories failed: it has nothing to do
with concurrent `xcodebuild` runs, and nothing to do with scanning
`/Applications` (`InstalledApps.scan`, which reads a different tree entirely).

**The experiment that settles it, in two minutes:** quit DaVinci Resolve
completely, then run the full suite three times. If the stall vanishes, it is
this. To discriminate Tier 2 from Tier 1, leave Resolve running and instead
revoke Accessibility for the DerivedData `Cutaway.app` — that turns off Tier 2
(`ProjectDetector.swift:47`) while leaving `fuscript` alive. A third
confirmation is free: the host's own log at
`$TMPDIR/cutaway-tests/detection-log.jsonl` timestamps every `tier1` attempt
with `took=`, so a stalled run leaves its own evidence.

Independent of the gate, the same code is a **production** hang surface: it is
the app's menu bar freezing next to a render, which is the one thing the charter
says must never happen.

---

## 6. MEDIUM-HIGH — `VACUUM INTO` runs on the main actor, including on the quit path

`Sources/Cutaway/Projects/StoreBackup.swift:107-123` performs
`sqlite3_exec(source, "VACUUM INTO '…'")`, which writes a full physical copy of
the database. It is reached from:

- `AppModel.backUpNow` (`AppModel.swift:196-207`), which is `@MainActor`;
- the engine tick (`AppModel.swift:160`) once a day via `BackupPolicy.isDue`;
- **`prepareForTermination()` (`AppModel.swift:215-219`)**, on the
  `applicationWillTerminate` path, where macOS allows only a few seconds before
  force-killing.

At the current ~90 KB store this is invisible. It grows with exactly the history
the app is designed to accumulate, and the disk it competes for is the one
Resolve is writing renders to. A quit-time `VACUUM INTO` that overruns the
termination budget is a backup that does not exist *and* a hang in front of the
user.

It also opens the live store a second time with `SQLITE_OPEN_READWRITE`
(`:112`) while SwiftData holds it. `VACUUM INTO` itself only needs a read lock,
but `READWRITE` invites the second connection into WAL recovery/checkpoint
behaviour it does not need. `SQLITE_OPEN_READONLY` is sufficient for
`VACUUM INTO` and is what every other probe in `StorePath` already uses.

The staging-then-rename discipline (`:49-65`, `:90-100`) is genuinely good and
handles the disk-full case correctly: the copy throws, the staging folder is
removed, and no folder ever carries the `billing-…` name unless it is complete.
`StoreBootstrap.open:110-111` catches and logs. That part needs nothing.

---

## 7. MEDIUM-HIGH — the panel walks the entire session history six times a second

While the popover is open, `MenuBarPanel` re-renders on the engine's 1 Hz tick.
Per render it reads:

| Read | Cost | Sites |
|---|---|---|
| `model.todayMoney` (`AppModel.swift:420-428`) | full `dayTotals` = `Dictionary(grouping:)` over **all** sessions + a `DayTotal` per day ever worked | `MenuBarPanel.swift:114`, `:152` |
| `model.unbilledLine` (`AppModel.swift:488-493`) | `unbilledTotal` filters all sessions and does a `Money.rounded` **per session** | `MenuBarPanel.swift:51`, `:327` |
| `model.lastSessionLine` (`AppModel.swift:456-459`) | `max` over all sessions | `MenuBarPanel.swift:51`, `:301` |

Six full walks of the complete history, every second. `SessionStore.todayCache`
(`SessionStore.swift:15`) was added for exactly this problem and covers
`activeSecondsToday` only; the three reads above route around it.

At today's ~51 hours this is free. At 10k sessions (roughly three years at eight
sessions a day) it is ~60k session visits and ~20k `Decimal` allocations per
second on the main thread, next to Resolve. That is the app becoming visible in
Activity Monitor purely through age.

`StatsView.swift:99` and `:200` each call `dayTotalsIncludingLive` on render,
which is another full grouping — bounded by how often Stats redraws rather than
by a timer, so lower priority.

Invoice growth is fine by comparison: 200 invoices × ~30 lines is ~6k rows, and
`invoices()` (`InvoiceStore.swift:29-31`) is only read when the sheet is open.
No `fetchLimit` anywhere in `Sources/`, but no fetch is on a hot path either.

---

## 8. MEDIUM — a full disk produces a truncated invoice PDF reported as success

`Sources/Cutaway/Billing/InvoicePDF.swift:39-48`

```swift
var drew = false
renderer.render { _, draw in
    context.beginPDFPage(nil); draw(context); context.endPDFPage(); drew = true
}
context.closePDF()
guard drew else { throw RenderError(...) }
return url
```

`drew` records that the *drawing closure ran*, not that bytes reached the disk.
`CGDataConsumer` writes lazily and `closePDF()` returns `Void` — a write failure
(full volume, revoked sandbox path, disconnected network drive) surfaces
nowhere. The owner gets a truncated or zero-byte PDF reported as a success, for
an invoice that is **already issued and whose sessions are already locked**
(`InvoiceStore.swift:135-136`).

A `FileManager.attributesOfItem(...)[.size]` check after `closePDF()` is two
lines and turns a silent bad document into the existing `RenderError` path,
which `InvoiceSheet.swift:272-277` already presents properly.

Related, and arguably correct as designed but worth stating: `InvoiceSheet.issue()`
(`:240-281`) issues and locks *before* the save panel opens. Cancelling the
panel leaves an issued invoice with no PDF. The number is kept and never reused,
so the sequence stays gapless — that is the documented intent — but there is no
"re-export" affordance except `savePDF` from the issued list, and that list
filters on `$0.projectName == project.name` (`:153`), so **renaming a project
hides every invoice it ever issued** and they can no longer be voided or
re-exported from the UI.

---

## 9. Swift 6 concurrency — what is real and what is only compiler-shaped

Audited every `nonisolated(unsafe)`, `assumeIsolated`, `Task.detached`, and
injected static closure.

**Sound as written** (the annotation is a compiler formality, and the reasoning
in the comment holds):

- `Prefs.swift:8` — `UserDefaults` is documented thread-safe. (Its *contents*
  are the problem; see finding #1.)
- `StoreBackup.swift:158` `contentComparisons` — written only from
  `isUnchanged`, reachable only from `backUp`/`snapshot`, both MainActor.
- `DamagedStoreAlert.swift:11-12` — a `let` closure; the only caller is
  `StoreBootstrap.open`, which is `@MainActor`, so `assumeIsolated` holds.
- `CutawayApp.swift:49`, `SystemProbes.swift:46`, `DetectionEngine.swift:127`,
  `AppModel.swift:175` — all AppKit/NSWorkspace callbacks that Apple documents
  as main-thread. `SystemProbes.swift:42-43` explicitly passes `queue: nil` and
  says why, which is the right call.
- `EditHistory.swift:37`, `:85` — `UndoManager` invokes on the thread that
  called `undo()`; the only callers are `@MainActor`.
- `InvoiceSheet.swift:207`, `:270` — `NSSavePanel.begin`'s completion is
  delivered on the main thread.

**Worth changing:**

- `AppModel.swift:79` `nonisolated(unsafe) static var askAboutDamagedStore` —
  the only mutable global in this set. It is a seam for tests, and it is written
  by tests from whatever context they run in while `AppModel.init` may read it.
  In practice both are main-thread today, so this is a latent hazard rather than
  a live race — but a `var` is a different risk class from the `let`s above and
  should not sit in the same bucket.
- `ProjectDetector.swift:131` — the blocking `readDataToEndOfFile` on a
  cooperative-pool thread, covered in finding #5.
- `SessionLogger.swift:6` `@unchecked Sendable` with a shared
  `ISO8601DateFormatter` (`:9`) formatted from arbitrary threads. Formatting-only
  use of a Foundation date formatter is thread-safe in practice, but
  `@unchecked` asserts it rather than proving it. The queue at `:10` already
  exists; moving `iso.string(from:)` inside the `queue.async` block makes the
  assertion true by construction and costs nothing.

**No actual data race found.** The concurrency posture here is better than most
codebases this size: one timer, one actor, notifications on `queue: nil` with a
stated reason, and detached work that carries only `Sendable` values across
(`AppModel.swift:179-182`, `AppPickerView.swift:96` — both use the same
`[weak self]`-outside/detached-inside shape, and both say why).

`NSAppleScript` is confirmed gone: `grep -rn "NSAppleScript\|AEDeterminePermission\|OSAScript" Sources/`
returns nothing. That removal also removed the Automation TCC prompt, which was
the app's worst unbounded-block surface. Good call.

---

## 10. Resource limits — what is capped, what is not

**Capped and correct:**

- Diagnostics: 10 reports (`Diagnostics.swift:10`, `:23`), newest-first, with a
  UUID suffix so a MetricKit batch cannot overwrite itself (`:20-21`).
- `.replaced-*` litter: 30 days, newest generation kept forever as the only undo
  for the most recent restore (`StoreBackup.swift:258-273`). The `stem()` helper
  at `:284-290` correctly groups `-wal`/`-shm` with their parent.
- `.staging-*`: 24 hours (`:275-278`).
- Backup rotation: newest 7 + newest-per-day for 30 days + **the eldest, never
  evicted** (`:220-253`). The reasoning at `:222-227` — that recency alone must
  never evict history — is the single best-designed piece of policy in this
  codebase, and the "a name that does not parse is NEVER deleted" rule at
  `:233-239` is the right instinct.
- Scratch: `$TMPDIR/cutaway-tests` measured at 3.2 MB and rotating;
  `~/Library/Preferences/cutaway.tests.*.plist` swept by
  `Tests/CutawayTests/ScratchDefaults.swift`.
- `closedSessions` in-memory diagnostics: capped at 20
  (`DetectionEngine.swift:425`).

**Not capped:**

- **The detection log's 2 MB roll only runs in `init`**
  (`SessionLogger.swift:43`, `:46-56`). The comment says "rolled at launch
  rather than per write: the check costs one stat call once". For an app that
  runs for weeks without relaunching, the cap does not hold — the file grows
  past 2 MB and stays there until the next launch. The observed file is already
  374 KB from one day of test runs. A cheap fix that keeps the intent: count
  bytes written in the serial queue and re-stat only when the counter crosses
  the threshold — still no per-write `stat`.
- **Backups have no total-size budget.** 7 recent + up to 30 dailies + the
  eldest ≈ 38 folders. At a 90 KB store that is 3.4 MB and fine. At an 80 MB
  store — the size `StoreBackup.swift:188` explicitly anticipates — it is
  ~3 GB in Application Support with nothing watching. The rotation rules are
  right; they are just expressed only in generations, never in bytes.
- `DiagnosticsStore.combinedReport()` (`Diagnostics.swift:34-38`) concatenates
  all 10 payloads into one `String`. MetricKit crash payloads can be megabytes.
  Bounded, but the bound is "10 × whatever MetricKit felt like".

---

## 11. Smaller things, listed rather than argued

- `StoreBootstrap.swift:158` `try! makeMemoryStore()` — the only `try!` in
  `Sources/`. The comment justifies it and the justification is reasonable
  ("crashing is honest if it does"), but it is a launch-path crash and the
  branch is already inside a `catch`.
- `MenuBarPanel.swift:118-119` `model.selectedProject!` guarded by a
  `?.client.isEmpty == false` on the line above. Safe today — same synchronous
  render, and `selectedProject` is cached (`ProjectsModel.swift:119-124`) — but
  it is a re-read of a computed property to satisfy a force-unwrap, which is the
  shape that becomes a crash the first time the property gains a side effect.
- `DayTimelineView.swift:102-103` `dragging!` — guarded by the ternary
  condition, no crash, but see finding #2 for why the condition is wrong.
- `SwissQRCode.swift:29-34` uses `NSImage.lockFocus`, whose backing resolution
  follows the current graphics context. Inside `ImageRenderer`'s PDF pass that
  is not guaranteed to be the print resolution, and a QR code rendered at a
  scale where the modules do not land on integer boundaries is a payment part a
  bank scanner rejects. The payload is exactly tested
  (`Tests/CutawayTests/SwissQRBillTests.swift`); the *raster* is not tested at
  all, and it is the half that has to survive a printer.
  `PaymentPartView.swift:57` sets `.interpolation(.none)`, which helps but does
  not fix a source raster that is already too small.
- `idleRenderExemption = 1` is still in the owner's live preferences; the render
  exemption was deleted on 2026-09-08 (`DetectionEngine.swift:73-81`). Harmless
  dead key, but it is the kind of thing that confuses the next person reading a
  `defaults read`.
- `Invoice.number` has no `@Attribute(.unique)` (no `@Attribute` anywhere in
  `Sources/`). Uniqueness rests entirely on `InvoiceBuilder.nextNumber`
  (`:104-112`) reading every existing invoice. Single-actor, so no race today;
  worth knowing it is a convention rather than a constraint.

---

## Ranking

| # | Finding | Blast radius |
|---|---|---|
| 1 | Test suite writes the owner's live prefs; deletes the running app's crash snapshot and defers its backup | Data loss, wrong project billed |
| 2 | All timeline blocks share one id — edits/deletes hit the wrong session | Silent destruction of tracked work |
| 3 | `assertNothingInvoiced` has no production caller | Issued invoices lose their evidence |
| 4 | Undo's `restore` strips the invoice lock and UID | Double-billing a client |
| 5 | Untimed AX call into Resolve on the main thread (+ force-cast) | Menu bar freeze next to a render; likely the gate |
| 6 | `VACUUM INTO` on the main actor, including at quit | Hang, and a backup that may not complete |
| 7 | Panel walks full history 6×/second | Idle CPU grows with age |
| 8 | Truncated invoice PDF reported as success | A bad document sent to a client |
| 9 | Detection log's 2 MB cap only checked at launch | Unbounded file on a weeks-long run |
| 10 | Backups capped in generations, never in bytes | GB in Application Support at scale |

Findings 1 and 2 are measured. Finding 5's *mechanism* is measured (the test
host does reach the owner's live Resolve, 3–5 s into every run); its causal link
to the slow test is a hypothesis with a named two-minute experiment.
