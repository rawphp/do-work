#!/usr/bin/env bash
# Tests for lib/file-feedback.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# gh CLI is mocked in all tests — no real GitHub API calls are made.
#
# Acceptance criteria covered:
#   - Exits 0 silently when feedback.enabled is false or absent.
#   - gh CLI absence handled gracefully (warn to stderr, exit 0).
#   - Fingerprint always embedded in body as HTML comment.
#   - Sanitisation rules applied before any gh call.
#   - Lockfile prevents thundering-herd (lock contended → exit 0 silently).
#   - Tests cover: disabled (no call), new issue, existing issue (comment),
#                  missing gh, lock contended, project_repo routing.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/file-feedback.sh"

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

# Write a config.yml with given feedback settings.
# Args: $1=enabled $2=repo $3=label $4=project_repo
write_config() {
  local enabled="${1:-false}"
  local repo="${2:-}"
  local label="${3:-do-work-feedback}"
  local project_repo="${4:-}"
  local cfg="$TMP/.do-work/config.yml"

  printf 'feedback:\n' > "$cfg"
  printf '  enabled: %s\n' "$enabled" >> "$cfg"
  if [ -n "$repo" ]; then
    printf '  repo: %s\n' "$repo" >> "$cfg"
  fi
  printf '  label: %s\n' "$label" >> "$cfg"
  if [ -n "$project_repo" ]; then
    printf '  project_repo: %s\n' "$project_repo" >> "$cfg"
  fi
}

setup_fixture() {
  TMP="$(mktemp -d -t file-feedback-test.XXXXXX)"
  mkdir -p "$TMP/.do-work" "$TMP/.do-work/state"

  # Mock gh directory (added to PATH)
  MOCK_BIN="$TMP/bin"
  mkdir -p "$MOCK_BIN"

  GH_CALLS_LOG="$MOCK_BIN/gh-calls.log"

  cat > "$MOCK_BIN/gh" <<GHEOF
#!/usr/bin/env bash
# Mock gh: record invocations for assertion.
{
  printf 'ARGS:'
  for a in "\$@"; do
    printf ' [%s]' "\$a"
  done
  printf '\n'
} >> "$GH_CALLS_LOG"

# Subcommand dispatch
sub1="\${1:-}"
sub2="\${2:-}"
case "\$sub1 \$sub2" in
  "issue list")
    resp="$MOCK_BIN/gh-issue-list-response"
    if [ -f "\$resp" ]; then
      cat "\$resp"
    else
      printf '[]\n'
    fi
    ;;
  "issue create")
    printf 'https://github.com/example/repo/issues/1\n'
    ;;
  "issue comment")
    printf 'Created comment\n'
    ;;
esac
exit 0
GHEOF
  chmod +x "$MOCK_BIN/gh"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Run the script from TMP with MOCK_BIN prepended to PATH.
# Captures rc, stdout, stderr into RC_, STDOUT_, STDERR_, LOG_.
run_script() {
  local event_type="${1:-deadlock}"
  local fingerprint="${2:-deadlock:no-progress-stall:0:12345}"
  local context_json="${3:-{\}}"
  local title="${4:-Test deadlock issue}"
  local body="${5:-Something went wrong.}"

  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"

  (
    cd "$TMP" && \
    PATH="${FF_TEST_PATH:-$MOCK_BIN:/usr/bin:/bin}" \
    FEEDBACK_LOCK_DIR="$TMP/.do-work/state" \
    "$SCRIPT" "$event_type" "$fingerprint" "$context_json" "$title" "$body" \
      > "$out_file" 2> "$err_file"
  )
  RC_=$?
  STDOUT_="$(cat "$out_file" 2>/dev/null || true)"
  STDERR_="$(cat "$err_file" 2>/dev/null || true)"
  if [ -f "$GH_CALLS_LOG" ]; then
    LOG_="$(cat "$GH_CALLS_LOG")"
  else
    LOG_=""
  fi
  rm -f "$err_file" "$out_file"
}

