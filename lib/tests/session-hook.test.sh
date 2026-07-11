#!/usr/bin/env bash
# Tests for lib/session-hook.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/session-hook.sh"

FAILED=0
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

setup() { TMP="$(mktemp -d -t session-hook-test.XXXXXX)"; }
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

EVENTS() { echo "$TMP/.do-work/state/events.jsonl"; }

# --- start with .do-work + marker (mirrors REQ verification step 2) ---------
CURRENT_CASE="start emits session.start with marker"
setup
mkdir -p "$TMP/.do-work"
out=$( cd "$TMP" && echo '{"session_id":"test-123"}' | DO_WORK_UI_MARKER=m1 bash "$SCRIPT" start )
rc=$?
assert_eq 0 "$rc" "exit code"
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"session":"test-123"'*) : ;;
  *) fail "session missing: $line" ;;
esac
case "$line" in
  *'"type":"session.start"'*) : ;;
  *) fail "type wrong: $line" ;;
esac
case "$line" in
  *'"data":{"marker":"m1"}'*) : ;;
  *) fail "marker data missing: $line" ;;
esac
teardown

# --- start without marker: no data field -----------------------------------
CURRENT_CASE="start without marker omits data"
setup
mkdir -p "$TMP/.do-work"
# Explicitly clear the marker — it may be set in the ambient environment when
# this session was itself spawned by the extension.
( cd "$TMP" && echo '{"session_id":"s2"}' | env -u DO_WORK_UI_MARKER bash "$SCRIPT" start )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *data*) fail "data should be absent without marker: $line" ;;
esac
case "$line" in
  *'"type":"session.start"'*) : ;;
  *) fail "type wrong: $line" ;;
esac
teardown

# --- end emits session.end -------------------------------------------------
CURRENT_CASE="end emits session.end"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && echo '{"session_id":"s3"}' | bash "$SCRIPT" end )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"type":"session.end"'*) : ;;
  *) fail "type wrong: $line" ;;
esac
case "$line" in
  *'"session":"s3"'*) : ;;
  *) fail "session wrong: $line" ;;
esac
teardown

# --- no .do-work: exit 0, no file written (REQ verification step 3) ---------
CURRENT_CASE="no .do-work is a silent no-op"
setup
# TMP has NO .do-work/ directory.
out=$( cd "$TMP" && echo '{"session_id":"test-123"}' | DO_WORK_UI_MARKER=m1 bash "$SCRIPT" start )
rc=$?
assert_eq 0 "$rc" "exit code without .do-work"
[ -e "$TMP/.do-work" ] && fail ".do-work must not be created"
[ -e "$(EVENTS)" ] && fail "events.jsonl must not be created"
teardown

# --- missing session_id: no-op exit 0 --------------------------------------
CURRENT_CASE="missing session_id is a no-op"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && echo '{"cwd":"'"$TMP"'"}' | bash "$SCRIPT" start )
rc=$?
assert_eq 0 "$rc" "exit code"
[ -e "$(EVENTS)" ] && fail "no event should be written without session_id"
teardown

# --- cwd from payload resolves the project ---------------------------------
CURRENT_CASE="cwd from payload resolves project"
setup
mkdir -p "$TMP/.do-work"
# Invoke from an unrelated dir; project comes from payload cwd.
( cd / && printf '{"session_id":"s4","cwd":"%s"}' "$TMP" | bash "$SCRIPT" start )
[ -f "$(EVENTS)" ] || fail "event should be written to payload cwd project"
teardown

# --- bad mode never fails the session --------------------------------------
CURRENT_CASE="unknown mode exits 0"
setup
echo '{"session_id":"s5"}' | bash "$SCRIPT" bogus >/dev/null 2>&1
assert_eq 0 "$?" "unknown mode still exits 0"
teardown

# --- summary ---------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  echo "session-hook.test.sh: all cases passed"
  exit 0
else
  echo "session-hook.test.sh: $FAILED assertion(s) failed" >&2
  exit 1
fi
