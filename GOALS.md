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

## Open

1. [stability] Editable workflow/satellite app lists — `workApps` and
   `satelliteApps` keys are read-only today; Settings shows static text.
   Add add/remove UI writing those keys; engine picks changes up live.
   VERIFY: defaults round-trip test; engine honors an added bundle id in
   a new engine test.
2. [robustness] Live Tier-1 proof — scripted check that fuscript detection
   works against a running Resolve (skips cleanly when Resolve absent).
   VERIFY: new optional harness scenario R-tier1 passes when Resolve is up.
3. [polish] Session detail view — clicking a day row shows its sessions
   (start/end/duration) read-only. Foundation for future editing.
   VERIFY: UI renders sessions matching sqlite for the demo fixture.
4. [hardening] Idle-during-render product question — add per-app idle
   exemption toggle ("count renders") for anchor apps, default OFF.
   VERIFY: engine test: idle in exempted app keeps recording.
5. [quality] Localize number/date formatting audit for non-CH locales.
   VERIFY: formatter tests pass under en_US, de_DE, es_CO locales.

## Done

(The loop moves completed goals here with the commit hash.)

- [stability] Project rename/delete UI with session reassignment — 210003c
