#!/usr/bin/env bash
# Tests for lib/ensure-integration-base.sh
# Plain bash (no bats dependency). Exit non-zero on failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
HELPER="$LIB_DIR/ensure-integration-base.sh"

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

assert_match() {
  local regex="$1"
  local actual="$2"
  local label="$3"
  if ! printf '%s' "$actual" | grep -Eq "$regex"; then
    fail "$label: expected match /$regex/, got '$actual'"
  fi
}

# Minimal git repo on the given default branch name (main or master).
# Optional: with_remote=1 creates origin and sets origin/HEAD → origin/<branch>.
# Bare remote lives as a sibling of the fixture so it does not dirty the tree.
setup_repo() {
  local default_branch="$1"
  local with_remote="${2:-0}"
  ROOT="$(mktemp -d -t ensure-integration-base.XXXXXX)"
  TMP="$ROOT/repo"
  REMOTE="$ROOT/remote.git"
  mkdir -p "$TMP"
  (
    cd "$TMP"
    git init -q -b "$default_branch"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo "init" > README
    git add README
    git commit -q -m "init"
    if [ "$with_remote" = "1" ]; then
      git init -q --bare "$REMOTE"
      git remote add origin "$REMOTE"
      git push -q -u origin "$default_branch" >/dev/null 2>&1
      # Point origin/HEAD at the default branch (like GitHub does).
      git -C "$REMOTE" symbolic-ref HEAD "refs/heads/$default_branch"
      git remote set-head origin -a >/dev/null 2>&1 || \
        git symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$default_branch"
    fi
  )
}

