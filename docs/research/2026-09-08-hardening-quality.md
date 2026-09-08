# Hardening pass — 2026-09-08

Branch `autoresearch/aug20`, HEAD `bf498b8` (moved from `648d6aa` mid-pass).
Nothing was fixed and nothing under `Sources/` was modified. Every finding
below was reproduced with a throwaway probe appended to an existing test file
and reverted immediately after; the probe output is quoted verbatim.

## Gate

| Stage | Result |
|---|---|
| `-only-testing:CutawayTests` | **PASS** — `Executed 487 tests, with 6 tests skipped and 0 failures (0 unexpected) in 15.535 (15.747) seconds` / `** TEST SUCCEEDED **` |
| `./scripts/smoke.sh "" 3` | **PASS** — `RESULT: ALL PASS`, binary stamped `2026-09-08 18:32` (today) |
| `-only-testing:CutawayUITests` | **FAIL** — `Executed 10 tests, with 1 test skipped and 3 failures (2 unexpected) in 78.666 s` / `** TEST FAILED **` |

Filter used: `^.*\.swift:[0-9]+:[0-9]+: error:` — no compile errors at any stage.

### The three UI failures

```
AccessibilityAuditTests.swift:58: error: -[AccessibilityAuditTests testProjectSheetPassesAccessibilityAudit] : Element has no description
AccessibilityAuditTests.swift:58: error: -[AccessibilityAuditTests testSettingsWindowPassesAccessibilityAudit] : Element has no description
MenuBarKeyboardTests.swift:56: error: -[MenuBarKeyboardTests testThePillOpensThePanelAndThePanelIsReachable] : XCTAssertTrue failed - the panel's contents must be in the accessibility tree
```

Both audit failures name the same offender, and it is not Cutaway's:

```
AUDIT ISSUE: type=4 label='' id='SafariPlatformSupportAutoCompleteWindow' — This element is missing useful accessibility information.
```

`SafariPlatformSupportAutoCompleteWindow` is a system autofill window that
drifted into the app's accessibility tree during the run. It belongs in the
audit's existing ignore-by-identity list beside the Touch Bar representation
and SwiftUI's window content group — the list at `AccessibilityAuditTests.swift`
already exists for exactly this class of element.

`MenuBarKeyboardTests` is a **flake**, not a regression: re-run alone it is
green, `Executed 5 tests, with 0 failures (0 unexpected)`. The most likely
cause is the same rogue system window taking the status-item click.

**Verdict: the UI gate does not pass reproducibly on this machine right now.**
Nothing in it points at a defect in today's code, but the charter's gate is
red and a tag must not exist until it is green.

---

## Findings, ranked by money at risk

### 1. A day that is already on an invoice is billed again, in full

`Sources/Cutaway/Billing/InvoiceStore.swift:84-85`, and the identical line in
the live preview at `Sources/Cutaway/Billing/InvoiceSheet.swift:230`:

```swift
let days = dayTotals(for: project, calendar: calendar)
    .filter { uidsByDay[$0.day] != nil }
```

`billableSessions` correctly excludes locked work. `dayTotals` does not — it
sums **every** session on the day, invoiced or not. So a day survives into the
new invoice as soon as it holds one unbilled second, and it arrives carrying
its whole total.

The state that produces it is the ordinary one. `record()` (auto-tracking),
`recoverCrashedSession()` and the running session that closes after the invoice
was issued all write into an invoiced day deliberately — the design says such
work "bills NEXT period rather than being folded silently into a document
already sent". It is not folded in. It drags the whole day back with it.

Concrete input, reproduced:

```
4 Sept 09:00–11:00, 2 h @ 100 → issue "This month" → INV-2026-0001, CHF 200.00
4 Sept 14:00–15:00, 1 h @ 100  (the running session closes after issue)
              → issue "This month" again
PROBE1b second-invoice-total=300
```

CHF 300 charged where CHF 100 is owed. The 2 h on the first invoice is billed a
second time. The line's `sessionUIDs` list only the unbilled session, so the
document's own provenance contradicts its quantity.

`InvoiceSnapshotTests.testWorkAlreadyInvoicedIsNeverBilledTwice` misses this
because its second session is on a **new day** (5 Sept), where the day-level
filter happens to be right.

Smallest fix: build the day totals from the billable sessions rather than from
`dayTotals`, i.e. aggregate `sessions` (already in hand, already filtered) into
`DayTotal`s instead of re-deriving them from the project. One function, and the
preview at `InvoiceSheet.swift:230` must use the same one.

Related, same root, lower value: an unbilled hour stranded on an already-invoiced
day outside the next period is skipped entirely (`PROBE5 total=100`), and can only
ever be collected by a re-bill that also double-bills the day.

