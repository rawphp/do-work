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

# --- helper: write a fixture JSONL transcript whose LAST assistant model is $2
write_transcript() {
  # $1 = path, $2 = last assistant model id
  cat > "$1" <<JSONL
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"id":"a1","role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"a"}]}}
{"type":"user","message":{"role":"user","content":"more"}}
{"type":"assistant","message":{"id":"a2","role":"assistant","model":"$2","content":[{"type":"text","text":"b"}],"usage":{"input_tokens":1}}}
JSONL
}

# --- AC1: start includes stdin model in session.start data -----------------
CURRENT_CASE="start passes stdin model into data"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && echo '{"session_id":"t1","model":"claude-opus-4-8","transcript_path":"/dev/null"}' | env -u DO_WORK_UI_MARKER bash "$SCRIPT" start )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"type":"session.start"'*) : ;;
  *) fail "type wrong: $line" ;;
esac
case "$line" in
  *'"model":"claude-opus-4-8"'*) : ;;
  *) fail "data.model missing: $line" ;;
esac
teardown

# --- AC2a: start falls back to transcript model when stdin has none --------
CURRENT_CASE="start falls back to transcript model"
setup
mkdir -p "$TMP/.do-work"
write_transcript "$TMP/tr.jsonl" "claude-sonnet-5"
( cd "$TMP" && printf '{"session_id":"t2","transcript_path":"%s"}' "$TMP/tr.jsonl" | env -u DO_WORK_UI_MARKER bash "$SCRIPT" start )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"model":"claude-sonnet-5"'*) : ;;
  *) fail "transcript model not used: $line" ;;
esac
teardown

# --- AC2b: no model anywhere -> no data.model key --------------------------
CURRENT_CASE="start omits model when none available"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && printf '{"session_id":"t3","transcript_path":"/dev/null"}' | env -u DO_WORK_UI_MARKER bash "$SCRIPT" start )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"model"'*) fail "model should be absent: $line" ;;
esac
case "$line" in
  *data*) fail "data should be absent with no marker and no model: $line" ;;
esac
teardown

# --- model composes with marker -------------------------------------------
CURRENT_CASE="start composes marker + model in data"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && echo '{"session_id":"t4","model":"claude-opus-4-8","transcript_path":"/dev/null"}' | DO_WORK_UI_MARKER=m9 bash "$SCRIPT" start )
line="$(tail -n1 "$(EVENTS)")"
case "$line" in
  *'"marker":"m9"'*) : ;;
  *) fail "marker missing when composing: $line" ;;
esac
case "$line" in
  *'"model":"claude-opus-4-8"'*) : ;;
  *) fail "model missing when composing: $line" ;;
esac
teardown

# --- AC3+AC4: Stop emits one model.change on diff, none when unchanged ------
CURRENT_CASE="stop model.change once on diff, none when unchanged"
setup
mkdir -p "$TMP/.do-work"
write_transcript "$TMP/tr.jsonl" "claude-sonnet-5"
# session.start records opus
( cd "$TMP" && echo '{"session_id":"m1","model":"claude-opus-4-8","transcript_path":"/dev/null"}' | env -u DO_WORK_UI_MARKER bash "$SCRIPT" start )
# stop 1: transcript says sonnet (differs) -> one model.change
( cd "$TMP" && printf '{"session_id":"m1","transcript_path":"%s"}' "$TMP/tr.jsonl" | bash "$SCRIPT" end )
# stop 2: same transcript, model now matches recorded -> no new model.change
( cd "$TMP" && printf '{"session_id":"m1","transcript_path":"%s"}' "$TMP/tr.jsonl" | bash "$SCRIPT" end )
count="$(grep -c 'model.change' "$(EVENTS)" | tr -d ' ')"
assert_eq 1 "$count" "exactly one model.change total"
mc="$(grep 'model.change' "$(EVENTS)")"
case "$mc" in
  *'"model":"claude-sonnet-5"'*) : ;;
  *) fail "model.change should carry new model: $mc" ;;
esac
ss="$(grep 'session.start' "$(EVENTS)")"
case "$ss" in
  *'"model":"claude-opus-4-8"'*) : ;;
  *) fail "session.start should carry opus: $ss" ;;
esac
# session.end still emitted per turn (regression guard)
case "$(grep -c 'session.end' "$(EVENTS)" | tr -d ' ')" in
  2) : ;;
  *) fail "expected two session.end lines, one per stop" ;;
esac
teardown

# --- no model determinable -> no model.change, session.end still emitted ----
CURRENT_CASE="stop with no determinable model emits no model.change"
setup
mkdir -p "$TMP/.do-work"
( cd "$TMP" && printf '{"session_id":"n1","transcript_path":"/dev/null"}' | bash "$SCRIPT" end )
[ -f "$(EVENTS)" ] || fail "session.end should still be written"
case "$(grep -c 'model.change' "$(EVENTS)" | tr -d ' ')" in
  0) : ;;
  *) fail "no model.change when model undeterminable" ;;
esac
teardown

# --- AC5: end mode with model payload but no .do-work -> exit 0, no writes ---
CURRENT_CASE="stop with model but no .do-work is a no-op"
setup
write_transcript "$TMP/tr.jsonl" "claude-sonnet-5"
out=$( cd "$TMP" && printf '{"session_id":"g1","transcript_path":"%s"}' "$TMP/tr.jsonl" | bash "$SCRIPT" end )
rc=$?
assert_eq 0 "$rc" "exit 0 without .do-work"
[ -e "$TMP/.do-work" ] && fail ".do-work must not be created"
teardown

# --- summary ---------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  echo "session-hook.test.sh: all cases passed"
  exit 0
else
  echo "session-hook.test.sh: $FAILED assertion(s) failed" >&2
  exit 1
fi
