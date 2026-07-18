#!/bin/bash
# Cutaway — repeatable verification loop.
# Usage: scripts/smoke.sh [app-path] [iterations]
# Exit 0 = every scenario passed every iteration. Any flake = exit 1.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Timex-*/Build/Products/Debug/"Cutaway.app" 2>/dev/null | head -1)}"
ITER="${2:-1}"
SUITE="com.vaneickelen.cutaway.scenario"
FAILS=0

q() { sqlite3 "$1/timex.store" "$2" 2>/dev/null; }

# assert <label> <actual> <op> <expected> [tolerance]
assert() {
  local label="$1" actual="$2" op="$3" expected="$4" tol="${5:-0}"
  local ok=1
  case "$op" in
    "==") [ "$actual" = "$expected" ] && ok=0 ;;
    "~=") ok=$(awk -v a="$actual" -v e="$expected" -v t="$tol" 'BEGIN{print (a>=e-t && a<=e+t)?0:1}') ;;
  esac
  if [ "$ok" != "0" ]; then
    echo "    FAIL $label: got '$actual', wanted $op $expected ±$tol"
    return 1
  fi
  return 0
}

run_scenario() {
  local file="$1" data="$2"
  defaults delete "$SUITE" >/dev/null 2>&1
  launchctl setenv TIMEX_SCENARIO "$ROOT/scenarios/$file"
  launchctl setenv TIMEX_DATA_DIR "$data"
  open -W "$APP"
  local rc=$?
  launchctl unsetenv TIMEX_SCENARIO
  launchctl unsetenv TIMEX_DATA_DIR
  return $rc
}

check() {
  local name="$1" data="$2" ok=0
  case "$name" in
    s1-zerostate-detect)
      assert "project count" "$(q "$data" 'SELECT COUNT(*) FROM ZPROJECT;')" == 1 || ok=1
      assert "project name" "$(q "$data" 'SELECT ZNAME FROM ZPROJECT;')" == "Demo Project" || ok=1
      assert "seconds" "$(q "$data" 'SELECT IFNULL(SUM(ZACTIVESECONDS),0) FROM ZWORKSESSION;')" "~=" 30 3 || ok=1 ;;
    s2-record60)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 1 || ok=1
      assert "seconds" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 60 3 || ok=1 ;;
    s3-bridge-credit)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 1 || ok=1
      assert "seconds (30+60gap+30)" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 120 4 || ok=1 ;;
    s4-bridge-expiry)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 2 || ok=1
      assert "seconds (gap dropped)" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 60 4 || ok=1 ;;
    s5-satellite)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 1 || ok=1
      # window = 60s from LAST anchor tick (t=30) → chrome sustains until t=90
      assert "seconds (30 anchor + 60 in-window)" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 90 4 || ok=1 ;;
    s6-pause-mid-gap)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 2 || ok=1
      assert "seconds (paused gap never billed)" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 50 4 || ok=1 ;;
    s7-midnight)
      assert "sessions" "$(q "$data" 'SELECT COUNT(*) FROM ZWORKSESSION;')" == 2 || ok=1
      assert "distinct days" "$(q "$data" "SELECT COUNT(DISTINCT date(ZSTART + 978307200, 'unixepoch', 'localtime')) FROM ZWORKSESSION;")" == 2 || ok=1
      assert "seconds preserved" "$(q "$data" 'SELECT SUM(ZACTIVESECONDS) FROM ZWORKSESSION;')" "~=" 90 4 || ok=1 ;;
  esac
  return $ok
}

echo "harness: $APP"
echo "iterations: $ITER"
OVERALL=0
for i in $(seq 1 "$ITER"); do
  echo "── iteration $i"
  for f in s1-zerostate-detect s2-record60 s3-bridge-credit s4-bridge-expiry s5-satellite s6-pause-mid-gap s7-midnight; do
    DATA=$(mktemp -d)
    run_scenario "$f.txt" "$DATA"
    if check "$f" "$DATA"; then
      echo "  PASS $f"
    else
      echo "  FAIL $f (data: $DATA)"
      OVERALL=1; FAILS=$((FAILS+1))
    fi
    [ "$OVERALL" = "0" ] && rm -rf "$DATA"
  done
  # S8: relaunch over S2's data — nothing duplicated, nothing lost
  DATA=$(mktemp -d)
  run_scenario "s2-record60.txt" "$DATA"
  BEFORE=$(q "$DATA" 'SELECT COUNT(*) || "|" || CAST(SUM(ZACTIVESECONDS) AS INT) FROM ZWORKSESSION;')
  run_scenario "s8-noop-relaunch.txt" "$DATA"
  AFTER=$(q "$DATA" 'SELECT COUNT(*) || "|" || CAST(SUM(ZACTIVESECONDS) AS INT) FROM ZWORKSESSION;')
  if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then
    echo "  PASS s8-noop-relaunch ($BEFORE unchanged)"
  else
    echo "  FAIL s8-noop-relaunch (before=$BEFORE after=$AFTER)"
    OVERALL=1; FAILS=$((FAILS+1))
  fi
  rm -rf "$DATA"
  echo "  NOTE s9-csv: covered at unit level (CSVExporterTests, exact-total assertions)"
done
echo "──────────"
if [ "$OVERALL" = "0" ]; then echo "RESULT: ALL PASS"; else echo "RESULT: $FAILS FAILURES"; fi
exit $OVERALL
