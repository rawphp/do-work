#!/usr/bin/env bash
# Tests for lib/stamp-session.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# IMPORTANT: All fixtures are created under mktemp -d. We never touch the
# real .do-work/working/ tree.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
STAMP_SESSION="$LIB_DIR/stamp-session.sh"

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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

setup_fixture() {
  TMP="$(mktemp -d -t stamp-session-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive" "$TMP/.do-work/state"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  TMP=""
}

# Claim stamp WITH Heartbeat, WITHOUT Session.
write_req_no_session() {
  local path="$1"
  cat > "$path" <<'EOF'
# REQ-999: Sample REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T01:00:00Z
**Heartbeat:** 2026-05-21T01:00:00Z
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** lib/stamp-session.sh
**Depends on:**

## Task

Do the thing.
EOF
}

# Claim stamp WITH Heartbeat and Session.
write_req_with_session() {
  local path="$1"
  cat > "$path" <<'EOF'
# REQ-999: Sample REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T01:00:00Z
**Heartbeat:** 2026-05-21T01:00:00Z
**Session:** sess-old
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** lib/stamp-session.sh
**Depends on:**

## Task

Do the thing.
EOF
}

# Claim stamp markers absent entirely.
write_req_no_claim() {
  local path="$1"
  cat > "$path" <<'EOF'
# REQ-999: Sample REQ

**UR:** UR-001
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** lib/stamp-session.sh
**Depends on:**

## Task

Do the thing.
EOF
}

# Run stamp-session.sh. Stores SS_RC, SS_STDOUT, SS_STDERR.
# Args after req path are forwarded (optional session-id).
run_stamp() {
  local req_path="$1"
  shift
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  "$STAMP_SESSION" "$req_path" "$@" > "$out_file" 2> "$err_file"
  SS_RC=$?
  SS_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  SS_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

read_session() {
  grep -m1 '^\*\*Session:\*\*' "$1" | sed 's/^\*\*Session:\*\* //'
}

count_session() {
  grep -c '^\*\*Session:\*\*' "$1" 2>/dev/null || echo 0
}

# Extract content between claim fences (exclusive of markers).
claim_between() {
  awk '
    /^<!-- claimed-start -->$/ { inblock=1; next }
    /^<!-- claimed-end -->$/ { inblock=0 }
    inblock { print }
  ' "$1"
}

# ----------------------------------------------------------------------
# Case 1: insert Session when absent (explicit session-id)
# ----------------------------------------------------------------------
CURRENT_CASE="insert-when-absent"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_no_session "$REQ"

run_stamp "$REQ" "sess-new-1"
assert_eq "0" "$SS_RC" "$CURRENT_CASE rc"

cnt="$(count_session "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE session count"

sid="$(read_session "$REQ")"
assert_eq "sess-new-1" "$sid" "$CURRENT_CASE session value"

content="$(cat "$REQ")"
case "$content" in
  *"**Session:** sess-new-1"*"<!-- claimed-end -->"*) : ;;
  *) fail "$CURRENT_CASE: Session not positioned before claimed-end" ;;
esac

between="$(claim_between "$REQ")"
assert_contains "**Session:** sess-new-1" "$between" "$CURRENT_CASE Session inside claim fences"
assert_contains "**Claimed by:** test-agent.1234" "$content" "$CURRENT_CASE Claimed by preserved"
assert_contains "**Heartbeat:** 2026-05-21T01:00:00Z" "$content" "$CURRENT_CASE Heartbeat preserved"

teardown_fixture

# ----------------------------------------------------------------------
# Case 2: replace existing Session (explicit session-id)
# ----------------------------------------------------------------------
CURRENT_CASE="replace-existing"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_with_session "$REQ"

original_sid="$(read_session "$REQ")"
assert_eq "sess-old" "$original_sid" "$CURRENT_CASE original session"

run_stamp "$REQ" "sess-new-2"
assert_eq "0" "$SS_RC" "$CURRENT_CASE rc"

cnt="$(count_session "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE session still single"

new_sid="$(read_session "$REQ")"
assert_eq "sess-new-2" "$new_sid" "$CURRENT_CASE session replaced"

# Ownership / heartbeat untouched.
claimed_by="$(grep -m1 '^\*\*Claimed by:\*\*' "$REQ" | sed 's/^\*\*Claimed by:\*\* //')"
assert_eq "test-agent.1234" "$claimed_by" "$CURRENT_CASE Claimed by unchanged"
hb="$(grep -m1 '^\*\*Heartbeat:\*\*' "$REQ" | sed 's/^\*\*Heartbeat:\*\* //')"
assert_eq "2026-05-21T01:00:00Z" "$hb" "$CURRENT_CASE Heartbeat unchanged"

