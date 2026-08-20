# Cutaway Loop Journal

Autoresearch-style state: what was tried, what happened, kept or reverted.
Newest entries at the top. Readiness score updates with each [ship] entry.

Readiness: 6/6 proven — PRODUCTION PUSH COMPLETE, v1.1.0 live (R-INSTALL, R-BACKUP, R-DEGRADE, R-LOCALE, R-DOCS, R-RELEASE)

---

## 2026-08-20 ~18:21 — [billing] Invoice period export — KEPT
Export dumped the whole project history every time, so billing a month meant
editing the file in Excel — and the cumulative columns were all-time, so the
hand-edited file was wrong in a way that looked right.

`Export CSV` is now a menu: All time / This month / Last month / This year.
Presets rather than a date picker, because the question is always "bill last
month", never "bill March 3rd to the 19th" — and a preset cannot be
mis-entered.

Filtering happens INSIDE the exporter, not at the call site. That is the
whole point: cumulative columns are computed over whatever survives the
filter, so a caller that filtered wrongly (or filtered and forgot the
cumulatives) would produce exactly the plausible-looking wrong file this
goal exists to prevent. The exporter also now writes `period_start` /
`period_end` into the summary, so a client can see what span they are paying
for without inferring it from the rows.

Filenames carry the period ("Nyx — 2026-07 — Cutaway.csv") so two invoices
for one client stay apart in a downloads folder.

VERIFY met: InvoicePeriodTests, 10 tests — outside days excluded, cumulative
columns restart inside the period, summary reconciles with its own rows, an
empty period produces an honestly empty file rather than claiming dates, and
the presets are right including across a year boundary (Jan -> last December).
Gate 147/147 + smoke ALL PASS (3 iterations) + accessibility audit passes.

## 2026-08-20 ~18:17 — [billing] Rate history — KEPT
The worst of the three invoicing defects. Every earnings figure in the app
was `activeSeconds × project.hourlyRate` — the CURRENT rate — and
WorkSession stored no rate. A raise silently repriced every past day,
including days already invoiced, so a re-export disagreed with the invoice
the client had already paid.

WorkSession now carries `hourlyRate`, stamped at record time. DayTotal
carries `earned` rather than letting each consumer recompute it, because
the sessions behind a day may have been worked at different rates; its
`effectiveRate` blends a day that spans a change so `hours × printed rate`
still reconciles with `earned`. CSV, Stats, the day rows, the session detail
lines and today's money all read the carried figure. Legacy rows (rate 0)
fall back to the project rate — exactly what they were billed under.

MIGRATION PROVEN, NOT ASSUMED. This is the first iteration to change the
shape of the billing store, so it was verified end to end rather than
trusted: built the previous commit in a git worktree, ran it against a
scratch data dir to write a store with the OLD schema (columns: Z_PK Z_ENT
Z_OPT ZPROJECT ZACTIVESECONDS ZEND ZSTART), then opened that same file with
the NEW binary. Result: ZHOURLYRATE added by lightweight migration, the
existing session intact at 59.0s, its rate 0.0 -> project-rate fallback.

GATE FAILURE ON THE WAY — 5 red, in CSVExporterTests. The failing
assertions (586.50, 977.50) were RIGHT; the FIXTURE was incomplete, because
a DayTotal must now carry its earned. Fixture updated to the same 85/h
figures the assertions already expected; `git diff | grep XCTAssert`
returned nothing, which is the check that the verifier stayed sacred. Had
the assertions themselves needed changing, the correct move was revert.

VERIFY met: RateHistoryTests — a raise does not reprice done work, the total
always reconciles with the days across multiple changes, legacy rows price
at the project rate, a day spanning a change blends, and the rate is
stamped at record time rather than read later.
Gate 137/137 + smoke ALL PASS (3 iterations) + accessibility audit passes.

## 2026-08-20 ~18:20 — AUDIT iteration (bias: invoicing / CSV) — 3 goals added
Walked the path a freelancer actually takes: work a month, open Stats,
Export CSV, send it to a client who checks it. Three findings, all money.