### 2. Undo unlocks an invoiced day and destroys the invoice's provenance

`Sources/Cutaway/Projects/SessionStore.swift:261-272` (`restore`), reached from
`Sources/Cutaway/Projects/EditHistory.swift:34-47` (`registerUndo`).

`restore` deletes every session on the day and re-inserts new ones from a
`DayEdit.Session` snapshot that carries `start`, `end`, `activeSeconds`,
`hourlyRate`, `isAdjusted` — and **not** `uid`, and **not** `invoiceNumber`
(`EditHistory.swift:12-18`).

Every edit path refuses an invoiced day, so a snapshot is only ever *taken* on
an unlocked day. But the undo *fires* later, and an invoice can be issued in
between. The undo stack is app-lifetime and spans both scenes.

Concrete input, reproduced:

```
4 Sept, 2 h @ 100. Edit the day (snapshot taken). Issue the invoice → CHF 200, day locked.
Press ⌘Z.
PROBE2 locked-after-undo=[""] uids=[""] invoiceUIDs=["5EC8DB11-…"]
       unbilledTotal 0 → 200
```

Afterwards: the day is unlocked and freely editable, the work is billable again
(so finding 1 will bill it a second time), and the issued invoice's line points
at a UID no session carries — the document can no longer be traced to the work
it describes, which is the one property `Invoice`'s header comment says the
whole snapshot design exists to buy.

Smallest fix: carry `uid` and `invoiceNumber` in `DayEdit.Session` and restore
them; and have `restore` refuse outright when the day is invoiced, the same
guard every other write already has.

### 3. Dragging a block sideways bills the idle the engine excluded

`Sources/Cutaway/Stats/DayTimelineView.swift:170-176` — the `.body` branch,
under the comment *"A move corrects WHEN, never how much"* — sets
`end = start + block.span` and hands both to
`Sources/Cutaway/Projects/SessionStore.swift:155`:

```swift
session.activeSeconds = end.timeIntervalSince(start)
```

`activeSeconds` is routinely **less** than the span; that difference is the idle
and gap time the detection engine deliberately refused to bill, and the strip
draws it and the tooltip names it (`· 1:30 idle excluded`). Any move rewrites
`activeSeconds` to the full wall-clock span.

Concrete input, reproduced:

```
13:00–17:00 wall, 2:30 active (idle excluded), CHF 120/h.
Nudge the block 5 minutes right.
PROBE13 activeBefore=9000 activeAfter=14400.0 earnedBefore=300.0 earnedAfter=480.0
```

CHF 180 invented, silently, by a gesture the code believes changes nothing but
the hour. This is the app inventing time that was never worked and putting it in
front of a client — the failure direction the whole engine is built to avoid.

A trailing-edge resize of the same block does it too
(`PROBE14 active=14700.0` for a 5-minute stretch), and there the intent is
arguable, but filling a four-hour span with four hours of "work" is not.

Smallest fix: in `updateSession`, preserve the worked fraction rather than
overwrite it — `activeSeconds = min(newSpan, activeSeconds * newSpan / oldSpan)`,
the same proportional rule `DayTimeline.split` and `DaySplitter` already use. A
pure move then leaves it untouched, which is what the comment promises.

### 4. A fixed price is a ceiling per invoice, not per job

`Sources/Cutaway/Billing/InvoiceBuilder.swift:75-90`. `budgetCapped` caps the
draft at the full budget every time it runs. It has no notion of what earlier
invoices on the same project already billed.

Concrete input, reproduced:

```
Budget project, CHF 1'000 agreed, CHF 100/h.
1–3 Sept, 24 h → issue → capped at CHF 1'000.
5–7 Sept, 24 h → issue → capped at CHF 1'000 again.
PROBE3 invoiceA=1000 invoiceB=1000 sum=2000 budget=1000
```

CHF 2'000 billed against a CHF 1'000 fixed price. `testABudgetProjectBillsTheBudgetNotTheOverrun`
only ever issues once.

Smallest fix: `budgetCapped` takes the already-invoiced total for the project
and caps at `budget - alreadyBilled` (clamped at zero, which then trips
`nothingToBill` and says so).

### 5. The mismatch rule is a one-way door — the clock can never restart

`Sources/Cutaway/Detection/ProjectAutoSwitcher.swift:67`:

```swift
let active = engine.state == .recording || engine.state == .paused(.noProject)
guard active else { return }
```

This is the **only** caller of `detectProjectName()` and `detectViaScriptingAPI()`
in the app. `.paused(.projectMismatch)` is not in that set, so the moment the
mismatch rule stops the clock, detection stops running. `resolveProject`
(`AppModel.swift:256`) then freezes at the stale name and `projectMismatch`
(`AppModel.swift:262-266`) stays true forever.

