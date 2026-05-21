#!/usr/bin/env bash
# Tests for lib/cycle-check.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CHECKER="$LIB_DIR/cycle-check.sh"

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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: did not expect substring '$needle' in '$haystack'" ;;
  esac
}

# Write a REQ file.
# Args: $1=path, $2=req-id, $3=ur (e.g. UR-001), $4=depends-on (comma list or empty)
write_req() {
  local path="$1"
  local id="$2"
  local ur="$3"
  local deps="$4"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:** $deps
EOF
}

setup_fixture() {
  TMP="$(mktemp -d -t cycle-check-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working"
  mkdir -p "$TMP/.do-work/archive"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_checker() {
  # $@ = optional args to cycle-check.sh
  local out_file="$TMP/.stdout.$$"
  local err_file="$TMP/.stderr.$$"
  ( cd "$TMP" && "$CHECKER" "$@" > "$out_file" 2> "$err_file" )
  CHK_RC=$?
  CHK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  CHK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

# ----------------------------------------------------------------------
# Case 1: empty graph — no REQ files anywhere → exit 0, silent
# ----------------------------------------------------------------------
CURRENT_CASE="empty-graph"
CASES=$((CASES + 1))
setup_fixture
run_checker
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: linear chain of 5 REQs (no cycle) → exit 0, silent
# ----------------------------------------------------------------------
CURRENT_CASE="linear-chain-no-cycle"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-001-a.md" "REQ-001" "UR-001" ""
write_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001" "REQ-001"
write_req "$TMP/.do-work/REQ-003-c.md" "REQ-003" "UR-001" "REQ-002"
write_req "$TMP/.do-work/REQ-004-d.md" "REQ-004" "UR-001" "REQ-003"
write_req "$TMP/.do-work/REQ-005-e.md" "REQ-005" "UR-001" "REQ-004"
run_checker
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: single cycle (REQ-007 → REQ-009 → REQ-007) → exit 1, prints cycle
# ----------------------------------------------------------------------
CURRENT_CASE="single-cycle"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-007-x.md" "REQ-007" "UR-001" "REQ-009"
write_req "$TMP/.do-work/REQ-009-y.md" "REQ-009" "UR-001" "REQ-007"
run_checker
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-007" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-007"
assert_contains "REQ-009" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-009"
assert_contains "→" "$CHK_STDOUT" "$CURRENT_CASE stdout contains arrow"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: self-loop (REQ-010 depends on itself) → exit 1
# ----------------------------------------------------------------------
CURRENT_CASE="self-loop"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-010-self.md" "REQ-010" "UR-001" "REQ-010"
run_checker
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-010" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-010"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: UR-scoped invocation ignores deps outside that UR
# ----------------------------------------------------------------------
CURRENT_CASE="ur-scoped-cross-ur-edge-ignored"
CASES=$((CASES + 1))
setup_fixture
# REQ-020 in UR-002 depends on REQ-100 in UR-999.
# REQ-100 (UR-999) depends on REQ-020 — would be a cycle unscoped.
# Scoped to UR-002: REQ-100 is not in scope, so no cycle reported.
write_req "$TMP/.do-work/REQ-020-a.md" "REQ-020" "UR-002" "REQ-100"
write_req "$TMP/.do-work/REQ-100-b.md" "REQ-100" "UR-999" "REQ-020"
run_checker "UR-002"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: UR-scoped invocation detects cycle within the UR
# ----------------------------------------------------------------------
CURRENT_CASE="ur-scoped-cycle-within-ur"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-030-a.md" "REQ-030" "UR-003" "REQ-031"
write_req "$TMP/.do-work/REQ-031-b.md" "REQ-031" "UR-003" "REQ-030"
run_checker "UR-003"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-030" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-030"
assert_contains "REQ-031" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-031"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: unscoped — REQs across backlog + working/ + archive/ all scanned
# ----------------------------------------------------------------------
CURRENT_CASE="scan-backlog-working-archive"
CASES=$((CASES + 1))
setup_fixture
# REQ-040 (backlog) depends on REQ-041 (working) depends on REQ-040 → cycle
write_req "$TMP/.do-work/REQ-040-a.md"          "REQ-040" "UR-004" "REQ-041"
write_req "$TMP/.do-work/working/REQ-041-b.md"  "REQ-041" "UR-004" "REQ-040"
run_checker
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-040" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-040"
assert_contains "REQ-041" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-041"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: archive REQ in the chain — cycle still detected
# ----------------------------------------------------------------------
CURRENT_CASE="archive-included"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-050-a.md"          "REQ-050" "UR-005" "REQ-051"
write_req "$TMP/.do-work/archive/REQ-051-b.md"  "REQ-051" "UR-005" "REQ-050"
run_checker
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-050" "$CHK_STDOUT" "$CURRENT_CASE stdout contains REQ-050"
teardown_fixture

# ----------------------------------------------------------------------
# Case 9: linear chain of 100+ REQs — stack safety, no cycle
# ----------------------------------------------------------------------
CURRENT_CASE="linear-chain-100-plus"
CASES=$((CASES + 1))
setup_fixture
# REQ-200..REQ-310: chain of 111 REQs, REQ-N depends on REQ-(N-1)
write_req "$TMP/.do-work/REQ-200-a.md" "REQ-200" "UR-006" ""
i=201
while [ "$i" -le 310 ]; do
  prev=$((i - 1))
  write_req "$TMP/.do-work/REQ-${i}-x.md" "REQ-${i}" "UR-006" "REQ-${prev}"
  i=$((i + 1))
done
run_checker
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty on long chain"
teardown_fixture

# ----------------------------------------------------------------------
# Case 10: three-node cycle — output shows all three
# ----------------------------------------------------------------------
CURRENT_CASE="three-node-cycle"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-070-a.md" "REQ-070" "UR-007" "REQ-071"
write_req "$TMP/.do-work/REQ-071-b.md" "REQ-071" "UR-007" "REQ-072"
write_req "$TMP/.do-work/REQ-072-c.md" "REQ-072" "UR-007" "REQ-070"
run_checker
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-070" "$CHK_STDOUT" "$CURRENT_CASE has REQ-070"
assert_contains "REQ-071" "$CHK_STDOUT" "$CURRENT_CASE has REQ-071"
assert_contains "REQ-072" "$CHK_STDOUT" "$CURRENT_CASE has REQ-072"
teardown_fixture

# ----------------------------------------------------------------------
# Case 11: scoped run does not report unrelated unscoped cycle
# ----------------------------------------------------------------------
CURRENT_CASE="scoped-ignores-unrelated-cycle"
CASES=$((CASES + 1))
setup_fixture
# UR-008 has a clean linear chain. UR-009 has a cycle. Scoping to UR-008 → exit 0.
write_req "$TMP/.do-work/REQ-080-a.md" "REQ-080" "UR-008" ""
write_req "$TMP/.do-work/REQ-081-b.md" "REQ-081" "UR-008" "REQ-080"
write_req "$TMP/.do-work/REQ-090-c.md" "REQ-090" "UR-009" "REQ-091"
write_req "$TMP/.do-work/REQ-091-d.md" "REQ-091" "UR-009" "REQ-090"
run_checker "UR-008"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
