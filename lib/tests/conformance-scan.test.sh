#!/usr/bin/env bash
# Tests for lib/conformance-scan.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/conformance-scan.sh"

FAILED=0
CASES=0
CURRENT_CASE=""
TMP=""

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
  TMP="$(mktemp -d -t conformance-scan-test.XXXXXX)"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_scan() {
  local project_root="$1"
  local out_file="$TMP/.stdout.$$"
  local err_file="$TMP/.stderr.$$"
  bash "$SCRIPT" "$project_root" > "$out_file" 2> "$err_file"
  SCAN_RC=$?
  SCAN_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  SCAN_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

CURRENT_CASE="conformant-tree"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work/archive"
run_scan "$TMP/project"
assert_eq "0" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="legacy-dir"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/do-work"
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "legacy-dir safe-blocking do-work/ exists and .do-work/ does not" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="dir-conflict"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/do-work" "$TMP/project/.do-work"
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "dir-conflict blocking both do-work/ and .do-work/ exist" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="pending-dir-empty"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work/pending"
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "pending-dir destructive .do-work/pending/ exists (0 REQ files)" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="pending-dir-non-empty"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work/pending"
touch "$TMP/project/.do-work/pending/REQ-001-one.md"
touch "$TMP/project/.do-work/pending/REQ-002-two.md"
touch "$TMP/project/.do-work/pending/notes.txt"
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "pending-dir destructive .do-work/pending/ exists (2 REQ files)" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="pending-dir-ignores-matching-directories"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work/pending/REQ-999-dir.md"
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "pending-dir destructive .do-work/pending/ exists (0 REQ files)" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="stale-config-key-present"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work"
cat > "$TMP/project/.do-work/config.yml" <<'EOF'
notifications:
  on_pending_validation: ""
EOF
run_scan "$TMP/project"
assert_eq "1" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "stale-config-key destructive notifications.on_pending_validation" "$SCAN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="stale-config-key-clean"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work"
cat > "$TMP/project/.do-work/config.yml" <<'EOF'
worktree:
  link_paths: []
  setup_command: ""

routing: []
EOF
run_scan "$TMP/project"
assert_eq "0" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="stale-config-key-user-custom"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work"
cat > "$TMP/project/.do-work/config.yml" <<'EOF'
notifications:
  on_custom_hook: "echo hi"

my_custom_section:
  my_custom_key: true
EOF
run_scan "$TMP/project"
assert_eq "0" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="stale-config-key-comment-only"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/project/.do-work"
cat > "$TMP/project/.do-work/config.yml" <<'EOF'
# notifications.on_pending_validation was removed in UR-039; do not re-add it.
notifications:
  on_new_hook: ""
EOF
run_scan "$TMP/project"
assert_eq "0" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_eq "" "$SCAN_STDERR" "$CURRENT_CASE stderr empty"
teardown_fixture

CURRENT_CASE="usage-missing-arg"
CASES=$((CASES + 1))
setup_fixture
out_file="$TMP/.stdout.$$"
err_file="$TMP/.stderr.$$"
bash "$SCRIPT" > "$out_file" 2> "$err_file"
SCAN_RC=$?
SCAN_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
SCAN_STDERR="$(cat "$err_file" 2>/dev/null || true)"
rm -f "$out_file" "$err_file"
assert_eq "2" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_contains "Usage: conformance-scan.sh <project-root>" "$SCAN_STDERR" "$CURRENT_CASE stderr usage"
teardown_fixture

CURRENT_CASE="usage-invalid-root"
CASES=$((CASES + 1))
setup_fixture
run_scan "$TMP/missing"
assert_eq "2" "$SCAN_RC" "$CURRENT_CASE rc"
assert_eq "" "$SCAN_STDOUT" "$CURRENT_CASE stdout empty"
assert_contains "Usage: conformance-scan.sh <project-root>" "$SCAN_STDERR" "$CURRENT_CASE stderr usage"
teardown_fixture

echo ""
echo "conformance-scan tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