1. RATE HISTORY. WorkSession stores start/end/activeSeconds and no rate;
   every earnings figure anywhere is `seconds × project.hourlyRate` at
   TODAY's rate. Raise your rate and history rewrites itself — the October
   export of September's work disagrees with the invoice you already sent,
   and the new file is the wrong one. This is the worst of the three: it
   silently changes numbers a client has already paid against.

2. NO INVOICE PERIOD. `CSVExporter.export` takes whatever days it is handed
   and CSVExportButton hands it all of them. Billing a month means editing
   the file by hand, and the cumulative columns are all-time, so the
   hand-edited file is wrong in a way that looks right.

3. PENNY DRIFT — proven, not theorised. Rows print rounded to cents;
   total_earned prints the rounded sum of the UNROUNDED values. Searched for
   a real case rather than asserting one: 12 days at 85/h where the rows sum
   to 5572.71 while total_earned prints 5572.72. One cent, in a document a
   client is paying against, is a credibility problem out of all proportion
   to its size.

Note what this audit did NOT propose: a PDF invoice generator, an invoice
number scheme, a client database. Those are features; these three are
defects in what the app already claims to do.

No code changed this iteration.

## 2026-08-20 ~18:06 — [ux] In-context Accessibility offer — KEPT
Accessibility is the difference between instant project switching and a
30–120s scripting poll, and it was discoverable only by wandering into
Settings. The timer now offers it once, in place, saying what the user GETS
rather than what the OS calls the permission — and admitting the app works
without it. "Not now" persists to Prefs and is never asked again.

Fenced by `shouldOfferAccessibility(granted:dismissed:hasProject:
zeroStateShowing:)`: never when granted, never after a decline, never
before a project exists (nothing to detect for), never stacked on a zero
state that is already asking for attention. One ask at a time.

GATE FAILURE ON THE WAY — recorded because it is data, not noise:
the first `smoke.sh "" 3` after this change came back "RESULT: 1 FAILURES".
Reruns (1x, 3x, 5x, 3x) all came back ALL PASS, so the failing scenario name
was never captured — the run had been piped through `tail -3`. Not
attributed, not dismissed.

What DID come out of it: the offer was rendering during scenario runs, which
is a real inconsistency — verification runs must never be steered by
onboarding UI, and the first-run project sheet already follows exactly that
rule (`!ScenarioMode.isActive`). The offer now follows it too. Whether that
was the flake's cause is unproven; the fix is right on its own terms.

Lesson for the loop: never pipe a gate run through `tail`. The failing line
is the whole point of running it.

VERIFY met: AccessibilityOfferTests, 6 tests, every branch plus persistence.
Gate 132/132 + smoke ALL PASS (5 + 3 iterations after the fix) +
accessibility audit passes.

## 2026-08-20 ~18:01 — [ux] Zero state — KEPT
Cancel the first-run sheet and the app was a 0:00 ring, a red pill and no
explanation; the meaning of red lived in the README. The timer now answers
the question itself. Pure `AppModel.zeroState(hasProject:trackedSeconds:
isRecording:resolveRunning:)` -> nil | .noProject | .nothingTrackedYet, with
the card replacing the pause button (a zero state has nothing to pause).

Two judgment calls worth recording:
- Scope. The goal as written listed "no Accessibility" as a third branch. It
  is NOT implemented here: the next goal offers Accessibility in context,
  and two surfaces asking for the same permission is worse than one. The
  goal was narrowed deliberately, not missed.
- Honesty of the hint. `.nothingTrackedYet` reads differently depending on
  whether Resolve is actually running — with Resolve closed it names the
  manual path (work in a workflow app) instead of promising detection that
  cannot happen. Locked by test.

The branch that matters most is the nil one: a project with recorded
history and a quiet afternoon is NOT an empty app, and must not be told it
is. Tested explicitly.

