# Cutaway — Improvement Loop Backlog

How this loop works: judgment, not rules.

There is a backlog below, roughly in priority order. Take the top thing that
can actually be done, do it well, run the tests and the smoke harness because
they are useful, write down what happened, commit. Nothing here is binding —
if a check is not worth running for a given change, do not run it; if a
change needs more care than the backlog entry suggests, give it more.

History lives in LOOP_JOURNAL.md and LOOP_RESULTS.tsv. Both are records, not
obligations.

## Production push — deadline 06:00 today

Objective: ready for real-world business use on OTHER Macs (no App Store,
no paid signing). Metric = readiness checklist items PROVEN, tracked in
LOOP_JOURNAL.md. Final iteration before 06:00: release v1.1.0 via
scripts/release.sh so `brew install svanlink/tap/cutaway` serves it.

Readiness checklist (each item needs proof, not belief):
- [x] R-INSTALL  Fresh-Mac install works: ad-hoc signed app, quarantined
      launch opens, cask caveats explain first launch.
- [x] R-BACKUP   Billing data survives disaster: automatic store backup
      rotation, proven by test.
- [x] R-DEGRADE  Works without Resolve / nonstandard Resolve path: manual
      projects fully usable, detector fails soft. Proven by test.
- [x] R-LOCALE   Currency/number/date formatting correct under en_US,
      de_DE, es_CO. Proven by test.
- [x] R-DOCS     README quickstart for a non-technical business user +
      troubleshooting (Gatekeeper, permissions, data location).
- [x] R-RELEASE  v1.1.0 tagged, cask bumped, `brew audit` clean.

## Open

## Later (post-deadline polish)

- [a11y] The pill tells VoiceOver the state and hides the number. Its
  accessibility label is "Recording" / "Paused" / "No project selected" — it
  never says the time, never says WHICH project, and never announces the
  banked-session confirmation or the forgotten-pause hint, both of which
  replace the visible readout. This is the app's primary always-visible
  surface, and the accessibility audit test only covers the main window, so
  nothing has ever checked it.
  VERIFY: a pure label function covering every state (no project, recording,
  paused, banked flash, long-pause hint) asserted by unit test — each label
  names the project and the figure a sighted user can see; and the audit UI
  test is extended to the status item.

- [design] The design gate cannot be enforced where it matters most. The
  rule is "no hardcoded colors/sizes outside DesignTokens", but there are 18
  font-size literals across the UI — 10 in the menu-bar panel, 3 in the pill
  itself — plus corner radii, ring widths and paddings that never became
  tokens. The gate is checked by eye, which means it is checked when someone
  remembers. Tokenise the remainder and make the rule mechanical.
  VERIFY: no `Font.system(size:` literal outside DesignTokens.swift, proven
  by a test that reads the UI sources and fails on any it finds; existing
  renders unchanged (PillRenderTests still produce three distinct states).

- [perf] A second 1 Hz timer runs for the life of the app to resize a pill
  whose width changes when a digit is added — a few times a day. It fires
  while paused, while no project is selected, and while the app sits in the
  background with a static number, on a machine the user is editing video
  on. The engine already ticks once a second and the pill already re-renders
  from it; the width sync can ride that instead of owning a timer.
  VERIFY: unit test — the controller schedules no timer of its own; width
  still syncs when the digit count changes (proven through the sync entry
  point, not by sleeping).

- [robustness] Live Tier-1 proof vs running Resolve — VERIFY: optional
  harness scenario R-tier1 passes when Resolve is up.

## Done

- [perf] Backup decided from size+mtime, contents only as fallback — cf0311c

- [data] Log quarantined from verification runs and bounded at ~4 MB — e1961a7

- [data] Backup skip-check reads the whole store, WAL included — 43e981c

- [ux] Recording says why — the research window is visible and counts down — d92f92a

- [hardening] Every engine time read goes through the injectable clock — 0ddb8c2

- [billing] Manual pause survives a relaunch — 60a3bf4

- [perf] Today's totals memoised — rendering no longer re-walks history — 9630250

- [logic] Stale Tier-1 answers cannot overrule a newer manual choice — 8ecab2f

- [logic] Auto-switch follows transitions in Resolve, not steady state — 7ef3870

- [billing] Invoice arithmetic — round once, then sum — 299c119

- [billing] Invoice period export — presets, filtered in the exporter — 557f59c

- [billing] Rate history — work bills at the rate it was worked at — 3a9d1c2

- [ux] Accessibility offered once, in context, with a real decline — 2234290

- [ux] Zero state — the timer says why it is not counting — 0b947a4

- [ux] First-run money defaults — one source, locale-seeded — b257e77

- [hardening] Idle-during-render exemption — opt-in, cpu-evidenced, 30 min cap — 9205c5f

- [polish] Session detail — day rows unfold into their sessions — ec0493e

- [design] Stats hierarchy pass — one money lead + two support stats — 75dbf4d

- [design] Last-banked receipt line in the menu-bar panel (functional gate met; blind judge panel outstanding) — 4adfe94

(The loop moves completed goals here with the commit hash.)

- [stability] Project rename/delete UI with session reassignment — 210003c
- [stability] Editable workflow/satellite app lists (Settings editor, live pickup) — d01dcc4
- [design] Settings grouped sections, blind panel 3/3 on scannability — 96571c6
