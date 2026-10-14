#!/bin/bash
# Runs inside the compose.test.yaml runner: every test suite against every engine. Reports go to /results.
set -uo pipefail
cd /app
export QW_RESULTS=/results
overall=0
run() {
  local name="$1"; shift
  echo; echo "================ $name ================"
  "$@"; local rc=$?
  echo "---------------- $name: exit $rc"
  echo "$name|$rc" >> /results/summary.txt
  [ "$rc" -ne 0 ] && overall=1
  return 0
}
: > /results/summary.txt
run "Seed Northstar sample" python scripts/seed.py
run "Unit + pack tests" python -m pytest -q -p no:cacheprovider --ignore=tests/test_live_sources.py --ignore=tests/test_live_frontend.py --junitxml=/results/unit.xml
run "Browser SQLite/WASM" node scripts/test_browser_sql.cjs
run "Provision all engines (pack migrate+seed, reader accounts)" python scripts/live/provision.py
run "Live app tests (all engines)" python -m pytest -p no:cacheprovider tests/test_live_sources.py -rA -v --junitxml=/results/live.xml
run "Running backend + frontend (app container, headless Chromium)" python -m pytest -p no:cacheprovider tests/test_live_frontend.py -rA -v --junitxml=/results/frontend.xml
run "Pack verify_all (native verification)" python scripts/live/provision.py --verify-all
echo; echo "================ SUMMARY ================"; column -t -s'|' /results/summary.txt 2>/dev/null || cat /results/summary.txt
exit $overall
