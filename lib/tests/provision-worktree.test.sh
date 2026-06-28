#!/usr/bin/env bash
# Tests for lib/provision-worktree.sh
# Plain bash (no bats dependency). Exit non-zero on failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
PROVISIONER="$LIB_DIR/provision-worktree.sh"

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
    *"$needle"*) fail "$label: did not expect substring '$needle' in '$haystack'" ;;
  esac
}

setup_fixture() {
  TMP="$(mktemp -d -t provision-worktree-test.XXXXXX)"
  MAIN_DIR="$TMP/main"
  WT_DIR="$TMP/worktree"
  mkdir -p "$MAIN_DIR" "$WT_DIR"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

run_provisioner() {
  local main_root="$1"
  local wt_root="$2"
  local out_file="$TMP/.stdout.$$"
  local err_file="$TMP/.stderr.$$"
  bash "$PROVISIONER" "$main_root" "$wt_root" > "$out_file" 2> "$err_file"
  PROV_RC=$?
  PROV_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  PROV_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

# ----------------------------------------------------------------------
# Case 1: symlink-from-main — composer.json in worktree root, vendor in main
# ----------------------------------------------------------------------
CURRENT_CASE="symlink-from-main"
CASES=$((CASES + 1))
setup_fixture
# main has vendor/
mkdir -p "$MAIN_DIR/vendor"
touch "$MAIN_DIR/vendor/autoload.php"
# worktree has composer.json but no vendor/
touch "$WT_DIR/composer.json"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc"
assert_contains "linked: vendor" "$PROV_STDOUT" "$CURRENT_CASE stdout"
# symlink must exist and resolve into main
if [ ! -L "$WT_DIR/vendor" ]; then
  fail "$CURRENT_CASE: $WT_DIR/vendor is not a symlink"
else
  resolved="$(readlink "$WT_DIR/vendor")"
  if [ "$resolved" != "$MAIN_DIR/vendor" ]; then
    fail "$CURRENT_CASE: symlink target '$resolved' != '$MAIN_DIR/vendor'"
  fi
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: depth-1 subdir detection — server/composer.json → server/vendor
# ----------------------------------------------------------------------
CURRENT_CASE="depth-1-subdir-detection"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$MAIN_DIR/server/vendor"
touch "$MAIN_DIR/server/vendor/autoload.php"
mkdir -p "$WT_DIR/server"
touch "$WT_DIR/server/composer.json"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc"
assert_contains "linked: server/vendor" "$PROV_STDOUT" "$CURRENT_CASE stdout"
if [ ! -L "$WT_DIR/server/vendor" ]; then
  fail "$CURRENT_CASE: $WT_DIR/server/vendor is not a symlink"
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: config link_paths override — path listed in config.yml is linked
# ----------------------------------------------------------------------
CURRENT_CASE="config-link-paths"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$MAIN_DIR/.do-work"
mkdir -p "$MAIN_DIR/custom/deps"
touch "$MAIN_DIR/custom/deps/somefile"
cat > "$MAIN_DIR/.do-work/config.yml" <<EOF
worktree:
  link_paths:
    - custom/deps
  setup_command: ""
EOF
mkdir -p "$WT_DIR/custom"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc"
assert_contains "linked: custom/deps" "$PROV_STDOUT" "$CURRENT_CASE stdout"
if [ ! -L "$WT_DIR/custom/deps" ]; then
  fail "$CURRENT_CASE: $WT_DIR/custom/deps is not a symlink"
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: unprovisionable — manifest exists but no main dir, no setup_command
# ----------------------------------------------------------------------
CURRENT_CASE="unprovisionable"
CASES=$((CASES + 1))
setup_fixture
# worktree has package.json but main has no node_modules and no setup_command
touch "$WT_DIR/package.json"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc (always exit 0)"
assert_contains "unprovisionable: node_modules" "$PROV_STDOUT" "$CURRENT_CASE stdout"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: already-present skip — vendor exists in worktree, no duplicate link
# ----------------------------------------------------------------------
CURRENT_CASE="already-present-skip"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$MAIN_DIR/vendor"
touch "$MAIN_DIR/vendor/autoload.php"
# worktree already has vendor/ (real dir, e.g. previously installed)
mkdir -p "$WT_DIR/vendor"
touch "$WT_DIR/vendor/autoload.php"
touch "$WT_DIR/composer.json"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc"
# must not print linked or unprovisionable for vendor
assert_not_contains "linked: vendor" "$PROV_STDOUT" "$CURRENT_CASE stdout no linked"
assert_not_contains "unprovisionable: vendor" "$PROV_STDOUT" "$CURRENT_CASE stdout no unprovisionable"
# must still be a real dir, not a symlink
if [ -L "$WT_DIR/vendor" ]; then
  fail "$CURRENT_CASE: vendor became a symlink but was already a real dir"
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: config link_paths — deduplication when auto-detect and config overlap
# ----------------------------------------------------------------------
CURRENT_CASE="dedup-config-autodetect"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$MAIN_DIR/.do-work"
mkdir -p "$MAIN_DIR/vendor"
touch "$MAIN_DIR/vendor/autoload.php"
# both auto-detect (via composer.json) and config list 'vendor'
cat > "$MAIN_DIR/.do-work/config.yml" <<EOF
worktree:
  link_paths:
    - vendor
  setup_command: ""
EOF
touch "$WT_DIR/composer.json"
run_provisioner "$MAIN_DIR" "$WT_DIR"
assert_eq "0" "$PROV_RC" "$CURRENT_CASE rc"
# 'linked: vendor' should appear exactly once
count=$(echo "$PROV_STDOUT" | grep -c "linked: vendor" || true)
if [ "$count" -ne 1 ]; then
  fail "$CURRENT_CASE: expected 'linked: vendor' exactly once, got $count times"
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: usage error — wrong arg count exits non-zero
# ----------------------------------------------------------------------
CURRENT_CASE="usage-error"
CASES=$((CASES + 1))
setup_fixture
out_file="$TMP/.stdout.$$"
bash "$PROVISIONER" > "$out_file" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero exit when called with no args, got 0"
fi
rm -f "$out_file"
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
