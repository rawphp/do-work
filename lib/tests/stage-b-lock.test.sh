#!/usr/bin/env bash
# Tests for lib/stage-b-lock.sh
#
# Stage B serialization lock tests. Proves:
# 1. Mutual exclusion — while one process holds the lock, a second waits
# 2. Auto-release on process death — killing the holder releases the lock
# 3. Portability guard — errors clearly if python3 is absent
#
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/stage-b-lock.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

# State directory for tests
STATE_DIR="$(mktemp -d -t stage-b-lock-state.XXXXXX)"
LOCK_FILE="$STATE_DIR/stage-b.lock"
TIMING_FILE="$STATE_DIR/timing.txt"

trap 'rm -rf "$STATE_DIR"' EXIT INT TERM

# Helper: run a command under the lock
with_lock() {
  STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock "$@" 2>&1
}

# Helper: get exit code only
with_lock_rc() {
  STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock "$@" >/dev/null 2>&1
  echo $?
}

# ---- Test 1: python3 missing guard --------------------------------------------
CURRENT_CASE="python3-missing-guard"
CASES=$((CASES + 1))

# Break PATH to hide python3
PATH_SAVE="$PATH"
PATH="/empty/bin"
OUT=$(STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock echo "test" 2>&1)
RC=$?
PATH="$PATH_SAVE"

if [ "$RC" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero rc when python3 missing, got 0"
fi

case "$OUT" in
  *"python3"*|*"required"*|*"not found"*) : ;;
  *) fail "$CURRENT_CASE: expected python3-missing message, got: $OUT" ;;
esac

# ---- Test 2: with-lock executes command --------------------------------------
CURRENT_CASE="with-lock-executes"
CASES=$((CASES + 1))

RESULT=$(with_lock echo "hello world")
RC=$?

if [ "$RC" -ne 0 ]; then
  fail "$CURRENT_CASE: with-lock failed with rc $RC"
fi

if [ "$RESULT" != "hello world" ]; then
  fail "$CURRENT_CASE: expected 'hello world', got '$RESULT'"
fi

# ---- Test 3: mutual exclusion — second holder waits -------------------------
CURRENT_CASE="mutual-exclusion"
CASES=$((CASES + 1))

# Clean state
rm -f "$TIMING_FILE"

# First holder: sleeps 2 seconds, writes timestamp
(STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock bash -c "echo start1 >> \"$TIMING_FILE\"; sleep 2; echo end1 >> \"$TIMING_FILE\"") &
PID1=$!

# Give it time to acquire lock and start
sleep 0.5

# Second holder: should wait for first, then execute
(STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock bash -c "echo start2 >> \"$TIMING_FILE\"; echo end2 >> \"$TIMING_FILE\"") &
PID2=$!

# Wait for both
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true

# Read timing file
if [ -f "$TIMING_FILE" ]; then
  CONTENT=$(cat "$TIMING_FILE")
  # Should see: start1, end1, start2, end2 (serialized)
  # NOT: start1, start2 (which would mean concurrent)
  case "$CONTENT" in
    *start2*end1*) fail "$CURRENT_CASE: start2 appeared before end1 (concurrent, not serialized). Content: $CONTENT" ;;
    *) : ;; # Good — serialized
  esac
else
  fail "$CURRENT_CASE: timing file not created"
fi

# ---- Test 4: auto-release on process death ----------------------------------
CURRENT_CASE="auto-release-on-death"
CASES=$((CASES + 1))

# Spawn a long-running holder in background
# Note: we use a simple sleep command - the wrapper will hold the lock
(STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock sleep 100) &
HOLDER_PID=$!

# Give it time to acquire lock
sleep 0.5

# Verify holder is still running (holding lock)
if ! kill -0 "$HOLDER_PID" 2>/dev/null; then
  fail "$CURRENT_CASE: holder process died unexpectedly"
fi

# Kill the holder's entire process group to ensure cleanup
# This kills the script AND any children (python3 holding the lock)
kill -9 -"$HOLDER_PID" 2>/dev/null || true
sleep 0.3

# Also ensure any strays are gone
pkill -9 -f "stage-b-lock" 2>/dev/null || true
sleep 0.2

# New holder should acquire immediately (lock auto-released)
# We run it in background and wait with timeout
(STATE_DIR="$STATE_DIR" bash "$SCRIPT" with-lock echo "quick") &
QUICK_PID=$!

WAITED=0
while kill -0 "$QUICK_PID" 2>/dev/null; do
  sleep 0.2
  WAITED=$((WAITED + 1))
  if [ "$WAITED" -gt 10 ]; then  # 2 seconds
    kill -9 "$QUICK_PID" 2>/dev/null || true
    fail "$CURRENT_CASE: second holder blocked > 2s after killing first (lock not auto-released)"
    break
  fi
done
wait "$QUICK_PID" 2>/dev/null || true

# ---- Test 5: lock file created in state dir --------------------------------
CURRENT_CASE="lock-file-created"
CASES=$((CASES + 1))

# Ensure clean state
rm -f "$LOCK_FILE"

with_lock echo "test" >/dev/null

# Lock file should exist
if [ ! -f "$LOCK_FILE" ]; then
  fail "$CURRENT_CASE: lock file not created in state directory"
fi

# ---- Test 6: command exit code is preserved ---------------------------------
CURRENT_CASE="exit-code-preserved"
CASES=$((CASES + 1))

RC=$(with_lock_rc bash -c "exit 42")
if [ "$RC" -ne 42 ]; then
  fail "$CURRENT_CASE: expected exit code 42, got $RC"
fi

# ---- Test 7: command stderr passes through ----------------------------------
CURRENT_CASE="stderr-passthrough"
CASES=$((CASES + 1))

RESULT=$(with_lock bash -c 'echo "error message" >&2' 2>&1)
RC=$?

# Both stdout and stderr should be captured (in 2>&1)
if [ "$RC" -ne 0 ]; then
  fail "$CURRENT_CASE: command failed unexpectedly"
fi

case "$RESULT" in
  *"error message"*) : ;; # Good
  *) fail "$CURRENT_CASE: stderr not passed through" ;;
esac

# ---- Summary ----------------------------------------------------------------
echo ""
echo "stage-b-lock tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
