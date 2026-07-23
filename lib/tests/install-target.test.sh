#!/usr/bin/env bash
# Tests for hub-only installer target resolution.
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: unexpectedly contains '$needle'" ;;
  esac
}

# --- hub default under synthetic HOME ---
CURRENT_CASE="hub-default"
CASES=$((CASES + 1))
unset AGENTS_SKILLS_HUB 2>/dev/null || true
OUT="$(bash "$TARGET" --resolve "/tmp/home")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "/tmp/home/.agents/skills/do-work|/tmp/home/.agents/skills/.backups|skills hub" "$OUT" "$CURRENT_CASE output"
assert_not_contains "$OUT" ".claude/skills" "$CURRENT_CASE no-claude"
assert_not_contains "$OUT" ".codex/skills" "$CURRENT_CASE no-codex"

# --- AGENTS_SKILLS_HUB override wins over home_dir ---
CURRENT_CASE="hub-override"
CASES=$((CASES + 1))
OUT="$(AGENTS_SKILLS_HUB="/tmp/custom-hub" bash "$TARGET" --resolve "/tmp/home")"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "/tmp/custom-hub/do-work|/tmp/custom-hub/.backups|skills hub" "$OUT" "$CURRENT_CASE output"

# --- no dual-env CLI: --resolve with env name is not required; bare resolve works ---
CURRENT_CASE="no-env-arg-required"
CASES=$((CASES + 1))
unset AGENTS_SKILLS_HUB 2>/dev/null || true
OUT="$(bash "$TARGET" --resolve)"
RC=$?
assert_eq "0" "$RC" "$CURRENT_CASE rc"
# HOME-based path must end with .agents/skills/do-work|...|.backups|skills hub
case "$OUT" in
  *"/.agents/skills/do-work|"*"/.agents/skills/.backups|skills hub") ;;
  *) fail "$CURRENT_CASE output shape: got '$OUT'" ;;
esac

# --- dual env names are not current behaviour ---
CURRENT_CASE="dual-env-not-current"
CASES=$((CASES + 1))
# Invoking with a legacy env token must not resolve to claude/codex skill dirs.
# Hub API ignores the env name if a second positional is passed for home only;
# callers should use --resolve [home]. Document that claude/codex are not targets.
SRC="$(cat "$TARGET")"
assert_not_contains "$SRC" ".claude/skills/do-work" "$CURRENT_CASE source-no-claude-path"
assert_not_contains "$SRC" ".codex/skills/do-work" "$CURRENT_CASE source-no-codex-path"

echo ""
echo "install-target tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
