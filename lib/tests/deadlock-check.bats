#!/usr/bin/env bats
# Tests for lib/deadlock-check.sh
# Bats test suite (bats-core >= 1.x).
# Compatible with macOS bash 3.2 and Linux bash >= 4.
#
# Acceptance criteria:
#   - At most one condition reported (first match in trigger order).
#   - Fingerprint is stable for same signal + same live-slot count + same hash.
#   - Tests cover: no-deadlock (empty backlog + empty working/),
#                  no-deadlock (active commits), no-progress-stall,
#                  mass-stale-slots, runtime-cycle.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
DEADLOCK="$SCRIPT_DIR/deadlock-check.sh"
SCAN_STALE="$SCRIPT_DIR/scan-stale.sh"
CYCLE_CHECK="$SCRIPT_DIR/cycle-check.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write a minimal backlog REQ file.
# Args: $1=path, $2=req-id, $3=ur
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

# Compute an ISO-8601 UTC timestamp offset by N seconds from now (BSD+GNU).
iso_at_offset() {
  local offset="$1"
  if date -u -v+0S +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    # BSD date (macOS)
    if [ "$offset" -lt 0 ]; then
      local abs=$(( -offset ))
      date -u -v-${abs}S +%Y-%m-%dT%H:%M:%SZ
    else
      date -u -v+${offset}S +%Y-%m-%dT%H:%M:%SZ
    fi
  else
    # GNU date
    date -u -d "@$(( $(date -u +%s) + offset ))" +%Y-%m-%dT%H:%M:%SZ
  fi
}

