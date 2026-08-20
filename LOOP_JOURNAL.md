# Cutaway Loop Journal

Autoresearch-style state: what was tried, what happened, kept or reverted.
Newest entries at the top. Readiness score updates with each [ship] entry.

Readiness: 6/6 proven — PRODUCTION PUSH COMPLETE, v1.1.0 live (R-INSTALL, R-BACKUP, R-DEGRADE, R-LOCALE, R-DOCS, R-RELEASE)

---

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