The clearest way in is `ignoreDetectedName` (`AppModel.swift:324-327`): it adds
the name to the ignore list and clears the card, but never clears
`resolveProject`. `detected()` returns at `case .stay, .ignore: return`
(`AppModel.swift:279`) before the card can be re-raised.

Concrete sequence:

```
Resolve opens a personal file. The card asks. Owner clicks "Not billable".
→ resolveProject = that name, projectMismatch = true, engine → .paused(.projectMismatch)
→ ProjectAutoSwitcher.tick() now early-returns on every tick
Owner closes it, opens the real client project in Resolve, works all afternoon.
→ Cutaway never looks again. Nothing is recorded. Nothing is asked.
```

The same trap is reachable without "Not billable" — any mismatch that is not
resolved from the card leaves detection switched off, so Resolve returning to
the correct project is invisible.

The only exits are quitting Resolve entirely (`AppModel.swift:166` clears
`resolveProject` when `resolveEdition() == nil`) or relaunching Cutaway. An
afternoon of billable hours is recorded nowhere. The mismatch banner
(`MenuBarPanel.swift:206`) names a project that is no longer on screen, so the
one visible cue is actively misleading.

`MismatchReleaseTests` does not catch it: both its cases recompute the rule
inline from local `let`s and assert on that, never touching `AppModel` or the
switcher — the release path it is named for is never executed.

Smallest fix: add `.paused(.projectMismatch)` to the `active` set at
`ProjectAutoSwitcher.swift:67`. Detection is what ends the hold; it must keep
running while the hold is on.

### 6. A normal month with an IBAN issues, locks, and then cannot be printed

`Sources/Cutaway/Billing/InvoicePDF.swift:20-28` refuses more than
`maxLinesWithPaymentPart = 16` lines when a payment part is present. In
`Sources/Cutaway/Billing/InvoiceSheet.swift:253-277` that check runs **after**
`issueInvoice` has already allocated the number, frozen the document and locked
every session.

An invoice carries one time line per worked day. Bill a month with 17 or more
worked days with an IBAN entered — the ordinary case — and the owner gets
*"The invoice was issued, but the PDF could not be written"*, an issued
invoice, a consumed number, a locked month, and no document to send. The only
way out is Void.

This contradicts the rule stated eight lines above it at `InvoiceStore.swift:61`:
*"Refuse before anything is written."*

Smallest fix: apply the same line-count limit in `issueInvoice`, before the
`Invoice` is inserted.

### 7. The QR payment part carries a malformed creditor and debtor address

`Sources/Cutaway/Billing/InvoiceDocumentView.swift:162-169`:

```swift
let creditor = SwissQRBill.Address(name: line(invoice.supplierBlock, 0),
                                   street: "", buildingNumber: "",
                                   postalCode: "", town: line(invoice.supplierBlock, 1),
                                   country: "CH")
```

The address field the sheet asks for is prompted *"Street, postcode and town"*
and is a three-line vertical field, so `supplierBlock` line 1 is the **street**.
It is written into the payload's `town`. `postalCode` is emitted empty, and a
structured (`"S"`) address requires postal code and town. `country` is
hardcoded `"CH"` for the **debtor** too — wrong for every reverse-charge EU
client, which is a tax mode the app explicitly offers.

`SwissQRBillTests` never reaches this: it constructs `SwissQRBill.Address`
values by hand with each field correctly populated, and asserts on field
*order*. The block-to-address mapping — the only place a real address is
converted — has no test.

Money at risk is a bill a bank's scanner rejects, and the app tells the owner to
validate the first one at `validation.iso-payments.ch`, so it is likely caught
once rather than repeatedly. Still a document that disagrees with itself.

Smallest fix: parse postal code and town from the last address line
(`^(\d{4,6})\s+(.+)$`) and put the remaining lines in `street`; take the debtor
country from the client's address rather than a constant.

### 8. Release: the shipped binary need not be the tagged tree

`scripts/release.sh:25` builds Release from the working tree. Nothing in the
script checks that the tree is clean — line 22 only commits `project.yml` and
`Info.plist`. Uncommitted work in `Sources/` is compiled into the zip, hashed,
published and written into the cask, while the tag points at a tree that does
not contain it.

Smallest fix: `git diff --quiet && git diff --cached --quiet || { echo "working tree is dirty"; exit 1; }`
before line 10.

Also worth naming: `release.sh:11-12` runs the unit suite and smoke ×3 but not
`CutawayUITests`, and CI (`.github/workflows/release.yml`) runs only
`-only-testing:CutawayTests`. The gate that can actually stop a tag is narrower
than the charter's gate — which is why today's red UI suite would not have
blocked a release.

---

## What must be true before a tag exists