# ---------------------------------------------------------------------------
# Test 1: Disabled — no gh calls when feedback.enabled is false
# ---------------------------------------------------------------------------
CURRENT_CASE="disabled-explicit-false"
CASES=$((CASES + 1))
setup_fixture
write_config "false" "example/system-repo"
run_script "deadlock" "fp:test:1:abc" "{}" "Test title" "Test body"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE stdout empty"
if [ -f "$GH_CALLS_LOG" ]; then
  fail "$CURRENT_CASE: gh should not be invoked when disabled"
fi
teardown_fixture

# ---------------------------------------------------------------------------
# Test 2: Disabled — no config file at all
# ---------------------------------------------------------------------------
CURRENT_CASE="disabled-no-config"
CASES=$((CASES + 1))
setup_fixture
# No config.yml written.
run_script "deadlock" "fp:test:1:abc" "{}" "Test title" "Test body"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_eq "" "$STDOUT_" "$CURRENT_CASE stdout empty"
if [ -f "$GH_CALLS_LOG" ]; then
  fail "$CURRENT_CASE: gh should not be invoked when config absent"
fi
teardown_fixture

# ---------------------------------------------------------------------------
# Test 3: New issue — gh issue create called with fingerprint in body
# ---------------------------------------------------------------------------
CURRENT_CASE="new-issue"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
run_script "deadlock" "deadlock:no-progress-stall:0:abc123" \
  "{}" "Deadlock detected" "All agents stalled."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "[issue] [list]" "$LOG_" "$CURRENT_CASE issue list called"
assert_contains "[issue] [create]" "$LOG_" "$CURRENT_CASE issue create called"
assert_not_contains "[issue] [comment]" "$LOG_" "$CURRENT_CASE no comment for new"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 4: Existing issue — gh issue comment called (not create)
# ---------------------------------------------------------------------------
CURRENT_CASE="existing-issue"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
# Mock: gh issue list returns one matching issue
printf '[{"number":42,"state":"open"}]\n' > "$MOCK_BIN/gh-issue-list-response"
run_script "deadlock" "deadlock:no-progress-stall:0:abc123" \
  "{}" "Deadlock detected" "All agents stalled."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "[issue] [list]" "$LOG_" "$CURRENT_CASE list called"
assert_contains "[issue] [comment]" "$LOG_" "$CURRENT_CASE comment called"
assert_not_contains "[issue] [create]" "$LOG_" "$CURRENT_CASE create not called"
assert_contains "[42]" "$LOG_" "$CURRENT_CASE issue number passed"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 5: Missing gh CLI — warn to stderr, exit 0 (no crash)
# ---------------------------------------------------------------------------
CURRENT_CASE="missing-gh"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
rm -f "$MOCK_BIN/gh"
# Run against a sandbox PATH that has the coreutils the script needs but NO gh,
# so `command -v gh` fails regardless of host. Simply removing the mock and
# keeping /usr/bin on PATH is not enough on CI runners, which ship a real gh in
# /usr/bin alongside the coreutils.
NOGH_BIN="$TMP/nogh-bin"
mkdir -p "$NOGH_BIN"
for _t in bash sh env awk sed grep cat printf mktemp rm mkdir date head tail tr cut sort wc dirname basename flock; do
  _p="$(command -v "$_t" 2>/dev/null || true)"
  [ -n "$_p" ] && ln -sf "$_p" "$NOGH_BIN/$_t"
done
FF_TEST_PATH="$NOGH_BIN" run_script "deadlock" "fp:1:2:3" "{}" "Title" "Body"
unset NOGH_BIN _t _p
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "gh" "$STDERR_" "$CURRENT_CASE warning mentions gh"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 6: Lock contended — second invocation exits 0 silently
# ---------------------------------------------------------------------------
CURRENT_CASE="lock-contended"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
# Acquire the lock in a background process, holding it open.
LOCK_FILE="$TMP/.do-work/state/feedback.lock"
touch "$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  (
    exec 9>"$LOCK_FILE"
    flock -x 9
    sleep 5
  ) &
  BG_PID=$!
  sleep 0.3
  run_script "deadlock" "fp:1:2:3" "{}" "Title" "Body"
  kill "$BG_PID" 2>/dev/null || true
  wait "$BG_PID" 2>/dev/null || true
  assert_eq "0" "$RC_" "$CURRENT_CASE rc (contended must exit 0)"
  if [ -f "$GH_CALLS_LOG" ]; then
    fail "$CURRENT_CASE: gh should not be called when lock contended"
  fi
