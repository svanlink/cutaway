# Cutaway architecture review — 2026-09-07

*Branch `autoresearch/aug20`, 47 files / 6,398 lines, 0 dependencies, 355 unit tests.
Measured: Release build `real 21.07s` (user 56.76s). Live store 80 KB / 14 sessions / 3 projects.
Method: reading, plus one build. No Sources/ changed.*

The engine is sound. Every cost below **grows with tracked history** — the one thing
this app exists to accumulate. At 14 sessions none of it is visible; at four years it
all is, arriving gradually enough that nobody notices which release did it.

---

## 1. Launch path — one unbounded cost, and it is the new code

`AppModel.init` (`Sources/Cutaway/App/AppModel.swift:70-104`) runs four things on the
main thread before `SessionStore()` opens. Three are already cheap:

| Step | Real cost | Verdict |
|---|---|---|
| `StorePath.adoptLegacyIfNeeded()` | 2 `stat` calls after first run (the `!fileExists(target)` guard short-circuits) | fine |
| `StorePath.applyPendingRestore()` | 1 `stat` | fine |
| `StorePath.quickCheckOK(storeURL)` | **`PRAGMA quick_check` reads and verifies every page of the store** | unbounded |
| `StoreBackup.backUp()` | manifest `stat` compare, then `FileManager.copyItem` — which **clones** on APFS, O(1) regardless of size | fine |

`quick_check` is O(file): ~1 ms today, a synchronous 200–500 ms before the pill exists
at 80 MB. `StoreBackup` already learned this and solved it with `manifest.json`
(`StoreBackup.swift:196-207`, "fine at 80 KB, pointless at 80 MB"); the integrity check
reintroduces the same cost on the same path.

**Smallest fix:** gate it on evidence. Set `Prefs "cleanShutdown" = false` at the top of
`init`, `true` in `prepareForTermination()`. Run `quickCheckOK` only when the flag was
false. Six lines; removes the cost from ~99 % of launches and keeps it for exactly the
launches that follow a crash.

### Dangerous: the integrity check cannot tell "corrupt" from "cannot open" or "empty"

`quickCheckOK` (`StorePath.swift:59`) returns `false` when `sqlite3_open_v2` fails at
all — a permissions blip, a disk-full, a file locked by Time Machine. The app then
moves the live store aside and restores the newest backup. Every minute of billing
since that backup is gone, and the user is told it was a *recovery*.

The mirror failure is worse: a store truncated to zero bytes **passes** `quick_check`
(an empty database is valid), SwiftData recreates the tables, and the backup path never
fires.

**Smallest fix, one operator** — the helper already exists, used by
`stagePendingRestore` and `adoptLegacyIfNeeded`:

```swift
if FileManager.default.fileExists(atPath: storeURL.path),
   !StorePath.quickCheckOK(storeURL) || !StorePath.holdsCutawayTables(storeURL),
```

Plus: `quickCheckOK` should distinguish open-failure from check-failure and only the
latter should auto-restore. Return an enum, not a `Bool`.

**Housekeeping:** `.replaced-<stamp>` files (`StorePath.swift:104`) are never deleted —
full store copies in Application Support, forever.

---

## 2. Per-second and per-render work

The status item's `onEngineTick` (`StatusItemController.swift:88`) is correct — one
clock, dedupe on the accessibility string, 0.5 s tolerance. The costs are one layer up,
in what the views ask the store for.

**`todayMoney` (`AppModel.swift:370`) calls `store.dayTotals(for:)`** — a
`Dictionary(grouping:)` over *every session the project ever had*, plus a map and a
sort, once per second while the panel is open (the state users leave it in).
`activeSecondsToday` is memoised in `SessionStore.todayCache`; `todayMoney` is the one
figure that bypasses it.
**Fix:** widen the cache tuple to `(day, seconds, earned)` and sum `earned` in the same
pass at `SessionStore.swift:150-160` — same sessions, same rates, same
`invalidateTodayCache()`. Billing-neutral by construction. ~8 lines.

