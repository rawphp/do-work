#!/usr/bin/env bash
# Tests for lib/pick-req.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
PICKER="$LIB_DIR/pick-req.sh"

FAILED=0
CASES=0

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

# Build a REQ file under $1 with id $2, files $3, deps $4, ur $5, status $6
write_req() {
  local path="$1"
  local id="$2"
  local files="$3"
  local deps="$4"
  local ur="$5"
  local status="$6"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** $status
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:** $deps
EOF
}

# Build a REQ file with an explicit **Priority:** field.
# Args: $1=path $2=id $3=files $4=deps $5=ur $6=status $7=priority (1-3)
write_req_pri() {
  local path="$1"
  local id="$2"
  local files="$3"
  local deps="$4"
  local ur="$5"
  local status="$6"
  local priority="$7"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** $status
**Created:** 2026-05-21
**Layer:** agents
**Priority:** $priority
**Size:** M
**Files:** $files
**Depends on:** $deps
EOF
}

# Build a working/ REQ (with claim stamp) at $1 for id $2, files $3, ur $4
write_working_req() {
  local path="$1"
  local id="$2"
  local files="$3"
  local ur="$4"
  cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** test-other-agent
**Claimed at:** 2026-05-21T00:00:00Z
**Heartbeat:** 2026-05-21T00:00:00Z
<!-- claimed-end -->

**UR:** $ur
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:**
EOF
}

