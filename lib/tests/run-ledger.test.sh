#!/usr/bin/env bash
# Tests for lib/run-ledger.sh.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/run-ledger.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

setup_project() {
  TMP="$(mktemp -d -t run-ledger-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive" "$TMP/.do-work/runs" "$TMP/lib"
  cat > "$TMP/.do-work/config.yml" <<'EOF'
ledger:
  enabled: true
EOF
  REQ="$TMP/.do-work/archive/REQ-001-test.md"
  cat > "$REQ" <<'EOF'
# REQ-001

**UR:** UR-001
**Status:** done
**Closure proof:** tests:passed
EOF
  cat > "$TMP/lib/derive-status.sh" <<'EOF'
#!/usr/bin/env bash
if grep -Fq '**Closure proof:** tests:passed' "$1"; then
  echo "REQ-001 proven"
else
  echo "REQ-001 unproven"
fi
EOF
  chmod +x "$TMP/lib/derive-status.sh"
  COMMANDS="$TMP/commands.txt"
  TESTS="$TMP/tests.txt"
  FILES="$TMP/files.txt"
  printf 'npm test\n' > "$COMMANDS"
  printf 'npm test\n' > "$TESTS"
  printf 'src/app.ts\n' > "$FILES"
}

teardown_project() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

write_ledger() {
  OUT="$(bash "$SCRIPT" --project "$TMP" --req "$REQ" --agent agent-1 --model sonnet --branch req/REQ-001 --started 2026-06-09T00:00:00Z --ended 2026-06-09T00:01:00Z --result "$1" --review "$2" --cost "$3" --commands "$COMMANDS" --tests "$TESTS" --changed-files "$FILES")"
  RC=$?
}

CURRENT_CASE="required-fields"
CASES=$((CASES + 1))
setup_project
write_ledger "done" "passed" "0.01"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
grep -q '^run_id: RUN-001$' "$OUT" || fail "$CURRENT_CASE run id"
grep -q '^req: REQ-001$' "$OUT" || fail "$CURRENT_CASE req"
grep -q '^model: "sonnet"$' "$OUT" || fail "$CURRENT_CASE model"
grep -q '^result: "done"$' "$OUT" || fail "$CURRENT_CASE result"
grep -q '^review_outcome: "passed"$' "$OUT" || fail "$CURRENT_CASE review"
grep -q '^proof_status: "proven"$' "$OUT" || fail "$CURRENT_CASE proof"
grep -q '  - "npm test"' "$OUT" || fail "$CURRENT_CASE command list"
teardown_project

CURRENT_CASE="stable-numbering"
CASES=$((CASES + 1))
setup_project
write_ledger "done" "passed" ""
FIRST="$OUT"
write_ledger "done" "passed" ""
SECOND="$OUT"
assert_eq "$TMP/.do-work/runs/RUN-001.yml" "$FIRST" "$CURRENT_CASE first"
assert_eq "$TMP/.do-work/runs/RUN-002.yml" "$SECOND" "$CURRENT_CASE second"
teardown_project

CURRENT_CASE="disabled"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
ledger:
  enabled: false
EOF
write_ledger "done" "passed" ""
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "ledger: disabled" "$OUT" "$CURRENT_CASE output"
test ! -e "$TMP/.do-work/runs/RUN-001.yml" || fail "$CURRENT_CASE wrote file"
teardown_project

CURRENT_CASE="stopped-outcome"
CASES=$((CASES + 1))
setup_project
REQ="$TMP/.do-work/REQ-002-stop.md"
cat > "$REQ" <<'EOF'
# REQ-002

**UR:** UR-001
**Status:** stopped
EOF
write_ledger "stopped:policy-blocked" "not-run" ""
assert_eq "0" "$RC" "$CURRENT_CASE rc"
grep -q '^result: "stopped:policy-blocked"$' "$OUT" || fail "$CURRENT_CASE result"
grep -q '^proof_status: "unproven"$' "$OUT" || fail "$CURRENT_CASE proof"
teardown_project

CURRENT_CASE="pr-url-recorded"
CASES=$((CASES + 1))
setup_project
OUT="$(bash "$SCRIPT" --project "$TMP" --req "$REQ" --agent agent-1 --model sonnet \
  --branch req/REQ-001 --started 2026-06-09T00:00:00Z --ended 2026-06-09T00:01:00Z \
  --result done --review passed --cost "" \
  --pr "https://github.com/owner/repo/pull/42" \
  --commands "$COMMANDS" --tests "$TESTS" --changed-files "$FILES")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
