# Cutaway Loop Journal

Autoresearch-style state: what was tried, what happened, kept or reverted.
Newest entries at the top. Readiness score updates with each [ship] entry.

Readiness: 6/6 proven — PRODUCTION PUSH COMPLETE, v1.1.0 live (R-INSTALL, R-BACKUP, R-DEGRADE, R-LOCALE, R-DOCS, R-RELEASE)

---

## 2026-08-20 ~19:36 — [ux] Recording says why — KEPT
`.recording` was opaque: identical whether Resolve was frontmost or a
browser was holding the clock up inside the research window. That window
expires silently, so an editor researching in Chrome found out only by
noticing the timer had stopped some time ago. The app is scrupulous about
not over-billing; it should be equally clear about when it is about to stop
counting.

`RecordingSource` (.anchor / .satellite(secondsLeft:)) is computed purely
and exposed by the engine. The panel shows a line ONLY for the satellite
case — anchor recording stops when the work does and needs no explanation,
and a line the user cannot act on is noise. Under five minutes the row turns
amber: late enough not to nag, early enough to touch Resolve and keep the
block alive.

The countdown rounds DOWN, so it never promises time the window does not
still have — 1:59 reads "1 min left", and anything under a minute says so
rather than showing "0 min".

Design gate caught something real: the new hourglass used a hardcoded
`size: 9`, which the gate forbids. Rather than tokenising just the new one,
took the pattern — the receipt's checkmark had the same literal inline — and
both now use `DT.glyph`. Fix the class, not the instance.

VERIFY met: RecordingSourceTests, 8 tests — anchor vs satellite, seconds
left, rounding down, no label for anchor, no source when paused (all four
reasons), no window without anchor history, clamping at zero rather than
going negative, and an unknown app being neither.
Gate 189/189 + smoke ALL PASS (3 iterations, s5-satellite included) +
accessibility audit passes. No hardcoded values outside DT.
DESIGN GATE PARTIAL: blind 3-judge panel still not runnable in-session.

This closes the detection-engine audit — all three findings fixed.

## 2026-08-20 ~19:24 — [hardening] The engine has one clock — KEPT
`closeSessionIfOpen` called `endSession()` with its default `Date()`, so the
moment that decides a session's END — and through DaySplitter, which DAY the
work bills to — was the one place in the engine that ignored `now()`.