else
  run_script "deadlock" "fp:1:2:3" "{}" "Title" "Body"
  assert_eq "0" "$RC_" "$CURRENT_CASE rc (no flock available)"
fi
teardown_fixture

# ---------------------------------------------------------------------------
# Test 7: project_repo routing — project-class events use project_repo
# ---------------------------------------------------------------------------
CURRENT_CASE="project-repo-routing"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo" "do-work-feedback" "example/project-repo"
run_script "ambiguous-criteria" "ambiguous:criteria:1:xyz" \
  "{}" "Ambiguous requirement" "The criteria were unclear."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "project-repo" "$LOG_" "$CURRENT_CASE project-repo used"
assert_not_contains "system-repo" "$LOG_" "$CURRENT_CASE system-repo not used"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 8: system-class events use feedback.repo
# ---------------------------------------------------------------------------
CURRENT_CASE="system-repo-routing"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo" "do-work-feedback" "example/project-repo"
run_script "deadlock" "deadlock:no-progress-stall:0:abc" \
  "{}" "Deadlock" "All agents stopped."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "system-repo" "$LOG_" "$CURRENT_CASE system-repo used"
assert_not_contains "project-repo" "$LOG_" "$CURRENT_CASE project-repo not used"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 9: project_repo fallback — when absent, project events use feedback.repo
# ---------------------------------------------------------------------------
CURRENT_CASE="project-repo-fallback"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo" "do-work-feedback" ""
run_script "verify-fail" "verify:fail:1:abc" \
  "{}" "Verify failed" "Acceptance criteria not met."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "system-repo" "$LOG_" "$CURRENT_CASE falls back to system-repo"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 10: Sanitisation — absolute paths stripped from body
# ---------------------------------------------------------------------------
CURRENT_CASE="sanitisation-paths"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
BODY="Error in /Users/tomkaczocha/EA/skills/do-work/lib/scan-stale.sh in {project} root"
run_script "deadlock" "fp:1:2:3" "{}" "Sanitise test" "$BODY"
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_not_contains "/Users/tomkaczocha" "$LOG_" "$CURRENT_CASE absolute path stripped"
assert_contains "<project>" "$LOG_" "$CURRENT_CASE project placeholder used"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 11: Fingerprint embedded as HTML comment in new issue body
# ---------------------------------------------------------------------------
CURRENT_CASE="fingerprint-embedded-create"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
FINGERPRINT="deadlock:no-progress-stall:0:unique123"
run_script "deadlock" "$FINGERPRINT" "{}" "Deadlock detected" "Agents stalled."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "[issue] [create]" "$LOG_" "$CURRENT_CASE create called"
assert_contains "fingerprint:" "$LOG_" "$CURRENT_CASE fingerprint marker present"
assert_contains "$FINGERPRINT" "$LOG_" "$CURRENT_CASE fingerprint value present"
teardown_fixture

# ---------------------------------------------------------------------------
# Test 12: Fingerprint embedded in comment body too (occurrence dedup)
# ---------------------------------------------------------------------------
CURRENT_CASE="fingerprint-embedded-comment"
CASES=$((CASES + 1))
setup_fixture
write_config "true" "example/system-repo"
printf '[{"number":7,"state":"open"}]\n' > "$MOCK_BIN/gh-issue-list-response"
FINGERPRINT="deadlock:no-progress-stall:0:unique999"
run_script "deadlock" "$FINGERPRINT" "{}" "Deadlock detected" "Stalled again."
assert_eq "0" "$RC_" "$CURRENT_CASE rc"
assert_contains "[issue] [comment]" "$LOG_" "$CURRENT_CASE comment called"
assert_contains "fingerprint:" "$LOG_" "$CURRENT_CASE fingerprint marker present in comment"
assert_contains "$FINGERPRINT" "$LOG_" "$CURRENT_CASE fingerprint value present in comment"
teardown_fixture

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
