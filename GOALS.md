# Cutaway — Improvement Loop Backlog

Rules of the loop (Karpathy autoresearch style):
- ONE goal per iteration, top-most OPEN goal first. Per-iteration budget
  ~20 minutes; a goal that can't pass its gate inside the budget is
  reverted and journaled, not stretched.
- Every goal has a VERIFY line — done when that check passes, not "mostly".
- The verifier is sacred: `Tests/` and `scenarios/` may gain new checks but
  existing assertions may never be weakened to make a change pass.
  (Autoresearch rule: the evaluator lives outside the editable surface.)
- Gate for every iteration: ALL unit tests green (101 and rising) AND `./scripts/smoke.sh "" 3`
  ALL PASS. A change that fails the gate is reverted, not patched forward.
- JOURNAL every iteration in LOOP_JOURNAL.md: what was tried, result,
  kept or reverted, and why. Failures are data — record them so the loop
  resumes instead of restarts.
- Bilevel rule: after 2 consecutive reverted iterations, the next iteration
  must be a research/re-plan iteration (change the approach, not retry).
- Each completed goal: conventional commit. Move to Done with hash.

Adopted verbatim from karpathy/autoresearch `program.md` (the loop this one
is modelled on), because they were the parts we were only half-doing:
- ADVANCE OR RESET. The gate is the metric. Gate green -> keep the commit and
  advance the branch. Gate red -> `git reset` back to where the iteration
  started. Never patch a red gate forward, never weaken it to go green.
- LEDGER. Every iteration gets a row in `LOOP_RESULTS.tsv` (tab-separated,
  untracked by design): commit, gate, test count, status keep/discard/crash,
  description. The prose journal explains; the ledger is greppable state.
- SIMPLICITY CRITERION. All else equal, simpler wins. A small improvement
  that adds ugly complexity is not worth it. An improvement that DELETES
  code is the best outcome there is. Equal result with less code: keep.
- NEVER STOP. Once the loop is running, do not pause to ask whether to
  continue or which goal is next — the backlog is ordered, take the top one.
  The human may be asleep. They interrupt the loop; the loop doesn't
  interrupt them. (Outward-facing acts — pushing, releasing — stay off the
  autonomous path and wait for a human word.)
- The run lives on `autoresearch/<tag>`, never directly on main.
- NEVER RUN DRY. autoresearch never runs out of ideas because its metric is
  continuous; this loop's gate is binary, so the backlog is the fuel. When
  "Later" is empty the next iteration is an AUDIT iteration: read the app
  with fresh eyes and append 3 new goals, each with a concrete VERIFY line.
  An empty backlog is a goal-generation task, never a reason to stop.
- Unattended runs: `./scripts/loop.sh` drives one `claude -p` iteration at a
  time against `scripts/loop-prompt.md`. `touch STOP` ends it after the
  current iteration.

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

- [ux] The zero state says nothing. Cancel the first-run sheet and the timer
  is a 0:00 ring, a red pill, and no explanation — the meaning of red lives
  in the README, not the app. Give it a real zero state: name what Cutaway
  is waiting for (no project / Resolve not running / no Accessibility) and
  offer one primary action out of it.
  VERIFY: AppModel exposes a pure `zeroState` reason; unit test covers every
  branch including the nil "nothing is wrong" case; design gate for the view.

- [ux] Accessibility is never explained at the moment it matters. It is the
  difference between instant project switching and a 30–120s scripting poll,
  and a first-run user only ever meets it buried in Settings. Offer it once,
  in context, after the first project exists — and never again once
  dismissed.
  VERIFY: pure `shouldOfferAccessibility(granted:dismissed:hasProject:)`;
  unit test proves it fires exactly once, never when already granted, never
  after dismissal, never before a project exists.

- [robustness] Live Tier-1 proof vs running Resolve — VERIFY: optional
  harness scenario R-tier1 passes when Resolve is up.

Design gate — applies to every [design] goal, ON TOP of the functional gate:
- Accessibility audit UI test must pass.
- Blind judge panel: before/after screenshots shown unlabeled and
  order-shuffled to 3 independent judges; ≥2 must prefer the change on the
  goal's named dimension, or the change is reverted.
- No new hardcoded colors/sizes outside DesignTokens (DT).

## Done

- [ux] First-run money defaults — one source, locale-seeded — b257e77

- [hardening] Idle-during-render exemption — opt-in, cpu-evidenced, 30 min cap — 9205c5f

- [polish] Session detail — day rows unfold into their sessions — ec0493e

- [design] Stats hierarchy pass — one money lead + two support stats — 75dbf4d

- [design] Last-banked receipt line in the menu-bar panel (functional gate met; blind judge panel outstanding) — 4adfe94

(The loop moves completed goals here with the commit hash.)

- [stability] Project rename/delete UI with session reassignment — 210003c
- [stability] Editable workflow/satellite app lists (Settings editor, live pickup) — d01dcc4
- [design] Settings grouped sections, blind panel 3/3 on scannability — 96571c6