VERIFY met: ZeroStateTests, 6 tests, every branch including nil.
Gate 126/126 + smoke ALL PASS (3 iterations) + accessibility audit passes.
No new hardcoded colors/sizes — DT.card, DT.strokeSubtle, DT.rLg, DT.s*.
DESIGN GATE PARTIAL: blind 3-judge panel still not runnable in-session.

## 2026-08-20 ~18:05 — [ux] First-run money defaults — KEPT
The defaults question had three answers on one Mac: SettingsView defaulted
to CHF, NewProjectSheet hardcoded `rate = "85.00"` / `currency = .chf` as
@State, and AppModel.switchOrCreate read the prefs. Set your defaults in
Settings and the New Project form still said 85 CHF; auto-created projects
and hand-created ones disagreed.

Now one source: `AppModel.defaultCurrency` / `AppModel.defaultHourlyRate`.
All three call sites read them. The currency falls back to
`TimexCurrency.fromLocale()` rather than a hardcoded CHF, so a first-run
user in Berlin starts in EUR — but a written pref always outranks the
locale, and a locale Cutaway does not support (JPY, GBP) falls back to CHF
rather than inventing an unsupported currency.

Bonus catch: the rate default now runs through `clampedRate`, so a corrupt
or hand-edited pref cannot seed a negative or six-figure rate onto a new
project — the clamp existed but the default path bypassed it.

VERIFY met: MoneyDefaultsTests — locale mapping for all four supported
currencies, unsupported-locale fallback, pref-outranks-locale, unreadable
pref, clamping, and the regression itself (every creation path reads the
same accessors).
Gate 120/120 + smoke ALL PASS (3 iterations) + UI tests pass.

## 2026-08-20 ~17:56 — AUDIT iteration (bias: first-run experience) — 3 goals added
Backlog was empty but for the Resolve-blocked Tier-1 goal, so the run-dry
rule fired: generate goals rather than stop. Human asked for a first-run
bias, so the audit walked the cold-install path — launch with no projects,
no prefs, Resolve absent — instead of reading the app as a returning user.

What that path actually is today: the window opens, and the FIRST thing a
new user sees is a modal form asking for a project name, a client, a billing
mode, an hourly rate and a currency. No welcome, no statement of what the
app does, no mention that it will detect Resolve projects by itself. The
README promises "first invoice in two minutes"; the app explains nothing.

Real defect found while reading, not theorised: NewProjectSheet hardcodes
`rate = "85.00"` and `currency = .chf` as @State, ignoring the
`defaultHourlyRate` / `defaultCurrency` prefs that SettingsView writes and
that AppModel.switchOrCreate already reads. So a user who sets their
defaults still gets 85 CHF on the form, and auto-created projects disagree
with hand-created ones on the same Mac.

Three goals appended, each with a VERIFY that is a unit test rather than a
judgment call. No code changed this iteration — an audit iteration commits
goals, nothing else.

## 2026-08-20 ~17:44 — [hardening] Idle-during-render exemption — KEPT
An export runs for 20 minutes, the editor watches it, touches nothing, and
the timer pauses at the idle threshold. That is real work going unbilled —
but the fix is the ONE rule in this app that resolves ambiguity toward
billing MORE, so it is fenced on every side:
- OFF by default. Opt-in toggle in Settings → TRACKING.
- Evidence required. Not "Resolve is open" — sustained cpu on an anchor
  process, sampled from proc_pid_rusage. Threshold 50% of one core, a named
  constant because machines differ and this is the knob to turn.
- Capped at 30 minutes per idle stretch. An unattended overnight render is
  not a working day. Input returning re-arms a fresh cap.
- Outranked by everything hard. It suppresses `.inputIdle` and nothing else,
  so manual pause, sleep, no-project and leaving the work context all still
  win — proven by test, not by reading.

Probe returns CUMULATIVE nanoseconds, not a percentage, so SystemProbing
stays stateless and the engine owns the two samples a rate needs. A default
implementation returning 0 means every existing fake probe compiles
untouched — the diff never reached the other engine tests.

