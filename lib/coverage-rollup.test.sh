#!/usr/bin/env bash
# Tests for lib/coverage-rollup.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT="$SCRIPT_DIR/coverage-rollup.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
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

setup_fixture() {
  TMP="$(mktemp -d -t coverage-rollup-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive" "$TMP/.do-work/working"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

write_req() {
  local path="$1"
  local id="$2"
  local ur="$3"
  local status="$4"
  local proof="$5"
  local layer="${6:-agents}"
  cat > "$path" <<EOF
# $id: Test

**UR:** $ur
**Status:** $status
**Created:** 2026-06-09
**Layer:** $layer
**Closure proof:** $proof
**Files:** agents/run.md
**Depends on:**
EOF
}

# write_closure <ur> <overall> [closed-count] [gaps-count]
# Writes a minimal UR-NNN/closure.md with the front-matter fields the rollup reads.
write_closure() {
  local ur="$1"
  local overall="$2"
  local closed="${3:-0}"
  local gaps="${4:-0}"
  local dir="$TMP/.do-work/user-requests/$ur"
  mkdir -p "$dir"
  cat > "$dir/closure.md" <<EOF
---
ur: $ur
closed_at: 2026-06-12T14:20:05Z
branch: main
path_units: $((closed + gaps))
verdict_summary:
  closed: $closed
  terminal-mismatch: $gaps
overall: $overall
---

# Closure report — $ur
EOF
}

run_script() {
  local scope="${1:-}"
  if [ -n "$scope" ]; then
    OUT="$(cd "$TMP" && bash "$SCRIPT" "$scope")"
  else
    OUT="$(cd "$TMP" && bash "$SCRIPT")"
  fi
  RC=$?
}

CURRENT_CASE="mixed-proven-unproven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-001-a.md" "REQ-001" "UR-001" "done" "checkpoint:RUN-001 commit:abc"
write_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001" "backlog" ""
write_req "$TMP/.do-work/working/REQ-003-c.md" "REQ-003" "UR-001" "in-progress" "checkpoint:RUN-003 commit:def"
run_script
assert_contains "UR-001 intended=3 proven=1 unproven=2" "$OUT" "$CURRENT_CASE counts"
assert_contains "unproven_ids=REQ-002,REQ-003" "$OUT" "$CURRENT_CASE ids"
# Additive: a UR with no path-unit REQs and no closure.md reports closed=n/a,
# and the existing fields are unchanged.
assert_contains "closed=n/a" "$OUT" "$CURRENT_CASE closure column"
teardown_fixture

CURRENT_CASE="fully-proven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-004-a.md" "REQ-004" "UR-002" "done" "checkpoint:RUN-004 commit:abc"
write_req "$TMP/.do-work/archive/REQ-005-b.md" "REQ-005" "UR-002" "done" "checkpoint:RUN-005 commit:def"
run_script "UR-002"
assert_contains "UR-002 intended=2 proven=2 unproven=0" "$OUT" "$CURRENT_CASE counts"
teardown_fixture

# --- Closure column (REQ-213): end-to-end closure state per UR ---

# closed=yes: path-unit REQ present, closure.md exists with overall: closed.
CURRENT_CASE="closure-yes"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-010-pu.md" "REQ-010" "UR-010" "done" "checkpoint:RUN-010 commit:abc" "none"
write_req "$TMP/.do-work/archive/REQ-011-impl.md" "REQ-011" "UR-010" "done" "checkpoint:RUN-011 commit:def" "agents"
write_closure "UR-010" "closed" 1 0
run_script "UR-010"
assert_contains "UR-010 intended=2 proven=2 unproven=0" "$OUT" "$CURRENT_CASE counts"
assert_contains "closed=yes" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=no (gaps): path-unit REQ present, closure.md exists with overall: gaps.
CURRENT_CASE="closure-no-gaps"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-020-pu.md" "REQ-020" "UR-020" "done" "checkpoint:RUN-020 commit:abc" "none"
write_closure "UR-020" "gaps" 0 1
run_script "UR-020"
assert_contains "closed=no" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=no (absent): path-unit REQ done but no closure.md written yet.
CURRENT_CASE="closure-no-absent"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-030-pu.md" "REQ-030" "UR-030" "done" "checkpoint:RUN-030 commit:abc" "none"
run_script "UR-030"
assert_contains "closed=no" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=n/a: UR has no path-unit REQs at all.
CURRENT_CASE="closure-na"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-040-a.md" "REQ-040" "UR-040" "done" "checkpoint:RUN-040 commit:abc" "agents"
run_script "UR-040"
assert_contains "closed=n/a" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

echo ""
echo "coverage-rollup tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0

