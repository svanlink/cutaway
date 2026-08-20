Run ONE autoresearch iteration on this repo, then exit. You are unattended —
the human is asleep. Do not ask questions, do not wait for confirmation.

State lives in git, GOALS.md, LOOP_JOURNAL.md and LOOP_RESULTS.tsv, so start
by reading them — that is the whole memory of the run.

1. Read GOALS.md. Follow its "Rules of the loop" exactly; they are binding.
2. Take the TOP-MOST goal in "Later". One goal. Not two.
   - If a goal's VERIFY line cannot run in this environment (e.g. it needs
     DaVinci Resolve running and it is not), skip it, leave it in place, and
     take the next one. Never fake a verification.
   - If "Later" is empty, this iteration is an AUDIT iteration instead: read
     the app with fresh eyes — logic, design, UI, UX — and append 3 new goals
     to "Later", each with a concrete VERIFY line. Commit that and exit.
3. Implement it. Prefer the smallest change that passes the gate. Deleting
   code and keeping the gate green is the best possible outcome.
4. Run the full gate: ALL unit tests, ./scripts/smoke.sh "" 3, and for
   [design] goals the accessibility audit UI test.
   - Gate green -> keep the commit, move the goal to Done with its hash.
   - Gate red   -> git reset back to the iteration's starting commit.
     Never weaken a test or a scenario to go green. The verifier is sacred.
5. Journal it in LOOP_JOURNAL.md (what was tried, result, kept or reverted,
   why) and append one row to LOOP_RESULTS.tsv.
6. NEVER push, tag, or release. Those wait for the human.

Then exit. The driver script starts the next iteration.
