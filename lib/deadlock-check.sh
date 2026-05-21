#!/usr/bin/env bash
# deadlock-check.sh — diagnose a deadlock in the do-work parallel coordination
# layer and print a structured report when one is detected.
#
# Usage: deadlock-check.sh   (no args; run from project root containing .do-work/)
#
# Output (stdout):
#   Empty          — no deadlock detected.
#   Structured     — one of the three trigger conditions fired:
#
#     deadlock-detected
#     signal: <no-progress-stall | mass-stale-slots | runtime-cycle>
#     live-slots: <count>
#     stale-slots: <count>
#     backlog-size: <count>
#     last-commit-age: <seconds>
#     diagnosis: <short text>
#     fingerprint: deadlock:<signal>:<live-slots>:<hash>
#
# Trigger conditions (first match wins):
#   1. no-progress-stall  — backlog non-empty OR working/ non-empty, AND no
#                           git commits touching .do-work/ in the last 5 minutes.
#   2. mass-stale-slots   — scan-stale.sh reports as many stale slots as there
#                           are working/ slots (all slots are stale).
#   3. runtime-cycle      — cycle-check.sh exits 1 (dependency cycle detected).
#
# Fingerprint is stable for the same (signal, live-slot count, in-flight REQ ids).
#
# Exit codes:
#   0  Check completed (deadlock or not — use stdout presence to distinguish).
#   1  Fatal internal error.
#
# Environment overrides (for testing):
#   SCAN_STALE_CMD   — path to scan-stale.sh (default: sibling in lib/)
#   CYCLE_CHECK_CMD  — path to cycle-check.sh (default: sibling in lib/)
#
# Compatible with macOS bash 3.2 (BSD date) and Linux bash >= 4 (GNU date).
# Standard POSIX tools only (grep, sed, awk, git).

set -u

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

SCAN_STALE="${SCAN_STALE_CMD:-$SELF_DIR/scan-stale.sh}"
CYCLE_CHECK="${CYCLE_CHECK_CMD:-$SELF_DIR/cycle-check.sh}"

DOWORK=".do-work"
WORKING="$DOWORK/working"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Count lines in a string (handles empty string → 0).
count_lines() {
  printf '%s' "$1" | grep -c '' 2>/dev/null || printf '0'
}

# Return epoch of the most-recent git commit touching .do-work/ (in this repo).
# Prints epoch seconds; prints 0 if no commits or git unavailable.
last_commit_epoch() {
  local epoch
  epoch="$(git log -1 --format="%ct" -- "$DOWORK" 2>/dev/null || true)"
  if [ -z "$epoch" ] || [ "$epoch" = "" ]; then
    # Fallback: any commit in repo
    epoch="$(git log -1 --format="%ct" 2>/dev/null || true)"
  fi
  printf '%s' "${epoch:-0}"
}

# Cross-platform epoch (BSD + GNU date).
now_epoch() {
  date -u +%s
}

# Simple hash of a string. Uses cksum (always available on POSIX).
simple_hash() {
  printf '%s' "$1" | cksum | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# Gather state
# ---------------------------------------------------------------------------

NOW="$(now_epoch)"

# Count backlog REQs (.do-work/REQ-*.md — not in working/ or archive/).
shopt -s nullglob 2>/dev/null || true
set +u
BACKLOG_FILES=( "$DOWORK"/REQ-*.md )
set -u
BACKLOG_SIZE="${#BACKLOG_FILES[@]}"

# Count working/ slots.
WORKING_TOTAL=0
WORKING_SLOT_IDS=""
if [ -d "$WORKING" ]; then
  set +u
  WORKING_FILES=( "$WORKING"/REQ-*.md )
  set -u
  WORKING_TOTAL="${#WORKING_FILES[@]}"
  # Collect in-flight REQ ids for fingerprint.
  if [ "$WORKING_TOTAL" -gt 0 ]; then
    for _wf in "${WORKING_FILES[@]}"; do
      [ -e "$_wf" ] || continue
      _base="$(basename "$_wf")"
      _id="$(printf '%s' "$_base" | awk '{
        if (match($0, /^REQ-M[0-9]+-[0-9]+/)) print substr($0,RSTART,RLENGTH)
        else if (match($0, /^REQ-[0-9]+/))     print substr($0,RSTART,RLENGTH)
      }')"
      WORKING_SLOT_IDS="${WORKING_SLOT_IDS}${_id}:"
    done
  fi