Grepping for the symptom found three more of the same leak rather than one:
the crash-recovery snapshot stamped `updatedAt` from the wall clock (that
stamp becomes a recovered session's END after a crash), the checkpoint timer
compared against a wall-clock reading, and `lastCheckpoint` was SEEDED with
`Date()` at construction — a wall-clock reading smuggled past the injectable
clock before the engine had even started. All four now read `now()`;
`lastCheckpoint` is optional instead of seeded, because there is no honest
value for "when did the last checkpoint happen" before one has.

The snapshot also moved from the global `Prefs` to the injected `defaults`,
finishing what the previous iteration started.

Latent, not live: in production the two clocks agree, so no user has been
billed a wrong day by this. It was worth fixing because it is the class of
bug that surfaces once, in someone's real data, in a way the tests
structurally could not reproduce — the test could not reach the code path
that read the wall clock.

Three test failures on the way, all mine: a "sanity" assertion asserting the
virtual clock was in the PAST when 1_800_000_000 is 2027 (now asserts
distance in either direction, so it cannot rot as the wall clock moves); a
day-boundary reference off by one day; and a checkpoint expectation tighter
than the 15s checkpoint interval it was measuring.

VERIFY met: EngineClockTests — a closed session ends on the engine's clock
and nowhere near the wall clock, a session crossing a virtual midnight
splits with every second conserved, the crash snapshot sits on the virtual
timeline, and checkpointing does not depend on construction time.
Gate 181/181 + smoke ALL PASS (3 iterations, s7-midnight included).

## 2026-08-20 ~19:12 — [billing] Manual pause survives a relaunch — KEPT
`manuallyPaused` was a plain var. Quit while paused — or crash, or restart
overnight — and the app came back recording, accruing time the user believed
was stopped, with nothing on screen to say the pause had been lifted. The
one boundary the app calls sacred, un-setting itself in the billing
direction. Now persisted, with `manualPauseStart` alongside it so a restored
pause reports its REAL age: pause on Friday, launch on Monday, and the
forgotten-pause hint fires immediately instead of restarting its 15-minute
clock as though the pause were new.

GATE FAILURE ON THE WAY — 5 red in DetectionEngineTests, and the cause was
the change itself, not the tests. Persisting pause made the engine read
global mutable state AT CONSTRUCTION, so every engine any test built now
inherited whatever another test had last written. Ordering-dependent,
therefore intermittent, therefore exactly the class of flake that wastes an
unattended night.

The fix was the design, not the symptom: `defaults` is injected
(`init(probes:logger:defaults:)`, defaulting to Prefs), and the engine tests
each get their own scratch suite. A store shared by every engine ever built
is as testable as a global variable. `git diff | grep XCTAssert` across the
touched test files returns nothing — the isolation changed how those tests
get a store, never what they assert.

Worth naming: had I persisted via a bare `Prefs` read and the suite happened
to be clean, this would have gone green and shipped a test suite whose
results depended on execution order. The failure was the useful outcome.

VERIFY met: PausePersistenceTests — a pause survives relaunch, not one
second accrues across it, resuming clears the persisted state, a
never-paused install is unaffected, a restored pause reports its real age
and trips the long-pause hint, and a start without a pause is not restored.
Gate 177/177 + smoke ALL PASS (3 iterations) + UI tests pass.

## 2026-08-20 ~18:58 — AUDIT iteration (detection engine — the billing logic)
No bias was sent this tick, so took the area flagged as least-audited and
highest-stakes: the engine's own rules, where the money is actually decided.
Read evaluate(), tick(), the accumulator and the bridge/satellite handling
line by line.

1. MANUAL PAUSE DOES NOT SURVIVE RELAUNCH. `manuallyPaused` is a plain var.
   Quit while paused, or crash, or restart overnight, and the app comes back
   recording. The app calls this boundary sacred — and it is, within a
   single run. Across runs it silently lifts, in the billing direction, and
   invisibly, because a relaunched app looks exactly like one that was never
   paused. Of everything found in three audits, this is the one that most
   directly contradicts a promise the app makes about itself.

2. THE ACCUMULATOR ENDS SESSIONS ON THE WALL CLOCK. `closeSessionIfOpen`
   calls `endSession()` with its default `Date()`, so the single moment that
   decides a session's end — and via DaySplitter, which DAY it bills to — is
   the one place in the engine that ignores the injectable `now()`. Latent
   in production (the clocks agree), but it is precisely the kind of latent
   that shows up as a wrong day boundary the tests structurally cannot
   reproduce.

3. RECORDING IS OPAQUE. `.recording` looks the same whether Resolve is
   frontmost or a browser is sustaining the clock inside the research
   window. An editor researching in Chrome cannot see that they are inside a
   20-minute window, and when it expires, tracking stops with no perceptible
   event. The app is scrupulous about not over-billing; it should be equally
   clear about when it is about to stop counting.

Checked and found CORRECT (recorded so a later audit skips it): sleep during
a bridge gap closes and clears the gap; the accumulator credits the
post-transition state, so a transition tick under-bills by at most a second
rather than over-billing; `pausedLong` resets on unpause; bridge credit is
refused once a session has ended, so a project switch mid-gap cannot move
another project's time; the 20-entry `closedSessions` cap is diagnostics
only and cannot affect persistence.

No code changed this iteration.

## 2026-08-20 ~18:57 — [perf] Today's totals memoised — KEPT
The menu-bar panel renders a row per project on every tick and each row
asked the store for that project's total today, which filtered that
project's ENTIRE session history to answer. Ten projects with a couple of
years of work is tens of thousands of comparisons a second, forever — a cost
that grows with exactly the thing the app is for.

Memoised per project, with the DAY as part of the key so midnight
invalidates itself rather than needing a timer to notice. Invalidation is
wholesale on record and delete: writes are rare, renders are not, and a
too-clever per-project invalidation is how a billing figure goes quietly
stale on screen. That is the trade this cache is willing to make and the one
it is not.

`sessionScanCount` is production diagnostics, not test scaffolding hidden in
the app — it is the only way to assert the actual claim ("rendering does not
re-walk history") rather than a proxy for it. A timing assertion would have
been flaky on a loaded machine and would not have proven the mechanism.

VERIFY met: TodayCacheTests — 10 projects x 60 days rendered twice costs
exactly 10 scans; the memoised answer equals the computed one; recording
work shows up immediately; midnight invalidates itself; deleting with
reassignment shows the heir's new total; and one project's total is never
served for another.
Gate 171/171 + smoke ALL PASS (3 iterations) + UI tests pass.

This closes the multi-project audit — all three findings fixed.

## 2026-08-20 ~18:52 — [logic] Stale Tier-1 race — KEPT (closes what the last
iteration only narrowed)
`detectViaScriptingAPI` spawns fuscript and answers seconds later, and the
result was applied with no check that it was still relevant. Pick a project
by hand while one is in flight and the old answer landed on top. Same
automation-beats-intent defect as the steady-state bug, but intermittent —
which is worse, because it reads as the app randomly changing your project
rather than as a rule you can learn.

`ManualIntent` counts explicit choices. A Tier-1 request stamps the count
BEFORE it starts; if the count has moved when it answers, the user chose in
the meantime and the answer is dropped — before the DetectionFollower ever
sees it. That ordering is the point: a stale answer naming a DIFFERENT
project looks exactly like a legitimate transition, so the follower cannot
be the thing that catches it. Locked by a test that asserts the follower's
`lastSeen` is untouched, with a sanity assertion proving the same name WOULD
have read as a transition had it got that far.

`select` now has an explicit-intent sibling, `selectManually`, used by the
three UI switch points; `createProject` takes `isManual` because
auto-creation routes through it too. Automation keeps calling the plain
paths, so the counter means exactly what its name says.

Dropping the answer does not lose a real change: if Resolve genuinely moved
while the user was choosing, the next poll reports the new name and the
follower treats it as the transition it is. Ignoring one round is the
correct cost.

VERIFY met: ManualIntentTests — an uninterrupted detection still applies, a
choice during the request invalidates it, choices made BEFORE the request
started do not, concurrent requests judge themselves against their own
start, and the different-project stale answer never reaches the follower.
Gate 165/165 + smoke ALL PASS (3 iterations) + UI tests pass.

## 2026-08-20 ~18:47 — [logic] Auto-switch follows transitions — KEPT
`switchOrCreate` selected whenever the detected name differed from the
selected project, and Tier 2 polls every 5s — so the app re-asserted
Resolve's steady state twelve times a minute and a manual switch survived at
most five seconds. An editor doing project B's work in After Effects, with A
open in Resolve, billed all of it to A. The app calls manual pause sacred
because explicit intent outranks automation; this was the same principle
being broken on a timer.

The fix is conceptual rather than defensive: a `DetectionFollower` turns
Resolve's steady state into transitions, and only a CHANGE moves
attribution. The first sighting is always a transition, which is how a fresh
install still adopts whatever is already open (scenario s1 proves that path
is untouched). Case/whitespace/diacritic drift between tiers is explicitly
not a transition — otherwise Tier 1 and Tier 2 disagreeing about spelling
would look like the user switching projects twice a minute.

Simplification on the way: `switchOrCreate` carried a private `normalized`
closure that duplicated the dedup rule. Both now use `ProjectName.matches`,
so the rule that decides "same project" exists once.

Deliberately NOT done here: the stale-Tier-1 race is the next goal. The
follower narrows it (a stale answer naming the same project is now ignored)
but does not close it — a stale answer naming a DIFFERENT project still
reads as a transition. Recorded so the next iteration does not assume it
inherited a fix it did not get.

VERIFY met: DetectionFollowerTests — first sighting adopts, 100 polls of the
same name never move attribution, a real change follows, tier spelling drift
is not a transition, blank readings cannot fake one, reset makes the next
sighting fresh.
Gate 159/159 + smoke ALL PASS (3 iterations, s1-zerostate-detect included).

## 2026-08-20 ~18:43 — AUDIT iteration (bias: multi-project switching) — 3 goals
Read the switching paths end to end — Tier 2 polling, the Tier 1 Task,
manual `select`, session close-and-reattribute — rather than reasoning about
them. Two of the three findings are the same defect wearing different
clothes: automation beating explicit intent.

1. AUTO-DETECTION OVERRIDES THE USER ON A TIMER. `switchOrCreate` selects
   whenever the detected name differs from the selected project, and Tier 2
   runs every 5s. A manual switch therefore cannot be held: pick B while
   Resolve has A open and you are back on A within five seconds, forever.
   Work done in After Effects for project B, with A open in Resolve, bills
   to A. The app states that explicit intent outranks automation (it is why
   manual pause is sacred) — here automation wins on a timer. The fix is
   conceptual, not a patch: auto-switch should follow TRANSITIONS in
   Resolve, not assert its steady state.

2. STALE TIER-1 RESULT WINS A RACE. The scripting-API call is a detached
   Task that spawns fuscript for seconds, and its result is applied with no
   relevance check. Switch by hand while one is in flight and the old answer
   lands on top. Same defect, but intermittent — which makes it worse, since
   it will read as "the app randomly changed my project".

3. SWITCHING COST SCALES WITH HISTORY. The panel renders a row per project
   every tick and each row filters that project's entire session history.
   Not a correctness bug, but it is the one part of the app whose cost grows
   with success, and it grows multiplicatively in the number of projects —
   which is exactly what this audit was asked to look at.

Checked and found FINE, worth recording so a later audit does not re-tread:
session attribution across a switch (the open span closes before the id
changes, so it stays with the old project); bridge gaps across a switch (the
credit guard refuses an ended session); duplicate creation across tiers
(normalised matching); delete-while-recording (closes, then reassigns).

No code changed this iteration.

## 2026-08-20 ~18:31 — [billing] Invoice arithmetic — KEPT (with a correction
to the audit that opened it)
Rows printed rounded to cents while totals printed the rounded sum of
UNROUNDED values, so a client adding up the rows could land a cent away from
the total. Fixed at the root: `round2` once, at the printed precision, and
every cumulative sums the rounded values. Applied to earnings AND hours —
same defect, same line of code, and an hours column that does not add up is
the same credibility problem. `budget_remaining` rounds through the same
helper so what is left agrees with what was earned.