teardown_fixture

# ----------------------------------------------------------------------
# Case 3: empty resolve leaves existing Session line untouched
# ----------------------------------------------------------------------
CURRENT_CASE="empty-resolve-preserve"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_with_session "$REQ"

# No events.jsonl → resolve-session prints nothing. Omit session-id so the
# script must call resolve-session; empty result must leave sess-old alone.
run_stamp "$REQ"
assert_eq "0" "$SS_RC" "$CURRENT_CASE rc"

cnt="$(count_session "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE session still single"

sid="$(read_session "$REQ")"
assert_eq "sess-old" "$sid" "$CURRENT_CASE session preserved when resolve empty"

teardown_fixture

# ----------------------------------------------------------------------
# Case 4: omit session-id + resolvable session inserts/replaces via resolve
# ----------------------------------------------------------------------
CURRENT_CASE="resolve-and-insert"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_no_session "$REQ"

# Single un-ended session in events.jsonl so resolve-session prints it.
cat > "$TMP/.do-work/state/events.jsonl" <<'EOF'
{"type":"session.start","session":"sess-resolved","ts":"2026-05-21T01:00:00Z"}
EOF

run_stamp "$REQ"
assert_eq "0" "$SS_RC" "$CURRENT_CASE rc"

sid="$(read_session "$REQ")"
assert_eq "sess-resolved" "$sid" "$CURRENT_CASE resolved session stamped"

teardown_fixture

# ----------------------------------------------------------------------
# Case 5: missing claim stamp → exit non-zero
# ----------------------------------------------------------------------
CURRENT_CASE="missing-claim-stamp-fail"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_no_claim "$REQ"

run_stamp "$REQ" "sess-x"
case "$SS_RC" in
  0) fail "$CURRENT_CASE: expected non-zero exit, got 0" ;;
  *) : ;;
esac
case "$SS_STDERR" in
  *claim*|*stamp*|*claimed*)
    : ;;
  *)
    fail "$CURRENT_CASE: stderr should mention missing claim stamp, got: $SS_STDERR" ;;
esac
# File must not gain a Session line or claim block.
if grep -q '^\*\*Session:\*\*' "$REQ" 2>/dev/null; then
  fail "$CURRENT_CASE: must not invent Session without claim stamp"
fi
if grep -q 'claimed-start' "$REQ" 2>/dev/null; then
  fail "$CURRENT_CASE: must not create claim stamp"
fi

teardown_fixture

# ----------------------------------------------------------------------
# Case 6: path outside working/ → exit non-zero
# ----------------------------------------------------------------------
CURRENT_CASE="outside-working-fail"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/REQ-999-stray.md"
write_req_no_session "$REQ"

run_stamp "$REQ" "sess-x"
case "$SS_RC" in
  0) fail "$CURRENT_CASE: expected non-zero exit, got 0" ;;
  *) : ;;
esac
case "$SS_STDERR" in
  *working*|*outside*)
    : ;;
  *)
    fail "$CURRENT_CASE: stderr should warn about non-working path, got: $SS_STDERR" ;;
esac

teardown_fixture

# ----------------------------------------------------------------------
# Case 7: missing file → exit non-zero
# ----------------------------------------------------------------------
CURRENT_CASE="missing-file-fail"
CASES=$((CASES + 1))
setup_fixture
MISSING="$TMP/.do-work/working/REQ-404-not-here.md"

run_stamp "$MISSING" "sess-x"
assert_eq "1" "$SS_RC" "$CURRENT_CASE rc=1"
case "$SS_STDERR" in
  *not\ found*|*does\ not\ exist*|*missing*|*REQ-404*)
    : ;;
  *)
    fail "$CURRENT_CASE: stderr should mention missing file, got: $SS_STDERR" ;;
esac

teardown_fixture

# ----------------------------------------------------------------------
# Case 8: empty explicit session-id same as omit — leave untouched when resolve empty
# ----------------------------------------------------------------------
CURRENT_CASE="empty-arg-preserve"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_with_session "$REQ"

run_stamp "$REQ" ""
assert_eq "0" "$SS_RC" "$CURRENT_CASE rc"
sid="$(read_session "$REQ")"
assert_eq "sess-old" "$sid" "$CURRENT_CASE empty arg leaves session"

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