grep -q '^pr_url: "https://github.com/owner/repo/pull/42"$' "$OUT" || fail "$CURRENT_CASE pr_url"
teardown_project

CURRENT_CASE="pr-url-absent"
CASES=$((CASES + 1))
setup_project
write_ledger "done" "passed" ""
grep -q '^pr_url: ""$' "$OUT" || fail "$CURRENT_CASE pr_url empty"
teardown_project

# --cost-estimate writes a numeric field distinct from the freeform --cost note.
CURRENT_CASE="cost-estimate-numeric-field"
CASES=$((CASES + 1))
setup_project
OUT="$(bash "$SCRIPT" --project "$TMP" --req "$REQ" --agent agent-1 --model sonnet \
  --branch req/REQ-001 --started 2026-06-09T00:00:00Z --ended 2026-06-09T00:01:00Z \
  --result done --review passed --cost "under budget" --cost-estimate "0.42" \
  --commands "$COMMANDS" --tests "$TESTS" --changed-files "$FILES")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
grep -q '^cost_estimate_num: 0.42$' "$OUT" || fail "$CURRENT_CASE numeric field"
grep -q '^cost_estimate: "under budget"$' "$OUT" || fail "$CURRENT_CASE freeform note preserved"
teardown_project

# Unset --cost-estimate defaults the numeric field to 0 (treated as no spend).
CURRENT_CASE="cost-estimate-default-zero"
CASES=$((CASES + 1))
setup_project
write_ledger "done" "passed" ""
grep -q '^cost_estimate_num: 0$' "$OUT" || fail "$CURRENT_CASE default zero"
teardown_project

# --sum-run sums cost_estimate_num across all RUN-*.yml in a runs dir.
CURRENT_CASE="sum-run-cumulative"
CASES=$((CASES + 1))
setup_project
bash "$SCRIPT" --project "$TMP" --req "$REQ" --result done --cost-estimate "0.50" >/dev/null
bash "$SCRIPT" --project "$TMP" --req "$REQ" --result done --cost-estimate "1.25" >/dev/null
bash "$SCRIPT" --project "$TMP" --req "$REQ" --result done --cost-estimate "0.25" >/dev/null
SUM="$(bash "$SCRIPT" --sum-run "$TMP/.do-work/runs")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "2.00" "$SUM" "$CURRENT_CASE sum"
teardown_project

# --sum-run on a runs dir with no numeric costs returns 0.00.
CURRENT_CASE="sum-run-empty"
CASES=$((CASES + 1))
setup_project
SUM="$(bash "$SCRIPT" --sum-run "$TMP/.do-work/runs")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "0.00" "$SUM" "$CURRENT_CASE empty sum"
teardown_project

# --sum-run errors when the runs dir is missing.
CURRENT_CASE="sum-run-missing-dir"
CASES=$((CASES + 1))
setup_project
SUM="$(bash "$SCRIPT" --sum-run "$TMP/.do-work/nonexistent" 2>/dev/null)"
RC=$?
assert_eq "1" "$RC" "$CURRENT_CASE rc"
teardown_project

# Budget gate fixture: cumulative ledger spend crossing a budget is detectable
# via --sum-run. Demonstrates the run-loop gate's arithmetic (spent >= budget).
CURRENT_CASE="budget-gate-crosses"
CASES=$((CASES + 1))
setup_project
BUDGET="3.00"
# REQ 1 completes: spend 2.00 (still under budget) -> loop continues.
bash "$SCRIPT" --project "$TMP" --req "$REQ" --result done --cost-estimate "2.00" >/dev/null
SUM1="$(bash "$SCRIPT" --sum-run "$TMP/.do-work/runs")"
awk -v s="$SUM1" -v b="$BUDGET" 'BEGIN { exit (s+0 < b+0) ? 0 : 1 }' \
  || fail "$CURRENT_CASE expected under-budget after REQ1 (sum=$SUM1)"
# REQ 2 completes: spend +1.50 -> cumulative 3.50 crosses budget -> gate trips.
bash "$SCRIPT" --project "$TMP" --req "$REQ" --result done --cost-estimate "1.50" >/dev/null
SUM2="$(bash "$SCRIPT" --sum-run "$TMP/.do-work/runs")"
assert_eq "3.50" "$SUM2" "$CURRENT_CASE cumulative"
awk -v s="$SUM2" -v b="$BUDGET" 'BEGIN { exit (s+0 >= b+0) ? 0 : 1 }' \
  || fail "$CURRENT_CASE expected budget crossed after REQ2 (sum=$SUM2)"
teardown_project

echo ""
echo "run-ledger tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
