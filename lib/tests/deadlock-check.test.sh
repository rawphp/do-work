#!/usr/bin/env bash
# Tests for lib/deadlock-check.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2 and Linux bash >= 4.
#
# Acceptance criteria:
#   - At most one condition reported (first match in trigger order).
#   - Fingerprint is stable for same signal + same live-slot count + same hash.
#   - Cases cover: no-deadlock (empty backlog + empty working/),
#                  no-deadlock (recent commit), no-progress-stall,
#                  mass-stale-slots, runtime-cycle, first-trigger-wins,
#                  fingerprint stability.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DEADLOCK="$LIB_DIR/deadlock-check.sh"
SCAN_STALE="$LIB_DIR/scan-stale.sh"
CYCLE_CHECK="$LIB_DIR/cycle-check.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

assert_not_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: unexpected substring '$needle' in '$haystack'" ;;
    *) : ;;
  esac
}

# Compute an ISO-8601 UTC timestamp offset by N seconds from now (BSD + GNU).
iso_at_offset() {
  local offset="$1"
  if date -u -v+0S +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    if [ "$offset" -lt 0 ]; then
      local abs=$(( -offset ))
      date -u -v-${abs}S +%Y-%m-%dT%H:%M:%SZ
    else
      date -u -v+${offset}S +%Y-%m-%dT%H:%M:%SZ
    fi
  else
    date -u -d "@$(( $(date -u +%s) + offset ))" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# Write a minimal backlog REQ file. Args: $1=path, $2=req-id, $3=ur
write_backlog_req() {
  local path="$1" id="$2" ur="$3"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.sh
**Depends on:**
EOF
}

# Write a working/ REQ with a given heartbeat ISO timestamp.
# Args: $1=path, $2=id, $3=heartbeat-iso (empty = omit line)
write_working_req() {
  local path="$1" id="$2" hb="$3"
  if [ -n "$hb" ]; then
    cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T00:00:00Z
**Heartbeat:** $hb
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
**Depends on:**
EOF
  else
    cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** in-progress
**Depends on:**
EOF
  fi
}

setup_fixture() {
  TMP="$(mktemp -d -t deadlock-check-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working"
  mkdir -p "$TMP/.do-work/archive"
  # Initialize a git repo so git log works; make a recent commit.
  git -C "$TMP" init -q
  git -C "$TMP" config user.email "test@test.com"
  git -C "$TMP" config user.name "Test"
  touch "$TMP/.do-work/.gitkeep"
  git -C "$TMP" add .
  # Fail loudly if the fixture can't be prepared — a missing init commit would
  # silently skew every commit-age assertion downstream.
  if ! GIT_COMMITTER_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         git -C "$TMP" commit -q --allow-empty -m "init"; then
    fail "setup_fixture: initial git commit failed"
  fi
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Age the most recent commit to OLD_DATE so `git log --since` ignores it.
age_last_commit() {
  local old_date="$1"
  # Surface a failed amend — a stale commit date is what the no-progress-stall
  # cases hinge on, so a silent failure here would make them misleading.
  if ! GIT_COMMITTER_DATE="$old_date" GIT_AUTHOR_DATE="$old_date" \
         git -C "$TMP" commit -q --allow-empty --amend --no-edit; then
    fail "age_last_commit: amend to $old_date failed"
  fi
}

# Run deadlock-check.sh inside $TMP, wiring the real scan-stale / cycle-check
# helpers via env overrides. Stores RC and OUTPUT (stdout only — the script
# emits its detection block on stdout and nothing on no-deadlock).
run_deadlock() {
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && env \
      SCAN_STALE_CMD="$SCAN_STALE" \
      CYCLE_CHECK_CMD="$CYCLE_CHECK" \
      "$DEADLOCK" > "$out_file" 2>/dev/null )
  RC=$?
  OUTPUT="$(cat "$out_file" 2>/dev/null || true)"
  rm -f "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: no deadlock — empty backlog and empty working/
# ----------------------------------------------------------------------
CURRENT_CASE="no-deadlock-empty"
CASES=$((CASES + 1))
setup_fixture
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_eq "" "$OUTPUT" "$CURRENT_CASE empty output"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: no deadlock — backlog has REQs but there is a recent commit
# ----------------------------------------------------------------------
CURRENT_CASE="no-deadlock-recent-commit"
CASES=$((CASES + 1))
setup_fixture
write_backlog_req "$TMP/.do-work/REQ-001-a.md" "REQ-001" "UR-001"
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_eq "" "$OUTPUT" "$CURRENT_CASE empty output"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: no-progress-stall — backlog non-empty, no commits in 5m window
# ----------------------------------------------------------------------
CURRENT_CASE="no-progress-stall"
CASES=$((CASES + 1))
setup_fixture
write_backlog_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001"
age_last_commit "$(iso_at_offset -360)"   # 6 minutes ago
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "deadlock-detected" "$OUTPUT" "$CURRENT_CASE detected"
assert_contains "signal: no-progress-stall" "$OUTPUT" "$CURRENT_CASE signal"
assert_contains "fingerprint: deadlock:no-progress-stall:" "$OUTPUT" "$CURRENT_CASE fingerprint"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: mass-stale-slots — all working/ slots are stale (recent commit
# keeps no-progress-stall from firing first).
# ----------------------------------------------------------------------
CURRENT_CASE="mass-stale-slots"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-010-a.md" "REQ-010" "$(iso_at_offset -3600)"
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "deadlock-detected" "$OUTPUT" "$CURRENT_CASE detected"
assert_contains "signal: mass-stale-slots" "$OUTPUT" "$CURRENT_CASE signal"
assert_contains "fingerprint: deadlock:mass-stale-slots:" "$OUTPUT" "$CURRENT_CASE fingerprint"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: runtime-cycle — cycle-check.sh exits 1 on a backlog cycle.
# ----------------------------------------------------------------------
CURRENT_CASE="runtime-cycle"
CASES=$((CASES + 1))
setup_fixture
cat > "$TMP/.do-work/REQ-020-a.md" <<EOF
# REQ-020: Test

**UR:** UR-001
**Status:** backlog
**Depends on:** REQ-021
EOF
cat > "$TMP/.do-work/REQ-021-b.md" <<EOF
# REQ-021: Test

**UR:** UR-001
**Status:** backlog
**Depends on:** REQ-020
EOF
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "deadlock-detected" "$OUTPUT" "$CURRENT_CASE detected"
assert_contains "signal: runtime-cycle" "$OUTPUT" "$CURRENT_CASE signal"
assert_contains "fingerprint: deadlock:runtime-cycle:" "$OUTPUT" "$CURRENT_CASE fingerprint"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: first trigger wins — no-progress-stall reported even when
# mass-stale is also true.
# ----------------------------------------------------------------------
CURRENT_CASE="first-trigger-wins"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-030-a.md" "REQ-030" "$(iso_at_offset -3600)"
write_backlog_req "$TMP/.do-work/REQ-031-b.md" "REQ-031" "UR-001"
age_last_commit "$(iso_at_offset -360)"
run_deadlock
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "deadlock-detected" "$OUTPUT" "$CURRENT_CASE detected"
assert_contains "signal: no-progress-stall" "$OUTPUT" "$CURRENT_CASE signal wins"
assert_not_contains "mass-stale-slots" "$OUTPUT" "$CURRENT_CASE mass-stale suppressed"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: fingerprint stability — same state → same fingerprint.
# ----------------------------------------------------------------------
CURRENT_CASE="fingerprint-stable"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-040-a.md" "REQ-040" "$(iso_at_offset -3600)"
run_deadlock
fp1="$(printf '%s\n' "$OUTPUT" | grep "^fingerprint:" | head -1)"
run_deadlock
fp2="$(printf '%s\n' "$OUTPUT" | grep "^fingerprint:" | head -1)"
if [ -z "$fp1" ]; then
  fail "$CURRENT_CASE: no fingerprint emitted"
fi
assert_eq "$fp1" "$fp2" "$CURRENT_CASE fingerprint stable across runs"
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