**`StatsView` walks the full history six times per render, per second.**
`statRows` (`StatsView.swift:97-101`): `totalActiveSeconds`, `dayTotalsIncludingLive`,
`avgDailySeconds` (which calls `dayTotals` again). `budgetRow:159-161`:
`avgDailySeconds` + `dayTotals`. `daysCard:195`: `dayTotalsIncludingLive` again. The
body re-evaluates every tick because it reads `engine.accumulator.activeSeconds`.
**Fix:** compute `dayTotalsIncludingLive` **once** in `body` and pass it down; derive
`total`, `dayCount`, `avg` from it. Pure hoist, deletes four store calls. Biggest single
win: the Stats window is what someone watches while a render runs.

**`detector.resolveEdition()` does a `FileManager.fileExists` per call**
(`ProjectDetector.swift:38`), and `MenuBarPanel.blocks()` reaches it two to three
times per body evaluation via `zeroState` and `shouldOfferAccessibility`. The Studio
marker cannot change while the app runs. **Fix:** `private static let studioMarker: Bool = …`.

**`pillSeconds` in `"total"` mode (`AppModel.swift:434`)** is an unmemoised
`totalActiveSeconds` every second, forever. Same cache, one more field.

**`evaluateRenderExemption` samples CPU before checking whether the feature is on**
(`DetectionEngine.swift:322-326`): `workAppCPUNanos` enumerates
`NSWorkspace.runningApplications` (50–150 entries) every second, though
`renderExemption` defaults **off**. Move the sample below the two guards — a rate one
second late is not a billing difference.

**The 15 s checkpoint writes 4 `UserDefaults` keys + 1 log line + 1 `os_log`**
(`DetectionEngine.swift:305`, `:391`). Per 8-hour recording day: ~23,000 defaults sets
and ~1,900 log appends, each opening, seeking, writing and closing a `FileHandle`
(`SessionLogger.swift:78-84`). The app's most plausible showing in Activity Monitor.
**Fix:** one encoded key instead of four; log every 4th checkpoint (60 s). Crash
recovery is unchanged — it reads `openSession.updatedAt`, not the log.

**The 30-minute backup timer should not exist.** It compares two `Date`s. Fold it into
the engine tick (`tickCount % 1800`); delete `startBackupSchedule()`, `backupTimer` and
one runloop source. *Caveat:* premium-audit #9 wants the tick timer stopped when nothing
can record — that plan and this one collide. Pick one owner for the clock.

**`backUpNow` runs `VACUUM INTO` on the main actor** (`AppModel.swift:230`,
`StoreBackup.swift:113`). Unlike the launch copy, `VACUUM INTO` is a *logical* copy —
no APFS clone, O(size). At 80 MB that is a multi-second main-thread stall, once a day,
beside a render. **Fix:** `Task.detached(priority: .utility)` for the daily path, hop
back to `recordBackup()`. Keep the quit path synchronous — the process is dying.
`StoreBackup` is a `nonisolated` enum already, so this is a wrapper, not a redesign.

---

## 3. SwiftData safety

**Unnamed stores: clean.** `ModelConfiguration` is constructed in exactly one place
(`SessionStore.swift:22-35`), never without a URL or `isStoredInMemoryOnly`. No
`@Query`, no `.modelContainer(for:)` anywhere in Sources.

**The residual risk is a future edit, not the current code.** One
`.modelContainer(for: Project.self)` in a view recreates the unnamed `default.store`
and the 2026-08 catastrophe with it. **Guard:** a five-line unit test that greps
Sources for `modelContainer(for:` and fails. Cheapest permanent insurance in the repo.

**Versioned schema: none, and now urgent.** `Project` and `WorkSession` are unversioned.
Today's additive properties (`hourlyRate`, `isAdjusted`, `appBundleIDs`) carry defaults,
so lightweight migration covers them. The problem is that
**adopting `VersionedSchema` later is itself a migration event** — SwiftData needs a
starting identity. Declare `SchemaV1` (an enum listing the two models,
`versionIdentifier 1.0.0`) and pass an empty `SchemaMigrationPlan` **before** the
client entity lands. ~25 lines, zero behaviour change, and without it v1.4 has no
migration story at all.

