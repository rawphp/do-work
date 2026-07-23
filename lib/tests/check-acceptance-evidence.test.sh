#!/usr/bin/env bash
# Tests for lib/check-acceptance-evidence.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/check-acceptance-evidence.sh"

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

setup_fixture() {
  TMP="$(mktemp -d -t acceptance-evidence-test.XXXXXX)"
  REQ="$TMP/REQ-001-test.md"
  REPORT="$TMP/report.yml"
  cat > "$REQ" <<'EOF'
# REQ-001: Test

## Acceptance Criteria

- [ ] First criterion
- [ ] Second criterion

## Verification Steps
EOF
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_script() {
  ERR="$TMP/err"
  OUT="$TMP/out"
  bash "$SCRIPT" "$REQ" "$REPORT" >"$OUT" 2>"$ERR"
  RC=$?
  STDERR="$(cat "$ERR")"
}

CURRENT_CASE="valid-evidence"
CASES=$((CASES + 1))
setup_fixture
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: test
        ref: tests/FooTest.php
  AC2:
    status: passed
    evidence:
      - type: runtime
        ref: curl returned 200
EOF
run_script
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

CURRENT_CASE="missing-ac"
CASES=$((CASES + 1))
setup_fixture
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: test
        ref: tests/FooTest.php
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"missing acceptance evidence: AC2"*) : ;; *) fail "$CURRENT_CASE stderr" ;; esac
teardown_fixture

CURRENT_CASE="failed-status"
CASES=$((CASES + 1))
setup_fixture
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: failed
    evidence:
      - type: test
        ref: tests/FooTest.php
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"acceptance evidence not passed: AC1"*) : ;; *) fail "$CURRENT_CASE stderr" ;; esac
teardown_fixture

CURRENT_CASE="missing-evidence-item"
CASES=$((CASES + 1))
setup_fixture
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"acceptance evidence missing evidence item: AC1"*) : ;; *) fail "$CURRENT_CASE stderr" ;; esac
teardown_fixture

# --- UR-043: type ui requires existing ui-evidence screenshot ---

CURRENT_CASE="ui-missing-ref"
CASES=$((CASES + 1))
setup_fixture
# Simulate project layout so resolve_project_root finds TMP as project
mkdir -p "$TMP/.do-work"
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: ui
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"acceptance evidence ui missing screenshot ref: AC1"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown_fixture

CURRENT_CASE="ui-text-only-ref"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/.do-work"
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: ui
        ref: looked fine in the browser
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"acceptance evidence ui ref is not an image path: AC1"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown_fixture

CURRENT_CASE="ui-missing-file"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/.do-work"
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: ui
        ref: .do-work/user-requests/UR-001/ui-evidence/REQ-001-step-1.png
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDERR" in *"acceptance evidence ui screenshot file missing: AC1"*) : ;; *) fail "$CURRENT_CASE stderr: $STDERR" ;; esac
teardown_fixture

CURRENT_CASE="ui-valid-screenshot"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/.do-work/user-requests/UR-001/ui-evidence"
# Minimal non-empty PNG-like file (existence check only)
printf 'fake-png' > "$TMP/.do-work/user-requests/UR-001/ui-evidence/REQ-001-step-1.png"
# REQ lives under project so PROJECT_ROOT resolves to TMP
REQ="$TMP/.do-work/REQ-001-test.md"
cat > "$REQ" <<'EOF'
# REQ-001: Test

## Acceptance Criteria

- [ ] First criterion
- [ ] Second criterion

## Verification Steps
EOF
cat > "$REPORT" <<'EOF'
acceptance:
  AC1:
    status: passed
    evidence:
      - type: ui
        ref: .do-work/user-requests/UR-001/ui-evidence/REQ-001-step-1.png
  AC2:
    status: passed
    evidence:
      - type: file
        ref: README.md
EOF
run_script
assert_eq "0" "$RC" "$CURRENT_CASE rc (stderr=$STDERR)"
teardown_fixture

echo ""
echo "check-acceptance-evidence tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0