fi

# Get stale slot count via scan-stale.sh (call from project root).
STALE_OUTPUT="$("$SCAN_STALE" 2>/dev/null || true)"
STALE_COUNT=0
if [ -n "$STALE_OUTPUT" ]; then
  STALE_COUNT="$(printf '%s\n' "$STALE_OUTPUT" | grep -c '' 2>/dev/null || true)"
fi

LIVE_SLOTS=$(( WORKING_TOTAL - STALE_COUNT ))
[ "$LIVE_SLOTS" -lt 0 ] && LIVE_SLOTS=0

# Age of last commit touching .do-work/
LAST_COMMIT_EPOCH="$(last_commit_epoch)"
if [ "$LAST_COMMIT_EPOCH" -gt 0 ] 2>/dev/null; then
  LAST_COMMIT_AGE=$(( NOW - LAST_COMMIT_EPOCH ))
else
  # No commits at all — treat as very old.
  LAST_COMMIT_AGE=999999
fi

# ---------------------------------------------------------------------------
# Evaluate trigger conditions in order (first match wins)
# ---------------------------------------------------------------------------
SIGNAL=""
DIAGNOSIS=""

# ---- Trigger 1: no-progress-stall ----------------------------------------
# Backlog OR working non-empty AND no commits to .do-work/ in last 5 minutes.
if [ "$SIGNAL" = "" ]; then
  if [ "$BACKLOG_SIZE" -gt 0 ] || [ "$WORKING_TOTAL" -gt 0 ]; then
    if [ "$LAST_COMMIT_AGE" -gt 300 ]; then
      SIGNAL="no-progress-stall"
      DIAGNOSIS="No git commits to .do-work/ in the last 5 minutes while work is pending."
    fi
  fi
fi

# ---- Trigger 2: mass-stale-slots ------------------------------------------
# scan-stale count equals working/ slot count (all slots dead).
# Only meaningful when there is at least one working slot.
if [ "$SIGNAL" = "" ]; then
  if [ "$WORKING_TOTAL" -gt 0 ] && [ "$STALE_COUNT" -eq "$WORKING_TOTAL" ]; then
    SIGNAL="mass-stale-slots"
    DIAGNOSIS="All $WORKING_TOTAL working slot(s) are stale (heartbeat expired). No live agents."
  fi
fi

# ---- Trigger 3: runtime-cycle ---------------------------------------------
# cycle-check.sh exits 1.
if [ "$SIGNAL" = "" ]; then
  if ! "$CYCLE_CHECK" >/dev/null 2>&1; then
    SIGNAL="runtime-cycle"
    DIAGNOSIS="Dependency cycle detected in REQ graph by cycle-check.sh."
  fi
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ -z "$SIGNAL" ]; then
  # No deadlock — empty stdout.
  exit 0
fi

# Build fingerprint: deadlock:<signal>:<live-slots>:<hash-of-in-flight-ids>
FP_HASH="$(simple_hash "${WORKING_SLOT_IDS}")"
FINGERPRINT="deadlock:${SIGNAL}:${LIVE_SLOTS}:${FP_HASH}"

printf 'deadlock-detected\n'
printf 'signal: %s\n'            "$SIGNAL"
printf 'live-slots: %s\n'        "$LIVE_SLOTS"
printf 'stale-slots: %s\n'       "$STALE_COUNT"
printf 'backlog-size: %s\n'      "$BACKLOG_SIZE"
printf 'last-commit-age: %s\n'   "$LAST_COMMIT_AGE"
printf 'diagnosis: %s\n'         "$DIAGNOSIS"
printf 'fingerprint: %s\n'       "$FINGERPRINT"

exit 0