**On a migration the app cannot perform:** `SessionStore()` throws → in-memory fallback
→ `storeIsEphemeral` + banner. Honest, but a user who misses the banner works a day into
RAM. The next launch's backup correctly skips (manifest unchanged), so nothing is
overwritten. Acceptable; do not extend it.

**WAL handling is correct.** Launch backups copy `.store`/`-wal`/`-shm` while
quiescent; `snapshot` uses `VACUUM INTO`, which folds the WAL in;
`stagePendingRestore` carries sidecars when present and `applyPendingRestore` moves the
live `-wal` aside so no stale WAL survives a restore. `isUnchanged` compares
`.store` + `-wal` and ignores the derived `-shm` — right.

---

## 4. Structure

**`CutawayCore` (premium-audit #21, first half): don't.** Its own cited criterion is
"split when builds slow or you can't test a view without the whole stack". A full
Release build is **21 s wall**, and 355 tests already run against the app target. The
logic the package would hold — `BillingEngine`, `DetectionState`, `DaySplitter`,
`ZeroStatePolicy`, `StoreBackup.survivors`, the `AppModel` statics — is *already*
`nonisolated`/pure and *already* tested. The package buys a SwiftPM manifest, a second
test target, protocol seams on types that need none, and a "which module?" decision on
every future file. Architecture theatre. **Take the second half (versioned schema),
drop the first.**

**File sizes.** `AppModel` 532 earns one edit: the ~35-line launch sequence
(adopt → restore → integrity → backup) irreversibly touches the billing store and has
**no unit test**, because testing it means launching the app. Extract
`StoreBootstrap.open() -> (SessionStore, [Notice])` — one file, one function, testable
against a temp directory. Leave the rest: the 20 lines of `ProjectsModel` forwarding are
ugly but free; `DetectionEngine`'s 486 lines *are* the billing invariants, and splitting
them splits those. `MenuBarPanel` 440 / `StatsView` 408 are layout, not complexity.

---

## 5. Next quarter — structural cost, and what must exist first

**Invoice PDF (ImageRenderer → vector).** Cheap, zero dependencies:
`renderer.render { size, ctx in ctx(CGContext(consumer:mediaBox:nil)!) }`. Plain `Text`
stays selectable, SF Symbols become paths — but **any `.ultraThinMaterial`, `.blur`,
`.shadow` or gradient rasterises the page**, and `DesignTokens` is full of them.
**Precondition:** a pure `InvoiceDocument` struct (period, rows, totals, supplier,
client, tax) computed from `DayTotal`s, so the arithmetic is unit-testable and the view
is a dumb renderer. Otherwise the invoice's money lives in a `body`, untestable.

**Client entity.** Additive `@Model` — lightweight-safe. **Three preconditions:**
`SchemaV1` above; `Project.client: String` must **not** become `Project.client: Client?`
(a type change on an existing property fails lightweight migration — add
`clientRef: Client?` beside it, backfill, keep the String as the denormalised
display/CSV value); and a `sessions(from:to:)` `FetchDescriptor`, because invoicing
groups by *client × period*, which crosses projects, and every aggregation today walks
`project.sessions`.

**Per-day billing status + lock.** Structurally small, operationally the riskiest.
`SessionStore.setActiveSeconds` (`SessionStore.swift:105`) trims newest-first and
*deletes* sessions that reach zero. With no notion of a lock, one day edit silently
rewrites invoiced hours. **The locked-session guard must ship in the same commit as the
status field, or before it.**

**Day timeline.** The cheapest: `store.sessions(for:on:)` exists, no schema change.
Trim/split/reassign are three new mutations, each of which must call
`invalidateTodayCache()` and respect the lock.

---

## 6. What to take from GitHub (zero new dependencies)

- **[jordanbaird/Ice](https://github.com/jordanbaird/Ice)** (29.5k★) —
  `Ice/MenuBar/ControlItem/ControlItem.swift` drives `statusItem.length` from published
  state with `.removeDuplicates()`: written only when it changes. Cutaway's `syncWidth()`
  (`StatusItemController.swift:41`) calls `host.fittingSize` — a full SwiftUI layout pass
  — every second, then compares. **Take:** compare the rendered string first, measure
  only when its length changes. One line.
- **[p0deje/Maccy](https://github.com/p0deje/Maccy)** (21.5k★) —
  [`Maccy/Storage.swift`](https://github.com/p0deje/Maccy/blob/master/Maccy/Storage.swift)
  names its store `Maccy/Storage.sqlite` and goes in-memory under test: the same pattern
  Cutaway already has, from a 21.5k★ app. **Take nothing** — and note its `fatalError`
  on open failure is exactly what Cutaway is right not to copy.
- **PDF:** no repo needed. `ImageRenderer.render` into a
  `CGContext(consumer:mediaBox:aux:)` is the whole technique
  ([hackingwithswift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-render-a-swiftui-view-to-a-pdf)).
  `shaps80/GraphicsRenderer` is dependency-free and still ~1,200 lines to avoid ~15. **No.**
- **Energy:** nothing to copy. Ice polls at 1/3/5/10 s across seven sites; Cutaway runs
  one 1 Hz clock at 50 % tolerance with `NSWorkspace` notifications for frontmost
  changes — ahead of the exemplars. Every win is internal, in §2.

---

## Ranked

1. Fix the integrity check (`||holdsCutawayTables`, open-failure ≠ corruption) — data loss, ~5 lines.
2. Lock guard in `setActiveSeconds` before per-day status ships — silent rewrite of invoiced hours.
3. `SchemaV1` + empty migration plan before the client entity — ~25 lines, no second chance.
4. Memoise today's `earned`; hoist `dayTotals` in `StatsView` — the two per-second walks.
5. Gate `quick_check` on unclean shutdown; move `VACUUM INTO` off the main actor.
6. Move the CPU sample below its guards; one key + 60 s logging for checkpoints; delete the backup timer.
7. Extract `StoreBootstrap`. Do **not** extract `CutawayCore`.

## Arbitration 2026-09-07: the invoice data model

*Ruling. Billing wins the substance; Architecture wins the sequencing and one structural point.*

### 1. Storage: snapshot, with references for provenance only

`Invoice` is a frozen snapshot. Architecture's duplication objection is noted and
overruled — an invoice is a document, not a query, and a view over live sessions cannot
survive a rate edit, a day edit or a Zurich→Bogotá move. Architecture's real win: the
snapshot must not be the *only* record of where a figure came from.

```
@Model Invoice   // every printed field is a COPY
  number, statusRaw(.draft/.issued/.paid/.void), issueDate, dueDate,
  periodStart, periodEnd, currencyRaw, taxModeRaw, taxRate,
  supplierBlock, clientBlock: String,        // copies, never a Client ref
  subtotal, taxAmount, total: Double,
  timeZoneIdentifier: String,                // the zone the days were grouped in
  qrReference: String?,
  @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice) lines: [InvoiceLine]

@Model InvoiceLine
  kindRaw(.time/.dayRate/.minimum/.manual/.deposit), day: Date?, text: String,
  quantity, unit, unitPrice, amount, adjustedHours: Double,
  sessionUIDs: [String]                      // provenance, NOT a relationship

WorkSession  += uid: UUID = UUID(), invoiceNumber: String = ""
```

`sessionUIDs` as strings, not a SwiftData relationship: a relationship's inverse pulls
live sessions back into the invoice — the exact coupling Architecture fears — and drags
invoices into every session fetch. `invoiceNumber` is the lock, denormalised so the
guard is checkable without loading the invoice. Non-empty = locked. Every figure stays
traceable (doctrine) and every figure is a copy (Billing).

### 2. What "locked" means

**Refuse:** `setActiveSeconds` on a day holding a locked session; deleting a locked
session; deleting or reassigning a project with locked sessions; any rate edit that
would reprice locked work. Message names the number.
**Allow with warning:** new work recorded inside an invoiced period — it lands
unlocked and bills next period, never silently folded back (under-bill bias); a
forward-only rate change.
**Correction path: void-and-reissue.** Not a credit note — that needs an accruing
cross-document balance, the same forever-correct state Billing §4 already refused for
retainers and late fees. Not an unlock — an issued document that can silently disagree
with the store destroys the property this whole ruling buys. Voiding keeps the number
(printed VOID, never reused, sequence stays gapless), clears `invoiceNumber` on its
sessions, and the correction then happens in the ordinary editing path.

### 3. Schema versioning lands first. Blocking.

`SchemaV1` (Project, WorkSession, `versionIdentifier 1.0.0`) + an empty
`SchemaMigrationPlan` ship in their own commit; `Invoice`/`InvoiceLine` are SchemaV2.
What breaks otherwise: adding two entities to `ModelContainer(for:)` changes the store's
implicit schema identity with no declared origin, so a later `SchemaV1` has no version
to migrate *from*. The only path left is `SessionStore()` throwing into the in-memory
fallback — `storeIsEphemeral` plus a banner someone misses while a render runs, and a
day of billing into RAM. ~25 lines, no second chance.

### 4. Currency

**A session does not stamp currency.** Its money is `activeSeconds × hourlyRate` and the
rate is already stamped; currency belongs to the agreement, not the minute, and
per-session currency invites a mixed-currency day no honest total can add. The
**invoice** stamps it.
Changing a project's currency: refused outright once any session is locked. While
nothing is invoiced, allowed with an explicit confirmation that **converts nothing** —
past amounts are reinterpreted, not translated. Conversion needs a rate Cutaway cannot
fetch (no network) and a date it cannot defend.
Minor units are a property of the currency (COP 0, CHF/EUR/USD 2) in one shared
function used by `round2`, `format` and the CSV.

### 5. Tests that pin this

Failing today: `InvoiceArithmeticTests.testRoundingModeAgreesAcrossSurfaces` —
`format(round2(x)) == format(x)`; CHF 45/h, 3'610 s → CSV `45.13`, Stats `CHF 45.12`.
`SessionStoreTests.testAdjustmentCarriesRateOfCorrectedDay` — `setActiveSeconds` stamps
`project.hourlyRate`, today's rate.
New: `testSetActiveSecondsRefusesInvoicedDay` · `testDeleteProjectRefusesWhenSessionsInvoiced`
· `InvoiceSnapshotTests.testIssuedTotalSurvivesRateChange` ·
`testIssuedTotalIsTimeZoneIndependent` · `testVoidKeepsNumberAndReleasesSessions` ·
`testReissueNeverReusesVoidedNumber` · `testEveryLineTracesToSessionUIDs` (no orphans,
no duplicates, Σ `adjustedHours` drives the footnote) ·
`testBudgetProjectBillsMinAccruedBudget` (48 h × 120 vs CHF 4'500 → 4'500) ·
`SchemaVersionTests.testSchemaV1DeclaredBeforeInvoiceEntity`.

**Risk accepted:** a bug in the snapshot builder freezes into a document already sent.
`sessionUIDs` let the app *detect* the divergence; only void-and-reissue can fix it, and
the client already holds the wrong PDF.

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

## Arbitration 2026-09-07: store damage and recovery

Both departments diagnosed the same defect. Both prescriptions are incomplete. Ruling
below is binding for the branch; nothing in Sources/ was changed to produce it.

### 1. The damage test

`quickCheckOK -> Bool` is abolished. `StorePath.verdict(_:) -> Verdict` returns one of
`absent`, `usable`, `unreadable(reason)`, `damaged(reason)`, evaluated in this order:

| Condition | Verdict |
|---|---|
| file does not exist | `absent` |
| `sqlite3_open_v2` returns CANTOPEN / PERM / AUTH / BUSY / LOCKED / READONLY / IOERR / FULL | `unreadable` |
| open returns NOTADB or CORRUPT | `damaged` |
| `PRAGMA quick_check` aborts with BUSY / LOCKED / IOERR mid-scan | `unreadable` |
| first `quick_check` row != "ok" | `damaged` |
| quick_check ok, `sqlite_master` holds no tables (covers the 0-byte file) | `damaged` |
| quick_check ok, tables present, no `ZPROJECT` | `damaged` (foreign) |
| quick_check ok, `ZPROJECT` present — **including with zero rows** | `usable` |

Permissions, disk-full and a Time Machine lock are `unreadable`, never `damaged`.
Zero-byte and foreign-schema are `damaged` — architecture's `holdsCutawayTables`
conjunction is upheld, but as a classifier, not as a restore trigger. An empty
*Cutaway* store is `usable`: restoring over a legitimately empty first run is the
2026-08-23 loop in reverse.

Architecture's `cleanShutdown` gate is granted for the `quick_check` page scan only.
Existence, open, and the `sqlite_master` probe are O(1) and run every launch.

### 2. Verdict → action, and consent

**Ruling: the app may never move, replace or overwrite the live store without the
owner saying yes first. No exception, including the automatic path.** Quality wins
this point outright; architecture loses it. The reasons are that the classifier can be
wrong, `.replaced-<stamp>` is not a visible undo, `storeErrors.notice` is a banner
*after* the swap, and every recovery that has actually happened on this Mac was done
by hand and worked.

- `absent`, `usable` → open. Say nothing.
- `unreadable` → touch nothing. Flag the reason, let `SessionStore()` fail into the
  existing in-memory fallback and its banner. Retry next launch. A lock or a full disk
  heals; a restore does not give back the minutes it drops.
- `damaged` / foreign → still touch nothing. Modal at launch naming the reason, the
  newest *usable* backup, its age and its session count: **[Restore that backup]
  [Open Backups folder] [Continue without restoring]**. Only button one stages and
  applies. Button three runs in memory and never writes over the damaged file.

`AppModel.init` therefore cannot own this. Extract `StoreBootstrap.plan(storeURL:
backupsDir:) -> Plan` — pure, no mutation — and let `AppDelegate` act on the plan.
README's "restored automatically" sentence is now false and must change with the code.

### 3. Restore selection

Match by content, never by name. The source store in a backup folder is the entry
matching `*.store` (excluding `-wal`, `-shm`, `manifest.json`) that passes §1 as
`usable`. Several candidates: prefer the live store's own name, else the largest.
Sidecars follow the chosen stem and are renamed to the live name during staging.
This opens all twelve folders the owner has — `default.store`, `timex.store`,
`billing.store` alike. Automatic candidate selection iterates newest-first and skips
any folder whose store is not `usable` (quality's fallback loop, granted). The
confirmation must print folder stamp, internal file name and `count(*)` from
`ZWORKSESSION`; that count is how the owner tells a real backup from a harness one.

### 4. Harness quarantine

`AppModel.backupsDir` becomes derived, not absolute:
`StorePath.url().deletingLastPathComponent().appendingPathComponent("Backups")`.
One quarantine gate for store and backups; `CUTAWAY_SCENARIO` stops being a second,
weaker gate. The five existing `timex.store` folders are the **owner's** files — the
app never deletes what it cannot classify, and that rule stays. Remove them by hand
before rotation acts, and add the check to the release list. Rotation stays pure on
names.

### 5. Retention and litter

- The oldest surviving generation is never evicted. One line in `survivors`; ~800 KB.
  Without it `billing-20260823-122952` — the pre-incident copy — dies on 2026-09-22.
- Newest-`keep` and newest-per-day for 30 days stand as written.
- `.replaced-*`: keep the newest always, delete the rest past 30 days, at launch.
  `.staging-*` past 24 h likewise.

### 6. Tests that pin this — 10 of 11 fail today

1. chmod 000 store → `unreadable`, not `damaged`. **FAILS**
2. 0-byte store → `damaged`. **FAILS**
3. `ZAPIREQUESTMODEL`-only store → `damaged` (foreign). **FAILS**
4. `ZPROJECT` with zero rows → `usable`, no restore proposed. passes; pin it.
5. Stage a restore from a folder holding `default.store`. **FAILS**
6. Same for `timex.store`. **FAILS**
7. Folder whose store is byte-truncated → skipped; the next-newest usable one is
   chosen. **FAILS**
8. `backupsDir` with `CUTAWAY_DATA_DIR` set resolves under the data dir. **FAILS**
9. `survivors` over 40 names spanning 60 days keeps the oldest. **FAILS**
10. `.replaced-*` cleanup keeps the newest, drops a 40-day-old one. **FAILS**
11. `StoreBootstrap.plan` on a damaged store returns `.askBeforeRestoring` and mutates
    nothing on disk. **FAILS**