teardown_fixture() {
  if [ -n "${ROOT:-}" ] && [ -d "$ROOT" ]; then
    rm -rf "$ROOT"
  elif [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  ROOT=""
  TMP=""
  REMOTE=""
}

# Run helper inside $TMP. Sets RUN_RC, RUN_STDOUT, RUN_STDERR.
# Capture files live outside the fixture so they do not dirty the tree.
run_helper() {
  local cap
  cap="$(mktemp -d -t eib-cap.XXXXXX)"
  local err_file="$cap/stderr"
  local out_file="$cap/stdout"
  (
    cd "$TMP"
    if [ "$#" -gt 0 ]; then
      bash "$HELPER" "$@"
    else
      bash "$HELPER"
    fi
  ) > "$out_file" 2> "$err_file"
  RUN_RC=$?
  RUN_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  # trim trailing newline for equality checks
  RUN_STDOUT="${RUN_STDOUT%"${RUN_STDOUT##*[![:space:]]}"}"
  RUN_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -rf "$cap"
}

current_branch() {
  ( cd "$TMP" && git branch --show-current )
}

# ----------------------------------------------------------------------
# Case 1: skip when already on a non-default (feature) branch
# ----------------------------------------------------------------------
CURRENT_CASE="skip-on-feature-branch"
CASES=$((CASES + 1))
setup_repo "main" 0
(
  cd "$TMP"
  git checkout -q -b feat/something
)
run_helper
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_eq "feat/something" "$RUN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "feat/something" "$(current_branch)" "$CURRENT_CASE still on feature"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: create ur/UR-001 when on main, clean tree, UR arg given
# ----------------------------------------------------------------------
CURRENT_CASE="create-ur-branch"
CASES=$((CASES + 1))
setup_repo "main" 0
run_helper "UR-001"
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_eq "ur/UR-001" "$RUN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "ur/UR-001" "$(current_branch)" "$CURRENT_CASE checked out"
# create-if-missing: second run should skip (already non-default) and print same
run_helper "UR-001"
assert_eq "0" "$RUN_RC" "$CURRENT_CASE re-run rc"
assert_eq "ur/UR-001" "$RUN_STDOUT" "$CURRENT_CASE re-run stdout"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: create work/* when on main, clean, no UR arg
# ----------------------------------------------------------------------
CURRENT_CASE="create-work-branch"
CASES=$((CASES + 1))
setup_repo "main" 0
run_helper
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_match '^work/[0-9]{8}T[0-9]{6}Z$' "$RUN_STDOUT" "$CURRENT_CASE stdout pattern"
assert_eq "$RUN_STDOUT" "$(current_branch)" "$CURRENT_CASE checked out work/*"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: dirty hard-stop stays on main, no stash, no branch change
# ----------------------------------------------------------------------
CURRENT_CASE="dirty-hard-stop"
CASES=$((CASES + 1))
setup_repo "main" 0
(
  cd "$TMP"
  echo "dirty" > dirty.txt
  # untracked dirt is enough for porcelain non-empty
)
run_helper "UR-002"
assert_eq "0" "$( [ "$RUN_RC" -ne 0 ] && echo 0 || echo 1 )" "$CURRENT_CASE non-zero exit (got $RUN_RC)"
# clearer:
if [ "$RUN_RC" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero exit, got 0"
fi
assert_contains "dirty" "$RUN_STDERR" "$CURRENT_CASE stderr mentions dirty"
assert_eq "main" "$(current_branch)" "$CURRENT_CASE stayed on main"
# no stash created
stash_count="$(cd "$TMP" && git stash list | wc -l | tr -d ' ')"
assert_eq "0" "$stash_count" "$CURRENT_CASE no stash"
# ur branch must not exist
if ( cd "$TMP" && git show-ref --verify --quiet refs/heads/ur/UR-002 ); then
  fail "$CURRENT_CASE: ur/UR-002 should not have been created"
fi
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: master is protected the same as main
# ----------------------------------------------------------------------
CURRENT_CASE="master-protected"
CASES=$((CASES + 1))
setup_repo "master" 0
run_helper "UR-003"
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_eq "ur/UR-003" "$RUN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "ur/UR-003" "$(current_branch)" "$CURRENT_CASE left master"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: remote HEAD missing still protects main/master
# ----------------------------------------------------------------------
CURRENT_CASE="remote-head-missing-protects-main"
CASES=$((CASES + 1))
setup_repo "main" 0
# Confirm no origin remote / no origin/HEAD
if ( cd "$TMP" && git rev-parse --abbrev-ref origin/HEAD >/dev/null 2>&1 ); then
  fail "$CURRENT_CASE: fixture unexpectedly has origin/HEAD"
fi
run_helper
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_match '^work/' "$RUN_STDOUT" "$CURRENT_CASE left main via work/*"
assert_match '^work/' "$(current_branch)" "$CURRENT_CASE not on main"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7 (extra AC): remote HEAD short name is also protected when present
# ----------------------------------------------------------------------
CURRENT_CASE="remote-head-protected"
CASES=$((CASES + 1))
setup_repo "develop" 1
# On develop with origin/HEAD → develop; should leave default
run_helper "UR-004"
assert_eq "0" "$RUN_RC" "$CURRENT_CASE rc"
assert_eq "ur/UR-004" "$RUN_STDOUT" "$CURRENT_CASE stdout"
assert_eq "ur/UR-004" "$(current_branch)" "$CURRENT_CASE left develop"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: detached HEAD hard-stop (no branch create)
# ----------------------------------------------------------------------
CURRENT_CASE="detached-hard-stop"
CASES=$((CASES + 1))
setup_repo "main" 0
(
  cd "$TMP"
  git checkout -q --detach HEAD
)
run_helper
if [ "$RUN_RC" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero exit on detached HEAD, got 0"
fi
assert_contains "detached" "$RUN_STDERR" "$CURRENT_CASE stderr mentions detached"
# still detached
show_cur="$(cd "$TMP" && git branch --show-current)"
assert_eq "" "$show_cur" "$CURRENT_CASE still detached (empty show-current)"
teardown_fixture

# ----------------------------------------------------------------------
echo "-----------------------------------------"
if [ "$FAILED" -ne 0 ]; then
  echo "FAILED: $FAILED assertion(s) across $CASES case(s)" >&2
  exit 1
fi
echo "OK: $CASES case(s) passed"
exit 0
