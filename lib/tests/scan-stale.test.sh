#!/usr/bin/env bash
# Tests for lib/scan-stale.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCAN="$LIB_DIR/scan-stale.sh"

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

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: unexpected substring '$needle' in '$haystack'" ;;
    *) : ;;
  esac
}

# Compute an ISO-8601 UTC timestamp offset by N seconds from now.
# Args: $1 = offset in seconds (may be negative, e.g. -3600 for 1h ago).
# Handles BSD (macOS) and GNU date.
iso_at_offset() {
  local offset="$1"
  # Try BSD date first.
  if date -u -v+0S +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    if [ "$offset" -lt 0 ]; then
      local abs=$(( -offset ))
      date -u -v-${abs}S +%Y-%m-%dT%H:%M:%SZ
    else
      date -u -v+${offset}S +%Y-%m-%dT%H:%M:%SZ
    fi
  else
    # GNU date
    date -u -d "@$(( $(date -u +%s) + offset ))" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# Write a working REQ with given heartbeat content.
# Args: $1 = path, $2 = id, $3 = heartbeat-line-content (full line) or empty to omit
write_working_req() {
  local path="$1"
  local id="$2"
  local hb_line="$3"
  if [ -n "$hb_line" ]; then
    cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T00:00:00Z
$hb_line
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
EOF
  else
    cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** test-agent.1234
**Claimed at:** 2026-05-21T00:00:00Z
<!-- claimed-end -->

**UR:** UR-001
**Status:** in-progress
EOF
  fi
}

setup_fixture() {
  TMP="$(mktemp -d -t scan-stale.XXXXXX)"
  mkdir -p "$TMP/.do-work/working"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Run scan-stale.sh inside $TMP. Stores RC, STDOUT, STDERR.
run_scan() {
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$SCAN" > "$out_file" 2> "$err_file" )
  RC=$?
  STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: fresh slot — heartbeat well within threshold → not stale
# ----------------------------------------------------------------------
CURRENT_CASE="fresh-slot"
CASES=$((CASES + 1))
setup_fixture
FRESH_ISO="$(iso_at_offset -10)"
write_working_req "$TMP/.do-work/working/REQ-001-fresh.md" "REQ-001" "**Heartbeat:** $FRESH_ISO"
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_not_contains "REQ-001-fresh.md" "$STDOUT" "$CURRENT_CASE no stale output"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: stale slot — heartbeat older than 300s default threshold
# ----------------------------------------------------------------------
CURRENT_CASE="stale-slot"
CASES=$((CASES + 1))
setup_fixture
STALE_ISO="$(iso_at_offset -3600)"   # 1 hour ago
write_working_req "$TMP/.do-work/working/REQ-002-stale.md" "REQ-002" "**Heartbeat:** $STALE_ISO"
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-002-stale.md" "$STDOUT" "$CURRENT_CASE stale slot in output"
assert_contains "$STALE_ISO" "$STDOUT" "$CURRENT_CASE heartbeat reported"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: missing-heartbeat slot — no **Heartbeat:** line at all (legacy)
# ----------------------------------------------------------------------
CURRENT_CASE="missing-heartbeat"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-003-nohb.md" "REQ-003" ""
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-003-nohb.md" "$STDOUT" "$CURRENT_CASE missing-hb slot reported"
assert_contains "absent" "$STDOUT" "$CURRENT_CASE 'absent' marker in output"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: malformed heartbeat — non-ISO-8601 → stale + diagnostic
# ----------------------------------------------------------------------
CURRENT_CASE="malformed-heartbeat"
CASES=$((CASES + 1))
setup_fixture
write_working_req "$TMP/.do-work/working/REQ-004-bad.md" "REQ-004" "**Heartbeat:** not-a-timestamp"
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-004-bad.md" "$STDOUT" "$CURRENT_CASE malformed slot in output"
assert_contains "REQ-004" "$STDERR" "$CURRENT_CASE diagnostic mentions REQ id"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: config override — stale_threshold_seconds: 60 (60s) makes a
# 120s-old slot stale even though it would not be stale under the
# default 300s threshold.
# ----------------------------------------------------------------------
CURRENT_CASE="config-override"
CASES=$((CASES + 1))
setup_fixture
cat > "$TMP/.do-work/config.yml" <<EOF
parallel:
  stale_threshold_seconds: 60
EOF
MID_ISO="$(iso_at_offset -120)"
write_working_req "$TMP/.do-work/working/REQ-005-mid.md" "REQ-005" "**Heartbeat:** $MID_ISO"
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-005-mid.md" "$STDOUT" "$CURRENT_CASE override makes slot stale"
teardown_fixture

# Inverse: under default 300s, the same 120s-old slot is NOT stale.
CURRENT_CASE="config-override-default-not-stale"
CASES=$((CASES + 1))
setup_fixture
MID_ISO="$(iso_at_offset -120)"
write_working_req "$TMP/.do-work/working/REQ-006-mid.md" "REQ-006" "**Heartbeat:** $MID_ISO"
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_not_contains "REQ-006-mid.md" "$STDOUT" "$CURRENT_CASE default 300s leaves it fresh"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: no working/ slots — clean exit, empty output
# ----------------------------------------------------------------------
CURRENT_CASE="no-working-slots"
CASES=$((CASES + 1))
setup_fixture
run_scan
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_eq "" "$STDOUT" "$CURRENT_CASE empty stdout"
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
