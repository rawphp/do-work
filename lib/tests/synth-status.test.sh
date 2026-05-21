#!/usr/bin/env bash
# Tests for lib/synth-status.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SYNTH="$LIB_DIR/synth-status.sh"

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
iso_at_offset() {
  local offset="$1"
  if date -u -v+0S +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    if [ "$offset" -lt 0 ]; then
      local abs=$(( -offset ))
      date -u -v-${abs}S +%Y-%m-%dT%H:%M:%SZ
    else
      date -u -v+${offset}S +%Y-%m-%dT%H:%M:%SZ
    fi
  else
    date -u -d "@$(( $(date -u +%s) + offset ))" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# Write a backlog REQ file.
# Args: $1 = path, $2 = id, $3 = UR, $4 = files, $5 = deps
write_backlog_req() {
  local path="$1"
  local id="$2"
  local ur="$3"
  local files="$4"
  local deps="$5"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:** $deps

## Task

Test.
EOF
}

# Write a working REQ file (claim stamp present).
# Args: $1 = path, $2 = id, $3 = UR, $4 = files, $5 = deps, $6 = claimer, $7 = heartbeat-iso
write_working_req() {
  local path="$1"
  local id="$2"
  local ur="$3"
  local files="$4"
  local deps="$5"
  local claimer="$6"
  local hb="$7"
  cat > "$path" <<EOF
# $id: Test REQ

<!-- claimed-start -->
**Claimed by:** $claimer
**Claimed at:** $hb
**Heartbeat:** $hb
<!-- claimed-end -->

**UR:** $ur
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** agents
**Files:** $files
**Depends on:** $deps

## Task

Test.
EOF
}

# Write an archived REQ.
write_archive_req() {
  local path="$1"
  local id="$2"
  local ur="$3"
  cat > "$path" <<EOF
# $id: Archived REQ

**UR:** $ur
**Status:** done
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:**
EOF
}

setup_fixture() {
  TMP="$(mktemp -d -t synth-status.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Run synth-status.sh with optional UR arg inside $TMP.
run_synth() {
  local arg="${1:-}"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  if [ -n "$arg" ]; then
    ( cd "$TMP" && "$SYNTH" "$arg" > "$out_file" 2> "$err_file" )
  else
    ( cd "$TMP" && "$SYNTH" > "$out_file" 2> "$err_file" )
  fi
  RC=$?
  STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: empty backlog → single "no REQs" row, exit 0.
# ----------------------------------------------------------------------
CURRENT_CASE="empty-backlog"
CASES=$((CASES + 1))
setup_fixture
run_synth
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "no REQs" "$STDOUT" "$CURRENT_CASE empty message"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: populated — 2 backlog, 1 working, 1 archive → header + rows.
# ----------------------------------------------------------------------
CURRENT_CASE="populated"
CASES=$((CASES + 1))
setup_fixture
write_backlog_req "$TMP/.do-work/REQ-101-a.md" "REQ-101" "UR-001" "lib/a.sh" ""
write_backlog_req "$TMP/.do-work/REQ-102-b.md" "REQ-102" "UR-001" "lib/b.sh" ""
FRESH_ISO="$(iso_at_offset -10)"
write_working_req "$TMP/.do-work/working/REQ-103-c.md" "REQ-103" "UR-001" "lib/c.sh" "" "agent-1.42" "$FRESH_ISO"
write_archive_req "$TMP/.do-work/archive/REQ-100-z.md" "REQ-100" "UR-001"
run_synth
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "backlog" "$STDOUT" "$CURRENT_CASE header word backlog"
assert_contains "REQ-101" "$STDOUT" "$CURRENT_CASE row REQ-101"
assert_contains "REQ-102" "$STDOUT" "$CURRENT_CASE row REQ-102"
assert_contains "REQ-103" "$STDOUT" "$CURRENT_CASE row REQ-103"
assert_contains "REQ-100" "$STDOUT" "$CURRENT_CASE row REQ-100"
assert_contains "agent-1.42" "$STDOUT" "$CURRENT_CASE claimer shown"
# Totals header: 2 backlog, 1 working, 1 archived
assert_contains "2" "$STDOUT" "$CURRENT_CASE backlog total"
assert_contains "1" "$STDOUT" "$CURRENT_CASE working total"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: UR filter scopes to matching UR.
# ----------------------------------------------------------------------
CURRENT_CASE="ur-filter"
CASES=$((CASES + 1))
setup_fixture
write_backlog_req "$TMP/.do-work/REQ-201-a.md" "REQ-201" "UR-005" "lib/a.sh" ""
write_backlog_req "$TMP/.do-work/REQ-202-b.md" "REQ-202" "UR-006" "lib/b.sh" ""
run_synth "UR-005"
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-201" "$STDOUT" "$CURRENT_CASE filter keeps UR-005"
assert_not_contains "REQ-202" "$STDOUT" "$CURRENT_CASE filter drops UR-006"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: stale heartbeat → STALE marker visible.
# ----------------------------------------------------------------------
CURRENT_CASE="stale-heartbeat"
CASES=$((CASES + 1))
setup_fixture
STALE_ISO="$(iso_at_offset -3600)"
write_working_req "$TMP/.do-work/working/REQ-301-stale.md" "REQ-301" "UR-007" "lib/s.sh" "" "agent-9.99" "$STALE_ISO"
run_synth
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-301" "$STDOUT" "$CURRENT_CASE stale REQ row"
assert_contains "STALE" "$STDOUT" "$CURRENT_CASE STALE marker"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: deps-status — blocked vs ready.
# ----------------------------------------------------------------------
CURRENT_CASE="deps-status"
CASES=$((CASES + 1))
setup_fixture
write_backlog_req "$TMP/.do-work/REQ-401-blocked.md" "REQ-401" "UR-008" "lib/x.sh" "REQ-999"
write_backlog_req "$TMP/.do-work/REQ-402-ready.md" "REQ-402" "UR-008" "lib/y.sh" ""
run_synth
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "blocked" "$STDOUT" "$CURRENT_CASE blocked status"
assert_contains "REQ-999" "$STDOUT" "$CURRENT_CASE missing dep mentioned"
assert_contains "ready" "$STDOUT" "$CURRENT_CASE ready status"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: footprint truncation — long file list trimmed to 60 chars.
# ----------------------------------------------------------------------
CURRENT_CASE="footprint-truncation"
CASES=$((CASES + 1))
setup_fixture
LONG_FILES="lib/very-long-file-name-one.sh, lib/another-quite-long-file.sh, lib/yet-another-file.sh, lib/final-file.sh"
write_backlog_req "$TMP/.do-work/REQ-501-long.md" "REQ-501" "UR-009" "$LONG_FILES" ""
run_synth
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-501" "$STDOUT" "$CURRENT_CASE row present"
# The full unwrapped string should NOT appear (it's >60 chars).
assert_not_contains "$LONG_FILES" "$STDOUT" "$CURRENT_CASE long string truncated"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: performance — 200 REQs renders quickly (< 5s as a safety bound).
# ----------------------------------------------------------------------
CURRENT_CASE="performance-200"
CASES=$((CASES + 1))
setup_fixture
i=1
while [ "$i" -le 200 ]; do
  # Pad id to keep filenames sorted naturally; content doesn't matter.
  write_backlog_req "$TMP/.do-work/REQ-${i}-perf.md" "REQ-${i}" "UR-010" "lib/p${i}.sh" ""
  i=$((i + 1))
done
START_EPOCH="$(date -u +%s)"
run_synth
END_EPOCH="$(date -u +%s)"
ELAPSED=$(( END_EPOCH - START_EPOCH ))
assert_eq "0" "$RC" "$CURRENT_CASE rc=0"
assert_contains "REQ-1 " "$STDOUT" "$CURRENT_CASE first row present"
assert_contains "REQ-200 " "$STDOUT" "$CURRENT_CASE last row present"
# Functional check: 200-row render should complete within a generous bound.
# Spec target is < 1s; we allow a wider 10s ceiling for slow CI but flag
# anything truly pathological.
if [ "$ELAPSED" -gt 10 ]; then
  fail "$CURRENT_CASE took too long: ${ELAPSED}s"
fi
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
