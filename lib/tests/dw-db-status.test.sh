#!/usr/bin/env bash
# dw-db-status.test.sh — status-synth: situation rows, proven/unproven, closed.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW="$LIB_DIR/dw-db.sh"
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED+1)); }

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 not installed"
  exit 0
fi

TMP="$(mktemp -d -t dw-status.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

ur="$(bash "$DW" create-ur "$TMP" --title "Status UR" --brief "brief for status")" \
  || { fail "create-ur"; rm -rf "$TMP"; exit 1; }

# REQ A: done + non-empty proof + AC checked → proven
req_proven="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Proven REQ" \
  --body "## Acceptance Criteria
- [x] works
" --layer "backend")" \
  || { fail "create-req proven"; rm -rf "$TMP"; exit 1; }

bash "$DW" update-req "$TMP" "$req_proven" --closure-proof "tests green" \
  || fail "set proof on proven"
bash "$DW" set-status "$TMP" "$req_proven" done \
  || fail "set proven done"

# REQ B: backlog, no proof → unproven
req_open="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Open REQ" \
  --body "## Acceptance Criteria
- [ ] not yet
" --files "src/x.ts")" \
  || { fail "create-req open"; rm -rf "$TMP"; exit 1; }

# Path-unit REQ (layer none) so closed field is meaningful
req_pu="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Path unit" \
  --layer "none" --body "## Acceptance Criteria
- [x] path ok
")" \
  || { fail "create-req path-unit"; rm -rf "$TMP"; exit 1; }
bash "$DW" update-req "$TMP" "$req_pu" --closure-proof "walked" \
  || fail "set proof on path-unit"
bash "$DW" set-status "$TMP" "$req_pu" done \
  || fail "set path-unit done"

# --- status-synth before close: proven/unproven + closed=no ---
out="$(bash "$DW" status-synth "$TMP" 2>&1)" || {
  fail "status-synth exit non-zero before close: $out"
  rm -rf "$TMP"
  exit 1
}

case "$out" in
  *"$req_proven"*proven*) : ;;
  *) fail "expected $req_proven proven in output: $out" ;;
esac
case "$out" in
  *"$req_open"*unproven*) : ;;
  *) fail "expected $req_open unproven in output: $out" ;;
esac
# path-unit is done+proof → proven too
case "$out" in
  *"$req_pu"*proven*) : ;;
  *) fail "expected $req_pu proven in output: $out" ;;
esac

# Coverage / closed before close write
case "$out" in
  *closed=no*) : ;;
  *closed=yes*) fail "closed should be no before write-close: $out" ;;
  *) fail "expected closed=no before write-close: $out" ;;
esac

# Totals / situation should mention statuses
case "$out" in
  *backlog*|*done*|*in_progress*|*in-progress*) : ;;
  *) fail "expected bucket/totals language in status-synth: $out" ;;
esac

# --- write-close → closed=yes ---
bash "$DW" write-close "$TMP" "$ur" --body "overall: closed
walked ok" \
  || fail "write-close"

out2="$(bash "$DW" status-synth "$TMP" 2>&1)" || {
  fail "status-synth after close failed: $out2"
  rm -rf "$TMP"
  exit 1
}
case "$out2" in
  *closed=yes*) : ;;
  *) fail "expected closed=yes after write-close: $out2" ;;
esac

# Scoped filter
out_scoped="$(bash "$DW" status-synth "$TMP" "$ur" 2>&1)" || fail "scoped status-synth failed"
case "$out_scoped" in
  *"$ur"*) : ;;
  *) fail "scoped output should mention $ur: $out_scoped" ;;
esac

# Unrelated UR scope yields no our REQs (or empty)
ur2="$(bash "$DW" create-ur "$TMP" --title "Other" --brief "other")" \
  || fail "create-ur2"
out_other="$(bash "$DW" status-synth "$TMP" "$ur2" 2>&1)" || fail "other scope failed"
case "$out_other" in
  *"$req_proven"*) fail "scoped to $ur2 should not list $req_proven: $out_other" ;;
esac

# suite=not-run downgrades proven
req_suite="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Suite not run" \
  --body "## Acceptance Criteria
- [x] ok
")" || fail "create suite req"
bash "$DW" update-req "$TMP" "$req_suite" --closure-proof "looks done" || fail "suite proof"
# set suite via raw SQL if update-req has no --suite; try update first
if ! bash "$DW" update-req "$TMP" "$req_suite" --suite "not-run" 2>/dev/null; then
  sqlite3 "$db" "UPDATE reqs SET suite='not-run' WHERE slug='$req_suite';"
fi
bash "$DW" set-status "$TMP" "$req_suite" done || fail "suite set done"
out3="$(bash "$DW" status-synth "$TMP" 2>&1)" || fail "status-synth suite case"
case "$out3" in
  *"$req_suite"*unproven*) : ;;
  *"$req_suite"*proven*) fail "suite=not-run must be unproven: $out3" ;;
  *) fail "expected $req_suite unproven for suite=not-run: $out3" ;;
esac

# done without proof → unproven
req_noproof="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "No proof" \
  --body "## Acceptance Criteria
- [x] ok
")" || fail "create noproof"
bash "$DW" set-status "$TMP" "$req_noproof" done || fail "noproof done"
out4="$(bash "$DW" status-synth "$TMP" 2>&1)" || fail "status-synth noproof"
case "$out4" in
  *"$req_noproof"*unproven*) : ;;
  *"$req_noproof"*proven*) fail "missing proof must be unproven: $out4" ;;
  *) fail "expected $req_noproof unproven: $out4" ;;
esac

rm -rf "$TMP"

if [ "$FAILED" -ne 0 ]; then
  echo "dw-db-status.test.sh: $FAILED failure(s)"
  exit 1
fi
echo "PASS: dw-db-status.test.sh"
exit 0
