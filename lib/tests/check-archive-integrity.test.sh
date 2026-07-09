#!/usr/bin/env bash
# Tests for lib/check-archive-integrity.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# The guardrail asserts a REQ about to be archived as `done` is internally
# consistent: Status is done, a non-empty Closure proof exists, and no
# acceptance criterion is left unchecked. It is the deterministic gate that
# replaces trust in the worker/orchestrator prose at the persistence boundary.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/check-archive-integrity.sh"

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

new_tmp() {
  TMP="$(mktemp -d -t archive-integrity-test.XXXXXX)"
  REQ="$TMP/REQ-001-test.md"
}

teardown() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_script() {
  ERR="$TMP/err"
  OUT="$TMP/out"
  bash "$SCRIPT" "$REQ" >"$OUT" 2>"$ERR"
  RC=$?
  STDERR="$(cat "$ERR")"
}

# ---- Case 1: fully valid done REQ -> rc 0 -------------------------------------
CURRENT_CASE="valid-done"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**UR:** UR-001
**Status:** done
**Created:** 2026-06-24
**Closure proof:** verified via grep + runtime check

## Acceptance Criteria

- [x] First criterion
- [x] Second criterion

## Verification Steps
EOF
run_script
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown

# ---- Case 2: status not done -> rc 1 -----------------------------------------
CURRENT_CASE="status-not-done"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** in-progress
**Closure proof:** something

## Acceptance Criteria

- [x] First criterion
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"status not done"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown

# ---- Case 3: closure proof field absent -> rc 1 ------------------------------
CURRENT_CASE="closure-proof-absent"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** done

## Acceptance Criteria

- [x] First criterion
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"missing closure proof"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown

# ---- Case 4: closure proof present but empty -> rc 1 -------------------------
CURRENT_CASE="closure-proof-empty"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** done
**Closure proof:**

## Acceptance Criteria

- [x] First criterion
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"missing closure proof"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown

# ---- Case 5: unchecked acceptance criterion -> rc 1 --------------------------
CURRENT_CASE="unchecked-acceptance"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** done
**Closure proof:** proven

## Acceptance Criteria

- [x] First criterion
- [ ] Second criterion left unchecked

## Verification Steps
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"unchecked acceptance criteria"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
# Diagnostic must pinpoint the offending item by line number and text so the
# operator can fix it without re-scanning. The unchecked box is on line 9.
case "$STDERR" in *"L9: "*) : ;; *) fail "$CURRENT_CASE expected line ref L9 in: $STDERR" ;; esac
case "$STDERR" in *"Second criterion left unchecked"*) : ;; *) fail "$CURRENT_CASE expected item text in: $STDERR" ;; esac
teardown

# ---- Case 6: unchecked box OUTSIDE acceptance section must NOT trip -> rc 0 ---
# Manual advisory checklists legitimately carry unchecked bullets; the guardrail
# only governs the Acceptance Criteria section.
CURRENT_CASE="unchecked-outside-acceptance"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** done
**Closure proof:** proven

## Acceptance Criteria

- [x] First criterion

## Manual checks (advisory)

- [ ] Manual device check deferred
EOF
run_script
assert_eq "0" "$RC" "$CURRENT_CASE rc (unchecked box outside AC must not fail)"
teardown

# ---- Case 7: missing file / usage -> rc 1 ------------------------------------
CURRENT_CASE="missing-file"
CASES=$((CASES + 1))
new_tmp
run_script_missing() {
  ERR="$TMP/err"; bash "$SCRIPT" "$TMP/nope.md" >/dev/null 2>"$ERR"; RC=$?; STDERR="$(cat "$ERR")"
}
run_script_missing
assert_eq "1" "$RC" "$CURRENT_CASE rc"
teardown

# ---- Case 8: no acceptance section, otherwise valid -> rc 0 ------------------
CURRENT_CASE="no-acceptance-section"
CASES=$((CASES + 1))
new_tmp
cat > "$REQ" <<'EOF'
# REQ-001: Test

**Status:** done
**Closure proof:** proven

## Task

Doc-only change.
EOF
run_script
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown

echo ""
echo "check-archive-integrity tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
