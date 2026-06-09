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

echo ""
echo "run-ledger tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
