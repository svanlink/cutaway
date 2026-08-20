#!/bin/bash
# Cutaway — unattended autoresearch driver.
#
# One `claude -p` invocation per iteration. Every iteration cold-starts and
# rebuilds its context from git + GOALS.md + LOOP_JOURNAL.md +
# LOOP_RESULTS.tsv, which is exactly why this can run all night without a
# conversation to remember.
#
#   ./scripts/loop.sh          run until stopped
#   touch STOP                 stop after the current iteration finishes
#   tail -f loop.log           watch it work
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
rm -f STOP
N=0
while [ ! -f STOP ]; do
  N=$((N + 1))
  echo "── iteration $N  $(date '+%Y-%m-%d %H:%M:%S')" | tee -a loop.log
  # caffeinate -i: an unattended loop is worthless if the Mac sleeps midway.
  caffeinate -i claude -p "$(cat scripts/loop-prompt.md)" >>loop.log 2>&1 ||
    echo "  iteration $N exited nonzero — see loop.log" | tee -a loop.log
  sleep 5
done
echo "── STOP after $N iterations  $(date '+%H:%M:%S')" | tee -a loop.log
