# Cutaway — Improvement Loop Backlog

Rules of the loop (Karpathy autoresearch style):
- ONE goal per iteration, top-most OPEN goal first. Per-iteration budget
  ~20 minutes; a goal that can't pass its gate inside the budget is
  reverted and journaled, not stretched.
- Every goal has a VERIFY line — done when that check passes, not "mostly".
- The verifier is sacred: `Tests/` and `scenarios/` may gain new checks but
  existing assertions may never be weakened to make a change pass.
  (Autoresearch rule: the evaluator lives outside the editable surface.)
- Gate for every iteration: 72+ unit tests green AND `./scripts/smoke.sh "" 3`
  ALL PASS. A change that fails the gate is reverted, not patched forward.
- JOURNAL every iteration in LOOP_JOURNAL.md: what was tried, result,
  kept or reverted, and why. Failures are data — record them so the loop
  resumes instead of restarts.
- Bilevel rule: after 2 consecutive reverted iterations, the next iteration
  must be a research/re-plan iteration (change the approach, not retry).
- Each completed goal: conventional commit, push. Move to Done with hash.

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

- [design] Last-banked line in the menu-bar panel — judges: the 4s banked
  flash often fires after the user walked away; the panel should show a
  persistent "Last session: 47 min · 14:32" line as the durable receipt.
  VERIFY: design gate "trust"; line matches last closed session in sqlite.
- [design] Stats hierarchy pass — VERIFY: design gate "hierarchy".
- [robustness] Live Tier-1 proof vs running Resolve — VERIFY: optional
  harness scenario R-tier1 passes when Resolve is up.
- [polish] Session detail view — VERIFY: UI matches sqlite fixture.
- [hardening] Idle-during-render exemption toggle — VERIFY: engine test.

Design gate — applies to every [design] goal, ON TOP of the functional gate:
- Accessibility audit UI test must pass.
- Blind judge panel: before/after screenshots shown unlabeled and
  order-shuffled to 3 independent judges; ≥2 must prefer the change on the
  goal's named dimension, or the change is reverted.
- No new hardcoded colors/sizes outside DesignTokens (DT).

## Done

(The loop moves completed goals here with the commit hash.)

- [stability] Project rename/delete UI with session reassignment — 210003c
- [stability] Editable workflow/satellite app lists (Settings editor, live pickup) — d01dcc4
- [design] Settings grouped sections, blind panel 3/3 on scannability — 96571c6
