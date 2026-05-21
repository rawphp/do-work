#!/usr/bin/env bash
# Tests for lib/heartbeat.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# IMPORTANT: All fixtures are created under mktemp -d. We never touch the
# real .do-work/working/ tree.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
HEARTBEAT="$LIB_DIR/heartbeat.sh"

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

assert_matches() {
  # ERE regex match using grep -E.
  local pattern="$1"
  local subject="$2"
  local label="$3"
  if ! printf '%s' "$subject" | grep -Eq "$pattern"; then
    fail "$label: expected pattern '$pattern' to match '$subject'"
  fi
}

# ISO-8601 UTC pattern: 2026-05-21T14:08:12Z
ISO_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

setup_fixture() {
  TMP="$(mktemp -d -t heartbeat-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  TMP=""
}

# Write a REQ file containing a claim stamp WITHOUT a Heartbeat line.
write_req_no_heartbeat() {
  local path="$1"
  cat > "$path" <<'EOF'
# REQ-999: Sample REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T01:00:00Z
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** lib/heartbeat.sh
**Depends on:**

## Task

Do the thing.
EOF
}

# Write a REQ file containing a claim stamp WITH an existing Heartbeat line.
write_req_with_heartbeat() {
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
**Files:** lib/heartbeat.sh
**Depends on:**

## Task

Do the thing.
EOF
}

# Run heartbeat.sh. Stores HB_RC, HB_STDOUT, HB_STDERR.
run_heartbeat() {
  local req_path="$1"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  "$HEARTBEAT" "$req_path" > "$out_file" 2> "$err_file"
  HB_RC=$?
  HB_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  HB_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# Extract the Heartbeat value from a REQ file (first match only).
read_heartbeat() {
  grep -m1 '^\*\*Heartbeat:\*\*' "$1" | sed 's/^\*\*Heartbeat:\*\* //'
}

# Count occurrences of the Heartbeat line in a REQ file.
count_heartbeat() {
  grep -c '^\*\*Heartbeat:\*\*' "$1" 2>/dev/null || echo 0
}

# ----------------------------------------------------------------------
# Case 1: insert Heartbeat when absent
# ----------------------------------------------------------------------
CURRENT_CASE="insert-when-absent"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_no_heartbeat "$REQ"

run_heartbeat "$REQ"
assert_eq "0" "$HB_RC" "$CURRENT_CASE rc"

# Heartbeat line must now exist exactly once.
cnt="$(count_heartbeat "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE heartbeat count"

# Value must be ISO-8601 UTC Z.
hb="$(read_heartbeat "$REQ")"
assert_matches "$ISO_PATTERN" "$hb" "$CURRENT_CASE iso format"

# Must sit before claimed-end inside the stamp block.
content="$(cat "$REQ")"
case "$content" in
  *"**Heartbeat:** ${hb}"*"<!-- claimed-end -->"*) : ;;
  *) fail "$CURRENT_CASE: Heartbeat not positioned before claimed-end" ;;
esac

# Claimed by/at unchanged.
assert_contains "**Claimed by:** test-agent.1234" "$content" "$CURRENT_CASE Claimed by preserved"
assert_contains "**Claimed at:** 2026-05-21T01:00:00Z" "$content" "$CURRENT_CASE Claimed at preserved"

teardown_fixture

# ----------------------------------------------------------------------
# Case 2: replace existing Heartbeat
# ----------------------------------------------------------------------
CURRENT_CASE="replace-existing"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_with_heartbeat "$REQ"

original_hb="$(read_heartbeat "$REQ")"
assert_eq "2026-05-21T01:00:00Z" "$original_hb" "$CURRENT_CASE original hb"

# Sleep 1s so timestamp can plausibly differ. (Not strictly needed — format
# check is enough — but it lets us assert distinctness when the test isn't
# run in the same second as the canned timestamp.)
sleep 1

run_heartbeat "$REQ"
assert_eq "0" "$HB_RC" "$CURRENT_CASE rc"

cnt="$(count_heartbeat "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE heartbeat still single"

new_hb="$(read_heartbeat "$REQ")"
assert_matches "$ISO_PATTERN" "$new_hb" "$CURRENT_CASE iso format"

# Must differ from the canned original.
if [ "$new_hb" = "$original_hb" ]; then
  fail "$CURRENT_CASE: heartbeat was not updated (still $new_hb)"
fi

# Claimed at must NOT have changed.
claimed_at="$(grep -m1 '^\*\*Claimed at:\*\*' "$REQ" | sed 's/^\*\*Claimed at:\*\* //')"
assert_eq "2026-05-21T01:00:00Z" "$claimed_at" "$CURRENT_CASE Claimed at unchanged"

teardown_fixture

# ----------------------------------------------------------------------
# Case 3: file missing → exit 1
# ----------------------------------------------------------------------
CURRENT_CASE="missing-file-exit-1"
CASES=$((CASES + 1))
setup_fixture
MISSING="$TMP/.do-work/working/REQ-404-not-here.md"

run_heartbeat "$MISSING"
assert_eq "1" "$HB_RC" "$CURRENT_CASE rc=1"
# Stderr should mention the path or the missing condition.
case "$HB_STDERR" in
  *not\ found*|*does\ not\ exist*|*missing*|*REQ-404*)
    : ;;
  *)
    fail "$CURRENT_CASE: stderr should mention missing file, got: $HB_STDERR" ;;
esac

teardown_fixture

# ----------------------------------------------------------------------
# Case 4: file outside working/ → warn + non-zero exit
# ----------------------------------------------------------------------
CURRENT_CASE="outside-working-warn"
CASES=$((CASES + 1))
setup_fixture
# Put a REQ at backlog root (NOT in working/).
REQ="$TMP/.do-work/REQ-999-stray.md"
write_req_no_heartbeat "$REQ"

run_heartbeat "$REQ"
case "$HB_RC" in
  0) fail "$CURRENT_CASE: expected non-zero exit, got 0" ;;
  *) : ;;
esac
# Stderr should warn about location.
case "$HB_STDERR" in
  *working*|*outside*)
    : ;;
  *)
    fail "$CURRENT_CASE: stderr should warn about non-working path, got: $HB_STDERR" ;;
esac

teardown_fixture

# ----------------------------------------------------------------------
# Case 5: idempotent — running twice leaves a single Heartbeat line
# ----------------------------------------------------------------------
CURRENT_CASE="idempotent"
CASES=$((CASES + 1))
setup_fixture
REQ="$TMP/.do-work/working/REQ-999-foo.md"
write_req_no_heartbeat "$REQ"

run_heartbeat "$REQ"
assert_eq "0" "$HB_RC" "$CURRENT_CASE first run rc"
run_heartbeat "$REQ"
assert_eq "0" "$HB_RC" "$CURRENT_CASE second run rc"

cnt="$(count_heartbeat "$REQ")"
assert_eq "1" "$cnt" "$CURRENT_CASE heartbeat still single after two runs"

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
