#!/usr/bin/env bats
# Tests for lib/cycle-check.sh
# Bats test suite (bats-core >= 1.x).
# Compatible with macOS bash 3.2 and Linux bash >= 4.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CHECKER="$SCRIPT_DIR/cycle-check.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write a REQ file to the backlog (root of .do-work/).
# Args: $1=path, $2=req-id, $3=ur, $4=depends-on
write_req() {
  local path="$1" id="$2" ur="$3" deps="$4"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** $ur
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:** $deps
EOF
}

setup() {
  TMP="$(mktemp -d -t cycle-check-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/working"
  mkdir -p "$TMP/.do-work/archive"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

run_checker() {
  cd "$TMP"
  run "$CHECKER" "$@"
}

# ---------------------------------------------------------------------------
# Test 1: empty graph
# ---------------------------------------------------------------------------
@test "empty graph — no REQs — exit 0 silent" {
  run_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test 2: linear chain no cycle
# ---------------------------------------------------------------------------
@test "linear chain no cycle — exit 0 silent" {
  write_req "$TMP/.do-work/REQ-001-a.md" "REQ-001" "UR-001" ""
  write_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001" "REQ-001"
  write_req "$TMP/.do-work/REQ-003-c.md" "REQ-003" "UR-001" "REQ-002"
  write_req "$TMP/.do-work/REQ-004-d.md" "REQ-004" "UR-001" "REQ-003"
  write_req "$TMP/.do-work/REQ-005-e.md" "REQ-005" "UR-001" "REQ-004"
  run_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test 3: single cycle
# ---------------------------------------------------------------------------
@test "single cycle — exit 1 prints both nodes" {
  write_req "$TMP/.do-work/REQ-007-x.md" "REQ-007" "UR-001" "REQ-009"
  write_req "$TMP/.do-work/REQ-009-y.md" "REQ-009" "UR-001" "REQ-007"
  run_checker
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REQ-007"
  echo "$output" | grep -q "REQ-009"
}

# ---------------------------------------------------------------------------
# Test 4: self-loop
# ---------------------------------------------------------------------------
@test "self-loop — exit 1 prints node" {
  write_req "$TMP/.do-work/REQ-010-self.md" "REQ-010" "UR-001" "REQ-010"
  run_checker
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REQ-010"
}

# ---------------------------------------------------------------------------
# Test 5: UR-scoped ignores dep edges outside UR
# ---------------------------------------------------------------------------
@test "UR-scoped dep edge to different UR not followed" {
  write_req "$TMP/.do-work/REQ-020-a.md" "REQ-020" "UR-002" "REQ-100"
  write_req "$TMP/.do-work/REQ-100-b.md" "REQ-100" "UR-999" "REQ-020"
  run_checker "UR-002"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test 6: UR-scoped cycle within UR detected
# ---------------------------------------------------------------------------
@test "UR-scoped cycle within UR detected" {
  write_req "$TMP/.do-work/REQ-030-a.md" "REQ-030" "UR-003" "REQ-031"
  write_req "$TMP/.do-work/REQ-031-b.md" "REQ-031" "UR-003" "REQ-030"
  run_checker "UR-003"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REQ-03"
}

# ---------------------------------------------------------------------------
# Test 7: scans across backlog working archive
# ---------------------------------------------------------------------------
@test "scans across backlog working archive" {
  write_req "$TMP/.do-work/REQ-040-a.md"         "REQ-040" "UR-004" "REQ-041"
  write_req "$TMP/.do-work/working/REQ-041-b.md" "REQ-041" "UR-004" "REQ-040"
  run_checker
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Test 8: linear chain of 100 REQs no stack overflow
# ---------------------------------------------------------------------------
@test "linear chain of 100 REQs no stack overflow" {
  write_req "$TMP/.do-work/REQ-200-a.md" "REQ-200" "UR-005" ""
  local i prev
  for i in $(seq 201 300); do
    prev=$((i - 1))
    write_req "$TMP/.do-work/REQ-${i}-x.md" "REQ-${i}" "UR-005" "REQ-${prev}"
  done
  run_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