One test failure on the way, worth recording: the accrual test jumped the
clock 10s and got 5s, because the engine deliberately caps a single tick's
delta at 5s against RunLoop stalls. The ENGINE was right and the new test
was wrong; fixed the test to tick at 1 Hz like the real timer. (No existing
assertion was touched — the verifier stays sacred.)

VERIFY met: RenderExemptionTests, 7 engine tests.
Gate 113/113 + smoke ALL PASS (3 iterations) + accessibility audit passes.

## 2026-08-20 ~17:29 — [polish] Session detail view — KEPT
A Daily Breakdown row is a claim ("4.6 h, CHF 391"). Until now there was no
way to see what it was made of, which is exactly the question a client
asks. Day rows are now disclosure buttons: tapping one unfolds the sessions
behind it — time range, hours, earnings — sourced from the same store rows
the CSV exports. One day open at a time; the breakdown is a ledger, not an
outline.

Honesty detail: today's row includes the live accumulator, which has no
WorkSession yet. Unfolded, the persisted parts would visibly fail to sum to
the total above them. The running span is therefore itemised too, marked
"running" in DT.orange with its live duration — the parts always reconcile
with the claim.

Chose in-place disclosure over a detail sheet: no new window, no navigation
state, no new surface to keep in sync with the ledger it describes.

VERIFY met: SessionDetailTests builds a sqlite fixture and asserts the
itemisation against it — day isolation, worked order, sum-equals-day-total,
midnight-split halves landing under the day each ran in, empty days, and
the rendered line matching the stored session.
Gate 106/106 + smoke ALL PASS (3 iterations) + accessibility audit passes.

## 2026-08-20 ~16:31 — [design] Stats hierarchy pass — KEPT
Three identically-weighted cards stacked in a column: same size, same
padding, same type. Nothing led, so the eye had to read all three to find
the number the user actually came for. Restructured to one lead + two
supports: the money figure (EARNED at DT.heroSec, or the budget card whose
bar already carries the weight) leads, PROJECT TOTAL and AVG PER DAY drop
to a half-width pair below at DT.statValue. Horizontal lead over a stacked
pair also breaks the uniform-rhythm problem.

Side effect worth naming: budget projects never showed AVG PER DAY at all
— the pair is mode-independent, so they get it now.

Simplification (autoresearch simplicity criterion): the card chrome was
duplicated per row and had already drifted; it is now one `statCard()`
extension defined once. Net +48/-18 lines for a structural change that
also deletes a duplication.

Gate 101/101 + smoke ALL PASS (3 iterations) + accessibility audit passes.
No new hardcoded colors/sizes — verified by diffing for literal font sizes
and paddings in the added lines.
DESIGN GATE PARTIAL: blind 3-judge panel still not runnable in-session.

## 2026-08-20 ~16:25 — [design] Last-banked line in the menu-bar panel — KEPT
Top-most Later goal. The 4s banked flash is a peak-end moment that often
fires after the editor already walked away, leaving no answer to "did that
block get counted?". The panel now carries a persistent receipt row between
the project list and the footer: "Last session: 47 min · 14:32", sourced
from `SessionStore.lastSession(for:)` (max by `end`, so a midnight-split
session reports the half the user actually finished).

Honesty detail found while writing the verifier: a bare clock time reads as
today forever. Anything not on today's date now carries its date
("Last session: 47 min · Jul 17, 14:32"). Duration rounds to the nearest
minute with a floor of 1 min — the line never claims a 0 min session.
Locale-aware `.dateTime` formatting (UI surface, not the POSIX-pinned
billing/CSV path). No new hardcoded colors or sizes — DT.captionMedium,
DT.text3, DT.strokeSubtle, DT.rowInset, DT.s2.

VERIFY met: 5 new tests (LastSessionReceiptTests) assert the line against
what the store actually holds, including newest-END-wins and the empty-
project case. Gate 101/101 + smoke ALL PASS (3 iterations) + accessibility
audit UI test passes.
DESIGN GATE PARTIAL: the blind 3-judge panel could not be run this
iteration (no judges available in-session). Functional gate and the
no-hardcoded-tokens rule are met; the judge panel is outstanding and the
goal stays reversible if it fails one later.

