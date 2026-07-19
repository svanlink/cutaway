# Cutaway — Improvement Loop Backlog

Rules of the loop (Karpathy-style):
- ONE goal per iteration, top-most OPEN goal first.
- Every goal has a VERIFY line — the goal is done when that check passes,
  not before, not "mostly".
- The verifier is sacred: `Tests/` and `scenarios/` may gain new checks but
  existing assertions may never be weakened to make a change pass.
- Gate for every iteration: 72+ unit tests green AND `./scripts/smoke.sh "" 3`
  ALL PASS. A change that fails the gate is reverted, not patched forward.
- Each completed goal: conventional commit, push. Releases stay manual
  (`scripts/release.sh`) — the loop never publishes.
- When the backlog is empty: run a research iteration (audit the app, study
  comparable tools, mine the FAQ/issues) and APPEND new goals instead of
  inventing code changes.

Design gate — applies to every [design] goal, ON TOP of the functional gate:
- Accessibility audit UI test must pass.
- Blind judge panel: before/after screenshots shown unlabeled and
  order-shuffled to 3 independent judges; ≥2 must prefer the change on the
  goal's named dimension, or the change is reverted.
- No new hardcoded colors/sizes outside DesignTokens (DT).

## Open

1. [robustness] Live Tier-1 proof — scripted check that fuscript detection
   works against a running Resolve (skips cleanly when Resolve absent).
   VERIFY: new optional harness scenario R-tier1 passes when Resolve is up.
2. [design] Pause button Fitts pass — primary control target ≥44pt tall,
   designed hover/pressed states (not just brightness).
   VERIFY: design gate on "control affordance"; a11y audit.
3. [polish] Session detail view — clicking a day row shows its sessions
   (start/end/duration) read-only. Foundation for future editing.
   VERIFY: UI renders sessions matching sqlite for the demo fixture.
4. [design] Menu-bar pill pre-attentive check — traffic-light border must
   read in a glance in all three states at menu-bar size.
   VERIFY: design gate on "state legibility" using pill close-ups.
5. [hardening] Idle-during-render product question — add per-app idle
   exemption toggle ("count renders") for anchor apps, default OFF.
   VERIFY: engine test: idle in exempted app keeps recording.
6. [design] Session-close peak-end moment — a session closing (the billing
   moment) deserves a quiet visible confirmation, not silence.
   VERIFY: design gate on "trust/feedback"; engine behavior unchanged.
7. [quality] Localize number/date formatting audit for non-CH locales.
   VERIFY: formatter tests pass under en_US, de_DE, es_CO locales.
8. [design] Stats hierarchy pass — daily breakdown scale contrast; the money
   column should lead, the bars support.
   VERIFY: design gate on "hierarchy".

9. [design] Settings subtitle truncation + contrast — judges flagged
   ellipsized descriptions ("research wi…") and low-contrast gray secondary
   text. Wrap or shorten subtitles; lift DT.text3 contrast toward WCAG AA.
   VERIFY: no truncated subtitle at default window size; contrast ratio of
   secondary text computed >= 4.5:1; design gate on "legibility".

## Done

(The loop moves completed goals here with the commit hash.)

- [stability] Project rename/delete UI with session reassignment — 210003c
- [stability] Editable workflow/satellite app lists (Settings editor, live pickup) — d01dcc4
- [design] Settings grouped sections, blind panel 3/3 on scannability — 96571c6
