#!/usr/bin/env bash
# Tests for lib/check-deps.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CHECKER="$LIB_DIR/check-deps.sh"

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

# Write a REQ file with the given Depends on: value.
# Args: $1 = path, $2 = id (for heading), $3 = deps line value
write_req() {
  local path="$1"
  local id="$2"
  local deps="$3"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:** $deps
EOF
}

# Write an archived REQ stub (just needs to exist).
write_archived() {
  local path="$1"
  local id="$2"
  cat > "$path" <<EOF
# $id: Archived REQ

**UR:** UR-001
**Status:** done
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:**
EOF
}

setup_fixture() {
  TMP="$(mktemp -d -t check-deps-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_checker() {
  # $1 = req path (relative to $TMP)
  local req_path="$1"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$CHECKER" "$req_path" > "$out_file" 2> "$err_file" )
  CHK_RC=$?
  CHK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  CHK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: no deps → empty stdout, exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="no-deps"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-001-foo.md" "REQ-001" ""
run_checker ".do-work/REQ-001-foo.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: all deps satisfied (single dep) → empty stdout, exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="all-satisfied-single"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-005-prior.md" "REQ-005"
write_req "$TMP/.do-work/REQ-010-target.md" "REQ-010" "REQ-005"
run_checker ".do-work/REQ-010-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: all deps satisfied (multiple, with whitespace variations)
# ----------------------------------------------------------------------
CURRENT_CASE="all-satisfied-multiple-whitespace"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-005-a.md" "REQ-005"
write_archived "$TMP/.do-work/archive/REQ-007-b.md" "REQ-007"
write_archived "$TMP/.do-work/archive/REQ-009-c.md" "REQ-009"
write_req "$TMP/.do-work/REQ-020-target.md" "REQ-020" "REQ-005, REQ-007 ,REQ-009"
run_checker ".do-work/REQ-020-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: one missing dep → that id on stdout
# ----------------------------------------------------------------------
CURRENT_CASE="one-missing"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-005-a.md" "REQ-005"
write_req "$TMP/.do-work/REQ-030-target.md" "REQ-030" "REQ-005, REQ-099"
run_checker ".do-work/REQ-030-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "REQ-099" "$CHK_STDOUT" "$CURRENT_CASE stdout has REQ-099"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: multiple missing deps → all on stdout (one per line)
# ----------------------------------------------------------------------
CURRENT_CASE="multiple-missing"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-005-a.md" "REQ-005"
write_req "$TMP/.do-work/REQ-040-target.md" "REQ-040" "REQ-005, REQ-098, REQ-099"
run_checker ".do-work/REQ-040-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-098" "$CHK_STDOUT" "$CURRENT_CASE stdout has REQ-098"
assert_contains "REQ-099" "$CHK_STDOUT" "$CURRENT_CASE stdout has REQ-099"
assert_not_contains "REQ-005" "$CHK_STDOUT" "$CURRENT_CASE stdout omits satisfied REQ-005"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: milestone-form ids (REQ-M2-041) — satisfied and missing
# ----------------------------------------------------------------------
CURRENT_CASE="milestone-form-ids"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-M2-041-done.md" "REQ-M2-041"
write_req "$TMP/.do-work/REQ-M2-050-target.md" "REQ-M2-050" "REQ-M2-041, REQ-M2-049"
run_checker ".do-work/REQ-M2-050-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "REQ-M2-049" "$CHK_STDOUT" "$CURRENT_CASE stdout has missing milestone dep"
assert_not_contains "REQ-M2-041" "$CHK_STDOUT" "$CURRENT_CASE stdout omits satisfied milestone dep"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: malformed dep id → logged to stderr, NOT to stdout
# ----------------------------------------------------------------------
CURRENT_CASE="malformed-id"
CASES=$((CASES + 1))
setup_fixture
write_archived "$TMP/.do-work/archive/REQ-005-a.md" "REQ-005"
write_req "$TMP/.do-work/REQ-060-target.md" "REQ-060" "REQ-005, notarequid, FOO-001, REQ-"
run_checker ".do-work/REQ-060-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (no missing valid deps)"
assert_contains "notarequid" "$CHK_STDERR" "$CURRENT_CASE stderr mentions notarequid"
assert_contains "FOO-001" "$CHK_STDERR" "$CURRENT_CASE stderr mentions FOO-001"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: deps line missing entirely → empty stdout, exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="deps-line-missing"
CASES=$((CASES + 1))
setup_fixture
cat > "$TMP/.do-work/REQ-070-target.md" <<EOF
# REQ-070: No deps line

**UR:** UR-001
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
EOF
run_checker ".do-work/REQ-070-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 9: archive glob — REQ-005 must match REQ-005-anything.md (not REQ-0050)
# ----------------------------------------------------------------------
CURRENT_CASE="prefix-not-substring"
CASES=$((CASES + 1))
setup_fixture
# Only REQ-0050 is archived (not REQ-005) — REQ-005 should be flagged missing.
write_archived "$TMP/.do-work/archive/REQ-0050-something.md" "REQ-0050"
write_req "$TMP/.do-work/REQ-080-target.md" "REQ-080" "REQ-005"
run_checker ".do-work/REQ-080-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "REQ-005" "$CHK_STDOUT" "$CURRENT_CASE REQ-005 still missing (REQ-0050 must not satisfy it)"
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