## 2026-07-19 ~04:35 — [ux] Stupid-proof sweep — KEPT (after a real gate failure)
Shipped: forgotten-pause hint (pill shows amber "still paused" after 15 min
of manual pause, engine-tested with virtual clock), ephemeral-store banner
(in-memory fallback now WARNS instead of silently losing data), rate
clamping (0..99'999, typo-proof, tested), duplicate-project-name guard in
the New Project sheet (case/diacritic-insensitive, tested).

GATE FAILURE + POSTMORTEM (the loop working as designed):
smoke went 24 FAILURES while unit tests stayed green. Bisect: committed
HEAD also failed -> environmental, not the diff. Chain: repo lives in
~/Downloads (TCC-protected); the GUI-launched app lost Downloads read
permission when its code signature changed (ad-hoc signing + reinstall);
scenario script unreadable; driver bail-out called NSApp.terminate during
App.init where NSApp is nil -> SIGTRAP. Proof: same scenario from /tmp
passed. Fixes: smoke stages scripts into the per-run temp dir (works on
any Mac now), driver bail-out uses exit(1). Assertions untouched.
Gate 96/96 + smoke ALL PASS.

## 2026-07-19 ~04:05 — [ux] User-reported lifecycle bugs — KEPT
Three real-use bugs from the user, all reproduced in code and fixed:
1. Settings never opened — panel called showSettingsWindow:, REMOVED in
   macOS 14 (silent no-op). Settings scene replaced with a real Window
   opened via closure from every entry point; Cmd-comma rebound.
   PROVEN: harness launch shows "Cutaway Settings" window (id 22941).
2. Red X terminated the app — SwiftUI default for non-MenuBarExtra apps.
   applicationShouldTerminateAfterLastWindowClosed -> false, locked in as
   AppLifecycleTests. Closing last window also drops the Dock icon
   (accessory policy); reopening from pill/panel restores it.
3. No way back to Timer — the panel hero is now a click target opening
   the main window on the Timer tab; Dock-icon reopen handled too.
Gate 93/93 + smoke ALL PASS. User declined the subagent audit fan-out —
scenario sweep continues inline as the next goal instead.

## 2026-07-19 ~03:55 — [design] Session-close peak-end flash — KEPT
Closing a session (the billing event) now flashes a quiet 4s "✓ 47 min
banked" in the pill (green text, no sound, micro-sessions < 1 min stay
silent), then reverts. Engine untouched — UI observers only. Blind panel
3/3 on "trust/feedback" (8-9 vs 4). All three judges independently found
the same follow-up: closes usually fire after the user walked away, so a
persistent "last banked" receipt belongs in the panel — added as a new
goal. Gate 92/92 + a11y + smoke ALL PASS.

## 2026-07-19 ~03:45 — [design] Pill state legibility — FAIL then KEPT
The check WORKED: 3/3 judges FAILED the original pill — green vs amber
(billing vs not) relied on hue alone, collapsing under deuteranopia.
Fix per consensus: shape-coded ring centers (record dot when recording,
pause bars when paused, empty ring for no-project). PillBody extracted as
pure view + render test producing the close-ups (locked in suite).
Re-judge: 3/3 PASS (7-8). Judges' residual notes (thicker ring at 1x,
bolder red glyph) logged as optional polish. Gate 90/90 + a11y + smoke.

## 2026-07-19 ~03:30 — [design] Pause button Fitts pass — KEPT
Primary control rebuilt as a real ButtonStyle: 44pt min target (Fitts),
lift-and-glow hover, compress on press, animated transitions — replacing
the 36pt brightness-only version. Blind panel 3/3 on "control affordance"
(8-9 vs 7). One judge notes the resting glow could read as hover — logged,
acceptable for the tally-light aesthetic. Gate 89/89 + a11y + smoke.

