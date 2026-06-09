#!/usr/bin/env bash
# Tests for installer target resolution.
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
TARGET="$LIB_DIR/install-target.sh"

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

run_resolve() {
  local env_name="$1"
  OUT="$(bash "$TARGET" --resolve "$env_name" "/tmp/home")"
  RC=$?
}

CURRENT_CASE="claude-target"
CASES=$((CASES + 1))
run_resolve claude
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "/tmp/home/.claude/skills/do-work|/tmp/home/.claude/backups|Claude Code" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="codex-target"
CASES=$((CASES + 1))
run_resolve codex
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "/tmp/home/.codex/skills/do-work|/tmp/home/.codex/backups|Codex" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="invalid-env"
CASES=$((CASES + 1))
OUT="$(bash "$TARGET" --resolve invalid "/tmp/home" 2>/dev/null)"
RC=$?
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_eq "" "$OUT" "$CURRENT_CASE stdout"

echo ""
echo "install-target tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0

