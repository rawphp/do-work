#!/usr/bin/env bash
# Integration-level regression test for the Stage B serialization invariant.
#
# Complements lib/tests/stage-b-lock.test.sh, which tests the lock *primitive*
# in isolation (mutual exclusion, auto-release, portability). This suite fires
# two concurrent "Stage B integration" sequences against a single shared
# resource and proves the invariant at the integration level:
#
#   1. Positive — under lib/stage-b-lock.sh with-lock, two concurrent
#      critical sections SERIALIZE: one full START..END pair completes before
#      the other's START begins (no interleave).
#
#   2. Negative — the SAME two critical sections run WITHOUT the lock wrapper
#      and DO interleave. This is the "guards, not decorates" proof: it shows
#      the assertion actually detects non-serialization, so the positive case
#      cannot silently pass if the lock is later removed or bypassed.
#
# The shared log file stands in for the integration base (the 4a-4d merge
# sequence); appending to it under the lock models the single-writer contract.
#
# REQ: REQ-016 (UR-005 / F4 regression)
# Plain bash (no bats). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
LOCK_SCRIPT="$LIB_DIR/stage-b-lock.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

# Per-test workspace. SHARED_LOG models the integration base; STATE_DIR holds
# the lock file, isolated from any real do-work run.
WORK_DIR="$(mktemp -d -t stage-b-serial.XXXXXX)"
SHARED_LOG="$WORK_DIR/integration.log"
STATE_DIR="$WORK_DIR/state"
mkdir -p "$STATE_DIR"

trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

# Markers written into SHARED_LOG by each pseudo-integration. Distinct literal
# strings (none a substring of another) keep the case-pattern matching exact.
A_START="A-START"
A_END="A-END"
B_START="B-START"
B_END="B-END"

# interleave_detected <content>
# Returns 0 (true) when the two critical sections overlapped in time — i.e.
# one process wrote its START while the other was inside its own START..END
# window. Accepts either direction of interleave.
interleave_detected() {
  local content="$1"
  # Signature A: A entered, then B entered before A ended.
  case "$content" in
    *"$A_START"*"$B_START"*"$A_END"*) return 0 ;;
  esac
  # Signature B: B entered, then A entered before B ended.
  case "$content" in
    *"$B_START"*"$A_START"*"$B_END"*) return 0 ;;
  esac
  return 1
}

# oneline_log — print the shared log as a single pipe-separated line for
# readable failure messages (newlines becomes '|').
oneline_log() {
  tr '\n' '|' < "$SHARED_LOG"
}

# Critical-section durations. The body sleep is the stand-in for the merge +
# retry window; the head-start sleep gives the first process time to enter its
# section before the second is launched.
CS_SLEEP=2
HEAD_START=0.5

# ---- Case 1: positive — concurrent integrations serialize under the lock ----
CURRENT_CASE="positive-serializes-under-lock"
CASES=$((CASES + 1))

rm -f "$SHARED_LOG"

# Process A: Stage B integration under the lock.
( STATE_DIR="$STATE_DIR" bash "$LOCK_SCRIPT" with-lock bash -c \
    "echo $A_START >> \"$SHARED_LOG\"; sleep $CS_SLEEP; echo $A_END >> \"$SHARED_LOG\"" ) &
PID_A=$!

# Let A acquire the lock and enter its critical section.
sleep "$HEAD_START"

# Process B: same integration under the lock — must wait for A to release.
( STATE_DIR="$STATE_DIR" bash "$LOCK_SCRIPT" with-lock bash -c \
    "echo $B_START >> \"$SHARED_LOG\"; sleep $CS_SLEEP; echo $B_END >> \"$SHARED_LOG\"" ) &
PID_B=$!

wait $PID_A 2>/dev/null || true
wait $PID_B 2>/dev/null || true

if [ ! -f "$SHARED_LOG" ]; then
  fail "$CURRENT_CASE: shared log not created"
else
  CONTENT="$(cat "$SHARED_LOG")"
  if interleave_detected "$CONTENT"; then
    fail "$CURRENT_CASE: critical sections interleaved under the lock (expected serialization). Log: $(oneline_log)"
  fi
  # Sanity: every marker landed exactly once — both integrations completed
  # and neither was silently dropped.
  for m in "$A_START" "$A_END" "$B_START" "$B_END"; do
    case "$CONTENT" in
      *"$m"*) : ;;
      *) fail "$CURRENT_CASE: missing marker '$m'. Log: $(oneline_log)" ;;
    esac
  done
fi

# ---- Case 2: negative — same sections interleave WITHOUT the lock ----------
# Proves the assertion in case 1 actually detects non-serialization. If the
# lock were removed/bypassed, this is the failure signature we would see.
CURRENT_CASE="negative-interleaves-without-lock"
CASES=$((CASES + 1))

rm -f "$SHARED_LOG"

# Process A: raw critical section, NO lock wrapper.
( bash -c "echo $A_START >> \"$SHARED_LOG\"; sleep $CS_SLEEP; echo $A_END >> \"$SHARED_LOG\"" ) &
PID_A=$!

# Let A enter its critical section.
sleep "$HEAD_START"

# Process B: raw critical section, NO lock — should interleave with A.
( bash -c "echo $B_START >> \"$SHARED_LOG\"; sleep $CS_SLEEP; echo $B_END >> \"$SHARED_LOG\"" ) &
PID_B=$!

wait $PID_A 2>/dev/null || true
wait $PID_B 2>/dev/null || true

if [ ! -f "$SHARED_LOG" ]; then
  fail "$CURRENT_CASE: shared log not created"
else
  CONTENT="$(cat "$SHARED_LOG")"
  if ! interleave_detected "$CONTENT"; then
    fail "$CURRENT_CASE: critical sections did NOT interleave without the lock — the positive case cannot prove it detects non-serialization. Log: $(oneline_log)"
  fi
  # Sanity: all four markers still present.
  for m in "$A_START" "$A_END" "$B_START" "$B_END"; do
    case "$CONTENT" in
      *"$m"*) : ;;
      *) fail "$CURRENT_CASE: missing marker '$m'. Log: $(oneline_log)" ;;
    esac
  done
fi

# ---- Summary ---------------------------------------------------------------
echo ""
echo "stage-b-serialization tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