CORRECTION TO THE AUDIT. The 12-day fixture cited as proof ("rows sum to
5572.71, total prints 5572.72") does NOT reproduce in this app. It was
derived in Python, which rounds half-to-even; Swift rounds half-away-from-
zero, and under those semantics that month adds up fine. The DEFECT CLASS
was real — round-then-sum vs sum-then-round genuinely diverges — but that
particular example was an artifact of the tool I checked it with. Re-found
two real cases under the app's own arithmetic (22 days at 157/h: 15651.25 vs
15651.24; and an hours case: 107.03 vs 107.02) and used those instead.

Three test failures on the way, all mine, none in the app:
1. A hardcoded budget expectation, Python-derived — same root cause.
2. `column()` counted summary lines as day rows and indexed off the end;
   `split` drops the blank line, so `prefix(while: !isEmpty)` never stopped.
   Now filters on an 18-field row.
3. Swift refused to type-check a chained `Double(try! XCTUnwrap(...))!`
   expression — broken into typed locals.

Rule added to GOALS: never let a fixture come from another tool's
arithmetic. Assert internal consistency; re-derive literals under the app's
own semantics.

VERIFY met: InvoiceArithmeticTests — the two genuine drift fixtures, a
300-iteration random sweep asserting rows always sum to the printed total
for both money and hours, the final cumulative row equalling the summary
total, and budget_remaining agreeing with total_earned.
Gate 152/152 + smoke ALL PASS (3 iterations) + accessibility audit passes.

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