setup_fixture() {
  TMP="$(mktemp -d -t pick-req-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive" "$TMP/.do-work/state"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_picker() {
  # $1 = scope, $2 = agent-id
  # Returns: stdout in $PICK_STDOUT, stderr in $PICK_STDERR, exit in $PICK_RC
  local scope="$1"
  local agent="$2"
  local out err
  err_file="$TMP/.stderr.$$"
  ( cd "$TMP" && "$PICKER" "$scope" "$agent" 2> "$err_file" )
  PICK_RC=$?
  PICK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file"
  return 0
}

# Capture stdout properly
run_picker() {
  local scope="$1"
  local agent="$2"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$PICKER" "$scope" "$agent" > "$out_file" 2> "$err_file" )
  PICK_RC=$?
  PICK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  PICK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: pickable exists (no deps, no overlap, scope=any)
# ----------------------------------------------------------------------
CURRENT_CASE="pickable-exists"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-001-foo.md"  "REQ-001" "src/a.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-002-bar.md"  "REQ-002" "src/b.ts" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-001-foo.md" "$PICK_STDOUT" "$CURRENT_CASE stdout"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: all deps blocked → empty stdout, exit 1, stderr lists dep:<id>
# ----------------------------------------------------------------------
CURRENT_CASE="all-deps-blocked"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-010-foo.md" "REQ-010" "src/x.ts" "REQ-099" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-011-bar.md" "REQ-011" "src/y.ts" "REQ-099" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE stdout empty"
assert_contains "dep:REQ-099" "$PICK_STDERR" "$CURRENT_CASE stderr has dep:REQ-099"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: all overlap blocked → empty stdout, exit 1, stderr lists overlap:<id>
# ----------------------------------------------------------------------
CURRENT_CASE="all-overlap-blocked"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-020-claimed.md" "REQ-020" "src/shared.ts" "UR-001"
write_req "$TMP/.do-work/REQ-021-conflict.md" "REQ-021" "src/shared.ts" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE stdout empty"
assert_contains "overlap:REQ-020" "$PICK_STDERR" "$CURRENT_CASE stderr has overlap:REQ-020"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: scope blocked → empty stdout, stderr lists scope:<UR>
# ----------------------------------------------------------------------
CURRENT_CASE="scope-blocked"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-030-foo.md" "REQ-030" "src/a.ts" "" "UR-005" "backlog"
write_req "$TMP/.do-work/REQ-031-bar.md" "REQ-031" "src/b.ts" "" "UR-005" "backlog"
run_picker "UR-001" "test-agent"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE stdout empty"
assert_contains "scope:UR-005" "$PICK_STDERR" "$CURRENT_CASE stderr has scope:UR-005"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: empty backlog → empty stdout, exit 1, no stderr categories
# ----------------------------------------------------------------------
CURRENT_CASE="empty-backlog"
CASES=$((CASES + 1))
setup_fixture
run_picker "any" "test-agent"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE stdout empty"
assert_not_contains "dep:" "$PICK_STDERR" "$CURRENT_CASE no dep stderr"
assert_not_contains "overlap:" "$PICK_STDERR" "$CURRENT_CASE no overlap stderr"
assert_not_contains "scope:" "$PICK_STDERR" "$CURRENT_CASE no scope stderr"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: milestone-mode filtering
# Only REQ-M2-* files should be considered when active-milestone.md = M2
# ----------------------------------------------------------------------
CURRENT_CASE="milestone-mode-filtering"
CASES=$((CASES + 1))
setup_fixture
echo "M2" > "$TMP/.do-work/state/active-milestone.md"
write_req "$TMP/.do-work/REQ-M1-040-foo.md" "REQ-M1-040" "src/a.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-M2-041-bar.md" "REQ-M2-041" "src/b.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-M3-042-baz.md" "REQ-M3-042" "src/c.ts" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-M2-041-bar.md" "$PICK_STDOUT" "$CURRENT_CASE stdout is M2 REQ"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: dep satisfied via archive → REQ is pickable
# ----------------------------------------------------------------------
CURRENT_CASE="dep-satisfied-via-archive"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-050-done.md" "REQ-050" "src/old.ts" "" "UR-001" "done"
write_req "$TMP/.do-work/REQ-051-next.md" "REQ-051" "src/new.ts" "REQ-050" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-051-next.md" "$PICK_STDOUT" "$CURRENT_CASE stdout"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: numeric sort — REQ-009 before REQ-010 (lexical would put 010 first
#         only if zero-padded; both work here, but verify deterministic order)
# ----------------------------------------------------------------------
CURRENT_CASE="numeric-sort-ascending"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-010-later.md" "REQ-010" "src/x.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-002-earlier.md" "REQ-002" "src/y.ts" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-002-earlier.md" "$PICK_STDOUT" "$CURRENT_CASE picks lower number first"
teardown_fixture

# ----------------------------------------------------------------------
# Case 9: glob in **Files:** expands and detects overlap
# ----------------------------------------------------------------------
CURRENT_CASE="glob-expansion-overlap"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/app/Models"
touch "$TMP/app/Models/FooBar.php"
write_working_req "$TMP/.do-work/working/REQ-060-claimed.md" "REQ-060" "app/Models/Foo*.php" "UR-001"
write_req "$TMP/.do-work/REQ-061-conflict.md" "REQ-061" "app/Models/FooBar.php" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE rc"
assert_contains "overlap:REQ-060" "$PICK_STDERR" "$CURRENT_CASE detected glob overlap"
teardown_fixture

# ----------------------------------------------------------------------
# Case 10: mixed — first candidate scope-blocked, second pickable
# ----------------------------------------------------------------------
CURRENT_CASE="scope-filter-then-pick"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-070-other-ur.md" "REQ-070" "src/a.ts" "" "UR-002" "backlog"
write_req "$TMP/.do-work/REQ-071-target.md"    "REQ-071" "src/b.ts" "" "UR-001" "backlog"
run_picker "UR-001" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-071-target.md" "$PICK_STDOUT" "$CURRENT_CASE stdout"
assert_contains "scope:UR-002" "$PICK_STDERR" "$CURRENT_CASE scope rejection logged"
teardown_fixture

# ----------------------------------------------------------------------
# Case 11: priority ordering — higher Priority claimed first even when its
#          REQ number is higher. REQ-A (Priority 1, lower number) must lose
#          to REQ-B (Priority 3, higher number).
# ----------------------------------------------------------------------
CURRENT_CASE="priority-beats-req-number"
CASES=$((CASES + 1))
setup_fixture
write_req_pri "$TMP/.do-work/REQ-080-low-pri.md"  "REQ-080" "src/a.ts" "" "UR-001" "backlog" "1"
write_req_pri "$TMP/.do-work/REQ-081-high-pri.md" "REQ-081" "src/b.ts" "" "UR-001" "backlog" "3"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-081-high-pri.md" "$PICK_STDOUT" "$CURRENT_CASE picks higher Priority first"
teardown_fixture

# ----------------------------------------------------------------------
# Case 12: equal priority → fall back to lower REQ number (existing tiebreak).
# ----------------------------------------------------------------------
CURRENT_CASE="equal-priority-tiebreak-by-number"
CASES=$((CASES + 1))
setup_fixture
write_req_pri "$TMP/.do-work/REQ-090-first.md"  "REQ-090" "src/a.ts" "" "UR-001" "backlog" "3"
write_req_pri "$TMP/.do-work/REQ-091-second.md" "REQ-091" "src/b.ts" "" "UR-001" "backlog" "3"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-090-first.md" "$PICK_STDOUT" "$CURRENT_CASE lower number wins on equal priority"
teardown_fixture

# ----------------------------------------------------------------------
# Case 13: all-legacy backlog (no Priority field) → order unchanged from
#          today. Absent Priority must sort exactly as Priority 2, so the
#          lowest REQ number is picked just like before this feature existed.
# ----------------------------------------------------------------------
CURRENT_CASE="all-legacy-order-unchanged"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-100-foo.md" "REQ-100" "src/a.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-101-bar.md" "REQ-101" "src/b.ts" "" "UR-001" "backlog"
write_req "$TMP/.do-work/REQ-102-baz.md" "REQ-102" "src/c.ts" "" "UR-001" "backlog"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-100-foo.md" "$PICK_STDOUT" "$CURRENT_CASE legacy picks lowest number"
teardown_fixture

# ----------------------------------------------------------------------
# Case 14: mixed legacy + prioritized — a legacy REQ (absent Priority == 2)
#          must lose to an explicit Priority 3, but beat an explicit
#          Priority 1, regardless of REQ number.
# ----------------------------------------------------------------------
CURRENT_CASE="absent-priority-sorts-as-2"
CASES=$((CASES + 1))
setup_fixture
write_req_pri "$TMP/.do-work/REQ-110-explicit-low.md"  "REQ-110" "src/a.ts" "" "UR-001" "backlog" "1"
write_req     "$TMP/.do-work/REQ-111-legacy.md"        "REQ-111" "src/b.ts" "" "UR-001" "backlog"
write_req_pri "$TMP/.do-work/REQ-112-explicit-high.md" "REQ-112" "src/c.ts" "" "UR-001" "backlog" "3"
run_picker "any" "test-agent"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_eq "$TMP/.do-work/REQ-112-explicit-high.md" "$PICK_STDOUT" "$CURRENT_CASE Priority 3 wins overall"
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
