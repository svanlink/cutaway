Do one round of improvement on this repo, then exit. You are unattended —
the human is asleep. Do not ask questions, do not wait for confirmation.

State lives in git, GOALS.md, LOOP_JOURNAL.md and LOOP_RESULTS.tsv. Read
them first; that is the whole memory of the run.

Take the top thing in GOALS.md's "Later" list that can actually be done —
skip anything whose check cannot run in this environment (needs DaVinci
Resolve running, needs a human to look at something) and leave it in place.
If the list is empty, read the app with fresh eyes instead and append a few
new entries worth doing, each with a concrete way to tell it is finished.

Then do it, as well as you would if someone were watching. Prefer the
smallest change that actually solves the problem. Deleting code and keeping
everything working is the best possible outcome.

Run what is worth running — the unit tests, `./scripts/smoke.sh "" 3`, the
accessibility UI test for anything visual. If it comes back red, work out
why: if the change is wrong, drop it; if the change is right but made
something else fragile, fix that properly rather than papering over it.
Never edit a test so a change can pass — if a test's expectation genuinely
has to change because behaviour changed on purpose, say so plainly in the
journal.

Write down what happened in LOOP_JOURNAL.md — what was tried, what came of
it, what you decided and why. Add a row to LOOP_RESULTS.tsv. Commit.

Do not push, tag, or release, and do not move or delete anything outside
this repository. Those wait for the human.

Then exit. The driver script starts the next round.
