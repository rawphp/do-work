#!/usr/bin/env bash
# Tests for lib/emit-event.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/emit-event.sh"

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

setup() { TMP="$(mktemp -d -t emit-event-test.XXXXXX)"; }
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

EVENTS() { echo "$TMP/.do-work/state/events.jsonl"; }

# --- happy path: with data, deterministic ts ------------------------------
CURRENT_CASE="happy path with data"
setup
mkdir -p "$TMP/.do-work"
EMIT_EVENT_TS="2026-07-11T00:00:00Z" bash "$SCRIPT" "$TMP" session.start "test-123" '{"marker":"m1"}'
rc=$?
assert_eq 0 "$rc" "exit code"
line="$(cat "$(EVENTS)")"
assert_eq '{"ts":"2026-07-11T00:00:00Z","session":"test-123","type":"session.start","data":{"marker":"m1"}}' "$line" "line content"
# exactly one line
assert_eq 1 "$(wc -l < "$(EVENTS)" | tr -d ' ')" "line count"
teardown

# --- no data arg: omit the data field --------------------------------------
CURRENT_CASE="no data field"
setup
mkdir -p "$TMP/.do-work"
EMIT_EVENT_TS="2026-07-11T00:00:00Z" bash "$SCRIPT" "$TMP" session.end "sess-w1"
line="$(cat "$(EVENTS)")"
assert_eq '{"ts":"2026-07-11T00:00:00Z","session":"sess-w1","type":"session.end"}' "$line" "line content"
case "$line" in
  *data*) fail "data key should be absent" ;;
esac
teardown

# --- defensive dir creation ------------------------------------------------
CURRENT_CASE="defensive state dir creation"
setup
mkdir -p "$TMP/.do-work"   # no state/ subdir yet
[ -d "$TMP/.do-work/state" ] && fail "precondition: state/ should not exist yet"
bash "$SCRIPT" "$TMP" session.start "s1" >/dev/null
[ -f "$(EVENTS)" ] || fail "events.jsonl not created"
teardown

# --- append (not overwrite) ------------------------------------------------
CURRENT_CASE="append two lines"
setup
mkdir -p "$TMP/.do-work"
bash "$SCRIPT" "$TMP" session.start "s1" >/dev/null
bash "$SCRIPT" "$TMP" session.end "s1" >/dev/null
assert_eq 2 "$(wc -l < "$(EVENTS)" | tr -d ' ')" "two appended lines"
teardown

# --- missing args -> exit 1 ------------------------------------------------
CURRENT_CASE="usage error"
setup
bash "$SCRIPT" "$TMP" session.start >/dev/null 2>&1
assert_eq 1 "$?" "missing session exits 1"
teardown

# --- session with special chars is escaped to valid JSON -------------------
CURRENT_CASE="special-char session escaped"
setup
mkdir -p "$TMP/.do-work"
bash "$SCRIPT" "$TMP" session.start 'a"b\c' >/dev/null
# Must remain valid JSON — validate with python3 (present per repo precedent).
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.loads(open(sys.argv[1]).readline())' "$(EVENTS)" \
    || fail "escaped line is not valid JSON"
fi
teardown

# --- every emitted line parses as valid JSON (parser-contract smoke) -------
CURRENT_CASE="valid JSON contract"
setup
mkdir -p "$TMP/.do-work"
bash "$SCRIPT" "$TMP" session.start "s1" '{"marker":"x"}' >/dev/null
if command -v python3 >/dev/null 2>&1; then
  python3 - "$(EVENTS)" <<'PY' || fail "line failed parser contract"
import json, sys
o = json.loads(open(sys.argv[1]).readline())
assert isinstance(o.get("ts"), str), "ts must be string"
assert isinstance(o.get("session"), str), "session must be string"
assert isinstance(o.get("type"), str), "type must be string"
assert isinstance(o.get("data"), dict), "data must be object when present"
PY
fi
teardown

# --- summary ---------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  echo "emit-event.test.sh: all cases passed"
  exit 0
else
  echo "emit-event.test.sh: $FAILED assertion(s) failed" >&2
  exit 1
fi
