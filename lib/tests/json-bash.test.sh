#!/usr/bin/env bash
# Tests for lib/json-bash.sh — shared JSON string escape + field extract.
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
HELPER="$LIB_DIR/json-bash.sh"

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

# --- source helper ----------------------------------------------------------
CURRENT_CASE="source helper"
if [ ! -f "$HELPER" ]; then
  fail "lib/json-bash.sh must exist"
  echo "FAILED: $FAILED"
  exit 1
fi
# shellcheck disable=SC1090
. "$HELPER"
# re-source must be safe
. "$HELPER"

# --- json_escape: plain -----------------------------------------------------
CURRENT_CASE="json_escape plain"
assert_eq 'hello' "$(json_escape 'hello')" "plain string"

# --- json_escape: backslash then quote order --------------------------------
# Input chars a \ " b → escape \ first → a \\ " b → escape " → a \\ \ " b
# Printed form: a\\\"b (valid JSON string content for a\"b).
CURRENT_CASE="json_escape backslash and quote"
assert_eq 'a\\\"b' "$(json_escape 'a\"b')" "backslash then quote"
assert_eq '\\\\' "$(json_escape '\\')" "single backslash doubles"
assert_eq '\"' "$(json_escape '"')" "lone quote"

# --- json_escape: tab -> \\t ------------------------------------------------
CURRENT_CASE="json_escape tab"
assert_eq 'a\tb' "$(json_escape $'a\tb')" "tab becomes \\t"

# --- json_escape: strip CR/LF -----------------------------------------------
CURRENT_CASE="json_escape strip CR LF"
assert_eq 'ab' "$(json_escape $'a\rb\n')" "CR and LF stripped"

# --- json_escape: empty -----------------------------------------------------
CURRENT_CASE="json_escape empty"
assert_eq '' "$(json_escape '')" "empty string"

# --- json_string_field: basic compact ---------------------------------------
CURRENT_CASE="json_string_field basic"
line='{"ts":"t","session":"sess-1","type":"session.start"}'
assert_eq 'sess-1' "$(json_string_field "$line" session)" "session field"
assert_eq 'session.start' "$(json_string_field "$line" type)" "type field"

# --- json_string_field: optional whitespace around colon --------------------
CURRENT_CASE="json_string_field whitespace"
line='{ "session" : "sess-ws" }'
assert_eq 'sess-ws' "$(json_string_field "$line" session)" "spaced colon"

# --- json_string_field: missing field ---------------------------------------
CURRENT_CASE="json_string_field missing"
assert_eq '' "$(json_string_field '{"a":"1"}' session)" "missing field empty"

# --- json_string_field: empty payload ---------------------------------------
CURRENT_CASE="json_string_field empty payload"
assert_eq '' "$(json_string_field '' session_id)" "empty payload"

# --- json_string_field: no trailing-newline glue (BSD sed safety) -----------
# Without feeding sed a trailing newline, two successive extracts can glue.
CURRENT_CASE="json_string_field no glue without final newline"
a="$(json_string_field '{"session":"sess-X"}' session)"
b="$(json_string_field '{"session":"sess-Y"}' session)"
assert_eq 'sess-X' "$a" "first extract"
assert_eq 'sess-Y' "$b" "second extract"
assert_eq 'sess-Xsess-Y' "${a}${b}" "concat is two distinct ids not glued mid-token"

# --- json_string_field: multi-key payload (session-hook style) --------------
CURRENT_CASE="json_string_field multi key"
payload='{"session_id":"abc-123","cwd":"/tmp/proj","model":"opus-4"}'
assert_eq 'abc-123' "$(json_string_field "$payload" session_id)" "session_id"
assert_eq '/tmp/proj' "$(json_string_field "$payload" cwd)" "cwd"
assert_eq 'opus-4' "$(json_string_field "$payload" model)" "model"

# --- functions are defined --------------------------------------------------
CURRENT_CASE="functions exported"
type json_escape >/dev/null 2>&1 || fail "json_escape not a function"
type json_string_field >/dev/null 2>&1 || fail "json_string_field not a function"

# --- summary ----------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
  echo "FAILED: $FAILED"
  exit 1
fi
echo "OK: json-bash tests passed"
exit 0
