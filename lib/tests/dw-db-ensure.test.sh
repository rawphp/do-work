#!/usr/bin/env bash
# dw-db-ensure.test.sh — ensure creates work.db with schema user_version=1.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW_DB="$LIB_DIR/dw-db.sh"
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED+1)); }

TMP="$(mktemp -d -t dw-db-ensure.XXXXXX)"
mkdir -p "$TMP/.do-work"

# Expect fail until implemented
if [ ! -x "$DW_DB" ] && [ ! -f "$DW_DB" ]; then
  fail "dw-db.sh missing"
fi

out="$(bash "$DW_DB" ensure "$TMP" 2>&1)" || true
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 not installed"
  rm -rf "$TMP"
  exit 0
fi

if [ ! -f "$TMP/.do-work/work.db" ]; then
  fail "work.db not created"
fi

ver="$(sqlite3 "$TMP/.do-work/work.db" 'PRAGMA user_version;')"
[ "$ver" = "1" ] || fail "user_version want 1 got $ver"

# idempotent second ensure
bash "$DW_DB" ensure "$TMP" >/dev/null || fail "second ensure failed"

# tables exist
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q urs || fail "missing urs"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q reqs || fail "missing reqs"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q claims || fail "missing claims"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q ur_artifacts || fail "missing ur_artifacts"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q deps || fail "missing deps"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q decisions || fail "missing decisions"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q calibration || fail "missing calibration"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q milestone_state || fail "missing milestone_state"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q run_notes || fail "missing run_notes"

# partial unique index for one active claim
sqlite3 "$TMP/.do-work/work.db" "SELECT sql FROM sqlite_master WHERE name='claims_one_active_per_req';" \
  | grep -qi unique || fail "missing claims_one_active_per_req"

# bad user_version hard-fails
BAD="$TMP/.do-work/bad.db"
sqlite3 "$BAD" "PRAGMA user_version=99;"
# ensure always targets default path; simulate bad version on work.db
cp "$BAD" "$TMP/.do-work/work.db"
if bash "$DW_DB" ensure "$TMP" >/dev/null 2>&1; then
  fail "ensure should hard-fail on unsupported user_version"
fi

rm -rf "$TMP"
[ "$FAILED" -eq 0 ] || exit 1
echo "PASS dw-db-ensure"
