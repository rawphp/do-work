#!/usr/bin/env bash
# Tests for lib/pick-req.sh — pending-only dep filter cases.
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# Covers:
#   (a) pending-only dep → candidate is rejected
#   (b) archive-only dep → candidate is claimable (unchanged behaviour)
#   (c) dep absent from archive/ → rejected (dep:<id> on stderr)

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
PICKER="$LIB_DIR/pick-req.sh"

FAILED=0
CASES=0
CURRENT_CASE=""
TMP=""

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

# Set up a throwaway fixture dir with .do-work/archive/ and .do-work/pending/.
setup_fixture() {
  TMP="$(mktemp -d -t pick-req-pending-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive"
  mkdir -p "$TMP/.do-work/pending"
}

# Tear down the fixture.
teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  TMP=""
}

# Write a candidate REQ in the backlog (.do-work/REQ-NNN-slug.md).
write_candidate() {
  local id="$1"
  local deps="$2"
  local slug="${id}-$(echo "$id" | tr '[:upper:]' '[:lower:]')-test"
  local path="$TMP/.do-work/${slug}.md"
  cat > "$path" <<EOF
# ${id}: Test candidate

**UR:** UR-001
**Status:** backlog
**Created:** 2026-06-12
**Layer:** none
**Files:** lib/pick-req.sh
**Depends on:** $deps
EOF
  echo "$path"
}

# Write a stub dep REQ file (just needs to exist as a matching file).
write_stub() {
  local path="$1"
  local id="$2"
  cat > "$path" <<EOF
# $id: Stub REQ

**UR:** UR-001
**Status:** done
**Created:** 2026-06-12
**Layer:** none
**Files:** lib/pick-req.sh
**Depends on:**
EOF
}

# Run pick-req.sh from inside the fixture dir so .do-work is found via CWD.
run_picker() {
  local scope="${1:-any}"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$PICKER" "$scope" "test.agent" > "$out_file" 2> "$err_file" )
  PICK_RC=$?
  PICK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  PICK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# -----------------------------------------------------------------------
# Case (a): pending-only dep → candidate is rejected
# -----------------------------------------------------------------------
CURRENT_CASE="pending-only-dep-rejected"
CASES=$((CASES + 1))
setup_fixture
# Dep parked in pending/ only — not in archive/
write_stub "$TMP/.do-work/pending/REQ-501-parked.md" "REQ-501"
# Candidate depending on REQ-501
write_candidate "REQ-502" "REQ-501"
run_picker "any"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE exit code (1 = nothing claimable)"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE no candidate returned"
assert_contains "dep:REQ-501" "$PICK_STDERR" "$CURRENT_CASE dep rejection on stderr"
teardown_fixture

# -----------------------------------------------------------------------
# Case (b): archive-only dep → candidate is claimable (unchanged behaviour)
# -----------------------------------------------------------------------
CURRENT_CASE="archive-only-dep-claimable"
CASES=$((CASES + 1))
setup_fixture
# Dep archived only
write_stub "$TMP/.do-work/archive/REQ-503-done.md" "REQ-503"
# Candidate depending on REQ-503
write_candidate "REQ-504" "REQ-503"
run_picker "any"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE exit code (0 = found claimable)"
assert_contains "REQ-504" "$PICK_STDOUT" "$CURRENT_CASE candidate path returned"
assert_not_contains "dep:REQ-503" "$PICK_STDERR" "$CURRENT_CASE no dep rejection on stderr"
teardown_fixture

# -----------------------------------------------------------------------
# Case (c): dep absent from archive/ → rejected
# -----------------------------------------------------------------------
CURRENT_CASE="dep-absent-from-both-rejected"
CASES=$((CASES + 1))
setup_fixture
# No stub written — REQ-505 is in neither archive/ nor pending/
write_candidate "REQ-506" "REQ-505"
run_picker "any"
assert_eq "1" "$PICK_RC" "$CURRENT_CASE exit code (1 = nothing claimable)"
assert_eq "" "$PICK_STDOUT" "$CURRENT_CASE no candidate returned"
assert_contains "dep:REQ-505" "$PICK_STDERR" "$CURRENT_CASE dep rejection on stderr"
teardown_fixture

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
