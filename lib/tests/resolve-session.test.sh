#!/usr/bin/env bash
# Tests for lib/resolve-session.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
RESOLVER="$LIB_DIR/resolve-session.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

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

# Create an isolated project fixture with a .do-work/state/ dir. Sets TMP.
setup_fixture() {
  TMP="$(mktemp -d -t resolve-session.XXXXXX)"
  mkdir -p "$TMP/.do-work/state"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Append one event line to the fixture's events.jsonl via emit-event.sh so the
# format under test is exactly what the real emitter writes.
emit() {
  local type="$1" session="$2" data="${3:-}"
  EMIT_EVENT_TS="2026-07-11T00:00:0${CASES}Z" \
    bash "$LIB_DIR/emit-event.sh" "$TMP" "$type" "$session" "$data" >/dev/null
}

# Run resolve-session.sh; store RC and STDOUT.
run_resolve() {
  local marker_set="$1"  # "1" to export DO_WORK_UI_MARKER, "0" to unset
  local marker_val="$2"
  local out_file="$TMP/.stdout.$$"
  if [ "$marker_set" = "1" ]; then
    DO_WORK_UI_MARKER="$marker_val" "$RESOLVER" "$TMP" > "$out_file" 2>/dev/null
  else
    ( unset DO_WORK_UI_MARKER; "$RESOLVER" "$TMP" > "$out_file" 2>/dev/null )
  fi
  RC=$?
  STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  rm -f "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: marker match — stamps the session whose start carries the marker
# ----------------------------------------------------------------------
CURRENT_CASE="marker-match"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-A" '{"marker":"m1"}'
emit "session.start" "sess-B" '{"marker":"m2"}'
run_resolve 1 "m1"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "sess-A" "$STDOUT" "$CURRENT_CASE resolves marker owner"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: no marker, single un-ended session — fallback resolves it
# ----------------------------------------------------------------------
CURRENT_CASE="no-marker-single-session"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-only" ""
run_resolve 0 ""
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "sess-only" "$STDOUT" "$CURRENT_CASE fallback resolves single session"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: multiple live sessions, no marker match — omit (never guess)
# ----------------------------------------------------------------------
CURRENT_CASE="ambiguous-multi-session"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-X" ""
emit "session.start" "sess-Y" ""
run_resolve 0 ""
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT" "$CURRENT_CASE omits when ambiguous"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: missing events.jsonl — omit, exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="missing-events"
CASES=$((CASES + 1))
setup_fixture
# No emit — events.jsonl absent.
run_resolve 1 "m1"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT" "$CURRENT_CASE omits when events.jsonl absent"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: marker set but no match — falls back to single un-ended session
# ----------------------------------------------------------------------
CURRENT_CASE="marker-no-match-fallback"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-fb" ""
run_resolve 1 "does-not-exist"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "sess-fb" "$STDOUT" "$CURRENT_CASE falls back when marker unmatched"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: ended session excluded from fallback candidates
# ----------------------------------------------------------------------
CURRENT_CASE="ended-session-excluded"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-1" ""
emit "session.end"   "sess-1" ""
emit "session.start" "sess-2" ""
run_resolve 0 ""
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "sess-2" "$STDOUT" "$CURRENT_CASE only the un-ended session resolves"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: marker match wins even when multiple sessions are live
# ----------------------------------------------------------------------
CURRENT_CASE="marker-wins-over-ambiguity"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-P" '{"marker":"mk"}'
emit "session.start" "sess-Q" ""
run_resolve 1 "mk"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "sess-P" "$STDOUT" "$CURRENT_CASE marker match beats ambiguity"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: marker prefix must not false-match (m1 vs m10)
# ----------------------------------------------------------------------
CURRENT_CASE="marker-prefix-no-false-match"
CASES=$((CASES + 1))
setup_fixture
emit "session.start" "sess-ten" '{"marker":"m10"}'
run_resolve 1 "m1"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
# No exact marker match for m1; single un-ended session falls back to sess-ten.
assert_eq "sess-ten" "$STDOUT" "$CURRENT_CASE m1 does not match m10 (falls back)"
teardown_fixture

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
  echo "resolve-session.test.sh: $FAILED assertion(s) failed across $CASES cases" >&2
  exit 1
fi
echo "resolve-session.test.sh: all $CASES cases passed"
exit 0
