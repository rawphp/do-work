#!/usr/bin/env bash
# Tests for lib/check-footprint.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CHECKER="$LIB_DIR/check-footprint.sh"

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

# Write a REQ file with given Files: line.
# Args: $1 = path, $2 = id, $3 = files line value
write_req() {
  local path="$1"
  local id="$2"
  local files="$3"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:**

## Task

Do the thing.
EOF
}

# Write a REQ file with NO **Files:** line at all (missing field case).
write_req_no_files() {
  local path="$1"
  local id="$2"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** backlog
**Created:** 2026-05-21
**Layer:** none
**Depends on:**

## Task

No files.
EOF
}

# Write a working/ REQ (stamped) at $1 for id $2 with files $3.
write_working_req() {
  local path="$1"
  local id="$2"
  local files="$3"
  cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** test-other-agent
**Claimed at:** 2026-05-21T00:00:00Z
**Heartbeat:** 2026-05-21T00:00:00Z
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:**
EOF
}

setup_fixture() {
  TMP="$(mktemp -d -t check-footprint-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Run check-footprint.sh inside $TMP. Stores RC_, STDOUT_, STDERR_.
run_check() {
  local req_path="$1"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$CHECKER" "$req_path" > "$out_file" 2> "$err_file" )
  RC_=$?
  STDOUT_="$(cat "$out_file" 2>/dev/null || true)"
  STDERR_="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: no overlap — empty stdout, exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="no-overlap"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/a.ts"
: > "$TMP/src/b.ts"
write_working_req "$TMP/.do-work/working/REQ-001-other.md" "REQ-001" "src/a.ts"
write_req "$TMP/.do-work/REQ-002-target.md" "REQ-002" "src/b.ts"
run_check ".do-work/REQ-002-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: single overlap — one slot reported
# ----------------------------------------------------------------------
CURRENT_CASE="single-overlap"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/foo.ts"
: > "$TMP/src/bar.ts"
write_working_req "$TMP/.do-work/working/REQ-010-other.md" "REQ-010" "src/foo.ts"
write_req "$TMP/.do-work/REQ-011-target.md" "REQ-011" "src/foo.ts, src/bar.ts"
run_check ".do-work/REQ-011-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "REQ-010" "$STDOUT_" "$CURRENT_CASE names overlap slot"
assert_contains "src/foo.ts" "$STDOUT_" "$CURRENT_CASE names overlap path"
assert_not_contains "src/bar.ts" "$STDOUT_" "$CURRENT_CASE non-overlapping path not listed"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: multi-slot overlap — both slots reported, one line each
# ----------------------------------------------------------------------
CURRENT_CASE="multi-slot-overlap"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/a.ts"
: > "$TMP/src/b.ts"
: > "$TMP/src/c.ts"
write_working_req "$TMP/.do-work/working/REQ-020-one.md" "REQ-020" "src/a.ts"
write_working_req "$TMP/.do-work/working/REQ-021-two.md" "REQ-021" "src/b.ts"
write_req "$TMP/.do-work/REQ-022-target.md" "REQ-022" "src/a.ts, src/b.ts, src/c.ts"
run_check ".do-work/REQ-022-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "REQ-020" "$STDOUT_" "$CURRENT_CASE first slot listed"
assert_contains "REQ-021" "$STDOUT_" "$CURRENT_CASE second slot listed"
# One slot per line: should be exactly 2 non-empty lines.
line_count="$(printf '%s\n' "$STDOUT_" | grep -c '^REQ-' || true)"
assert_eq "2" "$line_count" "$CURRENT_CASE two lines"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: glob expansion — **, *, ? all match correctly
# ----------------------------------------------------------------------
CURRENT_CASE="glob-expansion-double-star"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src/deep/nested"
: > "$TMP/src/deep/nested/a.ts"
: > "$TMP/src/top.ts"
# Working slot uses **/*.ts which should match all .ts under src/ recursively.
write_working_req "$TMP/.do-work/working/REQ-030-other.md" "REQ-030" "src/**/*.ts"
write_req "$TMP/.do-work/REQ-031-target.md" "REQ-031" "src/deep/nested/a.ts"
run_check ".do-work/REQ-031-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "REQ-030" "$STDOUT_" "$CURRENT_CASE ** glob detected overlap"
assert_contains "src/deep/nested/a.ts" "$STDOUT_" "$CURRENT_CASE intersect path listed"
teardown_fixture

CURRENT_CASE="glob-expansion-single-star"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src/sub"
: > "$TMP/src/foo.ts"
: > "$TMP/src/sub/deep.ts"
# Working slot uses src/*.ts — should only match direct children.
write_working_req "$TMP/.do-work/working/REQ-040-other.md" "REQ-040" "src/*.ts"
write_req "$TMP/.do-work/REQ-041-target.md" "REQ-041" "src/foo.ts"
run_check ".do-work/REQ-041-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "REQ-040" "$STDOUT_" "$CURRENT_CASE * glob detected overlap on direct child"
# Now a different target referencing only the nested file should NOT overlap.
write_req "$TMP/.do-work/REQ-042-target.md" "REQ-042" "src/sub/deep.ts"
run_check ".do-work/REQ-042-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc nested"
assert_not_contains "REQ-040" "$STDOUT_" "$CURRENT_CASE * glob does not match nested child"
teardown_fixture

CURRENT_CASE="glob-expansion-question-mark"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/foo1.ts"
: > "$TMP/src/foo12.ts"
# Working slot uses src/foo?.ts — should match foo1.ts but not foo12.ts.
write_working_req "$TMP/.do-work/working/REQ-050-other.md" "REQ-050" "src/foo?.ts"
write_req "$TMP/.do-work/REQ-051-target.md" "REQ-051" "src/foo1.ts"
run_check ".do-work/REQ-051-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "REQ-050" "$STDOUT_" "$CURRENT_CASE ? glob matched single char"

write_req "$TMP/.do-work/REQ-052-target.md" "REQ-052" "src/foo12.ts"
run_check ".do-work/REQ-052-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc multi-char"
assert_not_contains "REQ-050" "$STDOUT_" "$CURRENT_CASE ? glob does not match two chars"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: empty **Files:** field — silent empty output
# ----------------------------------------------------------------------
CURRENT_CASE="empty-footprint"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/a.ts"
write_working_req "$TMP/.do-work/working/REQ-060-other.md" "REQ-060" "src/a.ts"
# Target has an empty Files line.
write_req "$TMP/.do-work/REQ-061-target.md" "REQ-061" ""
run_check ".do-work/REQ-061-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE empty stdout regardless of other slots"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: missing **Files:** field entirely — silent empty output
# ----------------------------------------------------------------------
CURRENT_CASE="missing-field"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/a.ts"
write_working_req "$TMP/.do-work/working/REQ-070-other.md" "REQ-070" "src/a.ts"
write_req_no_files "$TMP/.do-work/REQ-071-target.md" "REQ-071"
run_check ".do-work/REQ-071-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE empty stdout when no Files field"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: self-overlap excluded — input REQ in working/ does not match itself
# ----------------------------------------------------------------------
CURRENT_CASE="self-overlap-excluded"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/src"
: > "$TMP/src/a.ts"
# Place target in working/ (e.g., REQ-158 commit-time check pattern).
write_working_req "$TMP/.do-work/working/REQ-080-target.md" "REQ-080" "src/a.ts"
run_check ".do-work/working/REQ-080-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE self not reported"

# Now add a different slot that DOES overlap — it should be reported.
write_working_req "$TMP/.do-work/working/REQ-081-other.md" "REQ-081" "src/a.ts"
run_check ".do-work/working/REQ-080-target.md"
assert_eq "0" "$RC_" "$CURRENT_CASE rc with peer"
assert_contains "REQ-081" "$STDOUT_" "$CURRENT_CASE peer slot reported"
assert_not_contains "REQ-080" "$STDOUT_" "$CURRENT_CASE self still excluded"
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