1. Findings 1–4 fixed. Each of them either bills a client money they do not owe
   or bills the owner's own work twice; a tag that ships any of them ships a
   wrong invoice.
2. Finding 5 fixed. It is the only one that loses hours outright, and it is
   unbounded — it persists until the owner notices and relaunches.
3. `CutawayUITests` green twice in a row on a quiet machine. Today's red is
   environmental, but "environmental" has to be demonstrated, not assumed, and
   the `SafariPlatformSupportAutoCompleteWindow` ignore entry is the honest way
   to demonstrate it.
4. A clean-tree guard in `release.sh`.
5. Regression tests that pin the shapes, not the models of the shapes:
   a partially-invoiced day, an undo that crosses an issue, a body drag on a
   block holding idle, a second invoice on a budget project, and a mismatch
   that ends because Resolve went back to the right project.

## Checked and sound

These were probed and behaved correctly; no change needed.

- **Midnight and DST arithmetic.** A 22:00→04:00 span across the 25-hour
  fall-back night splits into exactly 2 day parts and preserves all 25'200 s
  (`PROBE7`). A 01:30→04:30 span across the spring-forward hour stores its true
  7'200 s (`PROBE6`). `DaySplitter` uses `date(byAdding:.day)` on
  `startOfDay`, which is DST-correct.
- **Split arithmetic.** `DayTimeline.split` rounds the first half and gives the
  second the remainder; a split and its undo both preserve 9'000 s exactly and
  the session count returns to 1 (`PROBE8`).
- **Reassign.** Moves the money with the work, keeps the stamped rate
  (`PROBE10`: A → 0, B → 200 at A's original rate, not B's), and the two-sided
  undo in `EditHistory.reassignSession` restores both projects exactly
  (`PROBE9`), in the order the closure actually uses.
- **Panel vs document.** `unbilledTotal` rounds per session and the invoice
  rounds per day, but on three same-day sessions engineered to land on
  half-rappen ties they agree to the rappen (`PROBE4`: 135.41 = 135.41).
- **Blended rate.** A day worked at two rates prints an effective rate that
  reconciles: `qty 2 × rate 175 = amount 350` (`PROBE12`).
- **Day-total round trip.** Shrink to 1 h then grow back to 2 h returns 7'200 s
  and keeps the day's first and last activity (`PROBE11`).
- **Invoice numbering.** `nextNumber` takes the max over all invoices including
  voided ones, `voidInvoice` keeps the number, and both survive a relaunch
  because the fetch is over the store, not over memory. No reuse path found.
- **Store classification.** `StorePath.verdict` separates `unreadable` (disk)
  from `damaged` (file), treats a zero-byte file as damaged via the table
  count, and treats an empty `ZPROJECT` as a legitimate first run.
  `StoreBootstrap` decides and never touches a file, and `DamagedStoreAlert`
  correctly withholds the Restore button when there is no candidate — so the
  one unguarded branch in `StoreBootstrap.open` (`.restore` with a nil
  candidate falls through and opens the damaged file) is not reachable from the
  shipping alert. Worth a `guard` anyway, since `askAboutDamagedStore` is a
  replaceable static.
- **Test-run quarantine.** `StorePath.url` diverts on both `CUTAWAY_DATA_DIR`
  and `XCTestConfigurationFilePath`; `AppModel.backupsDir` follows the open
  store rather than a hard path; `demoSeedAllowed` requires a quarantined dir;
  `StoreBootstrap.open` skips adoption, backup and restore in scenario mode;
  and both UI test helpers set `CUTAWAY_DATA_DIR`. I found no path by which a
  test or scenario run can write to the owner's real store.
- **Backup rotation.** `survivors` keeps the newest N, the eldest generation
  unconditionally, and each day's newest for 30 days, and never deletes a name
  it cannot parse.

---

## Note on concurrency

Every finding above was read and reproduced against committed `bf498b8`, and
the three gate stages were run against that tree. While this pass was running,
a parallel pass left uncommitted changes in `Sources/Cutaway/App/AppModel.swift`,
`Detection/ProjectAutoSwitcher.swift`, `Detection/ProjectDetector.swift`,
`MenuBar/MenuBarPanel.swift` and `MenuBar/PromptPanel.swift`.

Finding **5** (the mismatch deadlock) is already addressed by that work:
`ProjectAutoSwitcher.tick()` now includes `.paused(.projectMismatch)` in its
`active` set, and an "ask again" path off the ignore list has been added. The
finding is left in full because it was real at HEAD and because the regression
test named in the release checklist does not exist yet.

Findings **1, 2, 3, 4, 6, 7 and 8** are untouched by those changes. The gate
must be re-run once that work is committed — the numbers in this document
describe `bf498b8`, not the current working tree.