setup() {
  TMP="$(mktemp -d -t deadlock-check-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working"
  mkdir -p "$TMP/.do-work/archive"
  # Initialize a git repo so git log works; make a commit 1 second ago
  git -C "$TMP" init -q
  git -C "$TMP" config user.email "test@test.com"
  git -C "$TMP" config user.name "Test"
  # Create a placeholder file and commit it
  touch "$TMP/.do-work/.gitkeep"
  git -C "$TMP" add .
  GIT_COMMITTER_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    git -C "$TMP" commit -q --allow-empty -m "init" 2>/dev/null || true
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

run_deadlock() {
  # Run the script from $TMP so relative .do-work/ paths resolve correctly.
  # Pass overrides via env vars: SCAN_STALE_CMD, CYCLE_CHECK_CMD
  cd "$TMP"
  run env \
    SCAN_STALE_CMD="$SCAN_STALE" \
    CYCLE_CHECK_CMD="$CYCLE_CHECK" \
    "$DEADLOCK"
}

# ---------------------------------------------------------------------------
# Test 1: No deadlock — empty backlog and empty working/
# ---------------------------------------------------------------------------
@test "no deadlock — empty backlog and empty working/" {
  # No backlog REQs, no working slots → empty stdout
  run_deadlock
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test 2: No deadlock — backlog has REQs but there is a recent commit
# ---------------------------------------------------------------------------
@test "no deadlock — backlog has REQs with recent git commit" {
  write_backlog_req "$TMP/.do-work/REQ-001-a.md" "REQ-001" "UR-001"
  # The git repo was initialized with a commit just now in setup() → recent
  run_deadlock
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test 3: no-progress-stall — backlog non-empty, no recent commits
# ---------------------------------------------------------------------------
@test "no-progress-stall — backlog non-empty, no git commits in 5 min window" {
  write_backlog_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001"
  # Amend the commit date to be old (6 minutes ago) so git log --since=5m returns nothing.
  # We do this by resetting the commit with an old date.
  OLD_DATE="$(iso_at_offset -360)"   # 6 minutes ago
  cd "$TMP"
  git -C "$TMP" commit -q --allow-empty --amend --no-edit \
    --date="$OLD_DATE" \
    -c "committer.date=$OLD_DATE" 2>/dev/null || \
  GIT_COMMITTER_DATE="$OLD_DATE" GIT_AUTHOR_DATE="$OLD_DATE" \
    git -C "$TMP" commit -q --allow-empty --amend --no-edit 2>/dev/null || true
  run_deadlock
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deadlock-detected"
  echo "$output" | grep -q "signal: no-progress-stall"
  echo "$output" | grep -q "fingerprint: deadlock:no-progress-stall:"
}

# ---------------------------------------------------------------------------
# Test 4: mass-stale-slots — all working/ slots are stale
# ---------------------------------------------------------------------------
@test "mass-stale-slots — all working slots are stale" {
  # One stale working slot (heartbeat 1 hour ago)
  STALE_ISO="$(iso_at_offset -3600)"
  write_working_req "$TMP/.do-work/working/REQ-010-a.md" "REQ-010" "$STALE_ISO"
  # Make git commit old so no-progress-stall is also triggered, but mass-stale should
  # be the signal when stale count == slot count regardless.
  # Actually: per REQ, first trigger wins. But mass-stale is trigger #2.
  # We need no-progress-stall to NOT fire, so make a fresh commit.
  # The setup() commit is fresh, so no-progress-stall won't fire.
  # mass-stale is trigger 2: scan-stale count == working slot count.
  run_deadlock
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deadlock-detected"
  echo "$output" | grep -q "signal: mass-stale-slots"
  echo "$output" | grep -q "fingerprint: deadlock:mass-stale-slots:"
}

# ---------------------------------------------------------------------------
# Test 5: runtime-cycle — cycle-check exits 1
# ---------------------------------------------------------------------------
@test "runtime-cycle — cycle-check.sh exits 1" {
  # Create a cycle in the .do-work/ backlog to trigger cycle-check exit 1.
  # REQ-020 depends on REQ-021, REQ-021 depends on REQ-020.
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
  # Both are in the backlog, no working slots → no-progress-stall could fire IF no recent commit.
  # setup() made a recent commit, so no-progress-stall won't fire.
  # mass-stale: 0 stale, 0 working slots → stale == slot_count only if both are 0;
  # but we need a working slot for mass-stale to trigger. No working slots → mass-stale won't fire.
  # runtime-cycle: cycle-check exits 1 → fires.
  run_deadlock
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deadlock-detected"
  echo "$output" | grep -q "signal: runtime-cycle"
  echo "$output" | grep -q "fingerprint: deadlock:runtime-cycle:"
}

# ---------------------------------------------------------------------------
# Test 6: only first trigger reported (no-progress-stall wins over mass-stale)
# ---------------------------------------------------------------------------
@test "first trigger wins — no-progress-stall reported even when mass-stale also true" {
  # Stale working slot (mass-stale trigger)
  STALE_ISO="$(iso_at_offset -3600)"
  write_working_req "$TMP/.do-work/working/REQ-030-a.md" "REQ-030" "$STALE_ISO"
  # Also put a backlog REQ so no-progress-stall can fire
  write_backlog_req "$TMP/.do-work/REQ-031-b.md" "REQ-031" "UR-001"
  # Make git commit old → no-progress-stall fires first
  OLD_DATE="$(iso_at_offset -360)"
  cd "$TMP"
  GIT_COMMITTER_DATE="$OLD_DATE" GIT_AUTHOR_DATE="$OLD_DATE" \
    git -C "$TMP" commit -q --allow-empty --amend --no-edit 2>/dev/null || true
  run_deadlock
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deadlock-detected"
  echo "$output" | grep -q "signal: no-progress-stall"
  # Should NOT contain mass-stale-slots since first trigger wins
  ! echo "$output" | grep -q "mass-stale-slots"
}

# ---------------------------------------------------------------------------
# Test 7: fingerprint stability — same inputs produce same fingerprint
# ---------------------------------------------------------------------------
@test "fingerprint is stable across two runs with same state" {
  # Stale working slot to trigger mass-stale-slots
  STALE_ISO="$(iso_at_offset -3600)"
  write_working_req "$TMP/.do-work/working/REQ-040-a.md" "REQ-040" "$STALE_ISO"
  # setup() has a fresh commit → no-progress-stall won't fire

  run_deadlock
  FIRST_OUTPUT="$output"
  fp1="$(echo "$FIRST_OUTPUT" | grep "^fingerprint:" | head -1)"

  run_deadlock
  SECOND_OUTPUT="$output"
  fp2="$(echo "$SECOND_OUTPUT" | grep "^fingerprint:" | head -1)"

  [ -n "$fp1" ]
  [ "$fp1" = "$fp2" ]
}