## 2026-07-19 ~03:15 — [design] Settings legibility — KEPT
Subtitles wrap instead of ellipsizing (fixedSize vertical); DT.text3/text2
alphas 0.50/0.55 -> 0.55/0.62 with hierarchy preserved. New ContrastTests
compute WCAG AA mathematically from raw DT tokens (composited over card and
window): all >= 4.5:1, locked against regression. Blind panel 3/3 on
"legibility" (9 vs 6). Gate 89/89 + a11y + smoke ALL PASS.

## 2026-07-19 ~04:00 — [ship] R-RELEASE — KEPT — v1.1.0 LIVE
Full sweep: 86 unit + UI tests green, smoke x5 ALL PASS. release.sh ran
verify -> Release build -> ad-hoc sign -> zip -> GitHub release v1.1.0 ->
cask bumped (version + sha256). Install command unchanged for users:
brew install --cask svanlink/tap/cutaway. Readiness 6/6.

## 2026-07-19 ~03:50 — [ship] R-DOCS — KEPT
README: 2-minute business quickstart, updated Gatekeeper guidance (ad-hoc
+ --no-quarantine), upgrade/uninstall commands, new "Your data" section
(location, automatic backups, restore steps), 3 new FAQ answers matching
this push's changes (nonstandard Resolve path, locale-pinned output).
Docs-only change; gate carried from previous iteration (86/86 + smoke).

## 2026-07-19 ~03:40 — [ship] R-LOCALE — KEPT
All formatters pinned to en_US_POSIX: currency (was separator-pinned only,
now digit/sign-proof too) and CSV date/weekday/time (was OS-calendar
dependent — a Thai-locale Mac would have exported Buddhist-era years).
3 exact-output tests across all 4 currencies. One test expectation was
wrong, not the app: formatWhole truncates (12'345.67 -> 12'345), kept as
correct under-billing behavior and documented. Gate 86/86 + smoke ALL PASS.

## 2026-07-19 ~03:30 — [ship] R-DEGRADE — KEPT
fuscript now found via LaunchServices (wherever Resolve is installed) with
stock-path fallbacks; injectable candidates make it testable. 2 tests:
missing fuscript -> nil (no crash), nonstandard path found. Smoke doubles
as the no-Resolve proof (whole app runs without Resolve present).
Gate 83/83 + smoke ALL PASS.

## 2026-07-19 ~03:20 — [ship] R-BACKUP — KEPT
StoreBackup: launch-time trio copy (store/-wal/-shm) before the container
opens, byte-compare skip, keep-7 rotation. 4 new tests (copy/skip/rotate/
no-op). Real double-launch proof: Backups/billing-20260719-025041 holds the
trio. One iteration hiccup: forgot xcodegen after adding the file — compile
fail, fixed by regenerate. Gate 81/81 + smoke ALL PASS.

## 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT
Ad-hoc codesign step added to release.sh (sign → verify → zip). Proof:
Release build signed (flags=0x2 adhoc), codesign --verify strict OK,
quarantined copy launches after documented xattr -cr. Caveat: this Mac has
Gatekeeper disabled (spctl override), so the warning dialog itself is
untestable here — stock-Mac path documented in cask caveats (right-click
Open / --no-quarantine). Tap updated + brew audit clean. Gate 77/77 + smoke.

## 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics
Researched karpathy/autoresearch + bilevel loop engineering. Adopted:
per-iteration budget, failure journaling (this file), bilevel re-plan rule
after 2 consecutive reverts, single readiness metric for the 06:00
production push. Backlog rewritten around the readiness checklist.

## 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6)
Blind panel 3/3 for grouped design (8 vs 4-5). Judges found real defects:
subtitle truncation + low contrast → new goal in Later. Gate green.

## 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4)
Settings editor popovers, live engine pickup, sanitizer. 77/77 + smoke.

## 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c)
One compile failure mid-iteration (missing SwiftData import) — fixed,
gate then green on first re-run. 75/75 + smoke.
