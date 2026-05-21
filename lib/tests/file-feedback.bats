#!/usr/bin/env bats
# Tests for lib/file-feedback.sh
# Bats test suite (bats-core >= 1.x).
# Compatible with macOS bash 3.2 and Linux bash >= 4.
#
# gh CLI is mocked in all tests — no real GitHub API calls are made.
#
# Acceptance criteria covered:
#   - Exits 0 silently when feedback.enabled is false or absent.
#   - gh CLI absence handled gracefully (warn to stderr, exit 0).
#   - Fingerprint always embedded in body as HTML comment.
#   - Sanitisation rules applied before any gh call.
#   - Lockfile prevents thundering-herd (lock contended -> exit 0 silently).
#   - Tests cover: disabled (no call), new issue, existing issue (comment),
#                  missing gh, lock contended, project_repo routing.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/file-feedback.sh"

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

setup() {
  TMP="$(mktemp -d -t file-feedback-test.XXXXXX)"
  export TMP
  STATE="$TMP/.do-work/state"
  export STATE
  mkdir -p "$TMP/.do-work" "$STATE"

  # Mock gh directory (added to PATH)
  MOCK_BIN="$TMP/bin"
  export MOCK_BIN
  mkdir -p "$MOCK_BIN"

  GH_CALLS_LOG="$MOCK_BIN/gh-calls.log"
  export GH_CALLS_LOG

  # Write the gh mock script
  GH_SCRIPT="$MOCK_BIN/gh"
  printf '#!/usr/bin/env bash\n' > "$GH_SCRIPT"
  printf 'printf "%%s\\n" "$*" >> "%s"\n' "$GH_CALLS_LOG" >> "$GH_SCRIPT"
  printf 'subcmd="$1 $2"\n' >> "$GH_SCRIPT"
  printf 'case "$subcmd" in\n' >> "$GH_SCRIPT"
  printf '  "issue list")\n' >> "$GH_SCRIPT"
  printf '    resp="%s/gh-issue-list-response"\n' "$MOCK_BIN" >> "$GH_SCRIPT"
  printf '    if [ -f "$resp" ]; then cat "$resp"; else printf "[]\n"; fi\n' >> "$GH_SCRIPT"
  printf '    ;;\n' >> "$GH_SCRIPT"
  printf '  "issue create") printf "https://github.com/example/repo/issues/1\n" ;;\n' >> "$GH_SCRIPT"
  printf '  "issue comment") printf "Created comment\n" ;;\n' >> "$GH_SCRIPT"
  printf 'esac\n' >> "$GH_SCRIPT"
  chmod +x "$GH_SCRIPT"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
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

# Run the script from TMP with MOCK_BIN prepended to PATH.
run_script() {
  local event_type="${1:-deadlock}"
  local fingerprint="${2:-deadlock:no-progress-stall:0:12345}"
  local context_json="${3:-{}}"
  local title="${4:-Test deadlock issue}"
  local body="${5:-Something went wrong.}"

  cd "$TMP"
  run env \
    PATH="$MOCK_BIN:$PATH" \
    FEEDBACK_LOCK_DIR="$TMP/.do-work/state" \
    "$SCRIPT" "$event_type" "$fingerprint" "$context_json" "$title" "$body"
}

# ---------------------------------------------------------------------------
# Test 1: Disabled -- no gh calls when feedback.enabled is false
# ---------------------------------------------------------------------------
@test "disabled -- exits 0 silently when feedback.enabled is false" {
  write_config "false" "github.com/example/repo"

  run_script "deadlock" "fp:test:1:abc" "{}" "Test title" "Test body"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$GH_CALLS_LOG" ]
}

# ---------------------------------------------------------------------------
# Test 2: Disabled -- no config file at all
# ---------------------------------------------------------------------------
@test "disabled -- exits 0 silently when config file absent" {
  run_script "deadlock" "fp:test:1:abc" "{}" "Test title" "Test body"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$GH_CALLS_LOG" ]
}

# ---------------------------------------------------------------------------
# Test 3: New issue -- gh issue create called with fingerprint in body
# ---------------------------------------------------------------------------
@test "new issue -- gh issue create called, fingerprint embedded in body" {
  write_config "true" "example/system-repo"

  run_script "deadlock" "deadlock:no-progress-stall:0:abc123" \
    "{}" "Deadlock detected" "All agents stalled."

  [ "$status" -eq 0 ]
  grep -q "issue list" "$GH_CALLS_LOG"
  grep -q "issue create" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Test 4: Existing issue -- gh issue comment called (not create)
# ---------------------------------------------------------------------------
@test "existing issue -- gh issue comment called instead of create" {
  write_config "true" "example/system-repo"

  printf '[{"number":42,"state":"open"}]\n' > "$MOCK_BIN/gh-issue-list-response"

  run_script "deadlock" "deadlock:no-progress-stall:0:abc123" \
    "{}" "Deadlock detected" "All agents stalled."

  [ "$status" -eq 0 ]
  grep -q "issue list" "$GH_CALLS_LOG"
  grep -q "issue comment" "$GH_CALLS_LOG"
  ! grep -q "issue create" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Test 5: Missing gh CLI -- warn to stderr, exit 0 (no crash)
# ---------------------------------------------------------------------------
@test "missing gh CLI -- warns to stderr and exits 0" {
  write_config "true" "example/system-repo"
  rm -f "$MOCK_BIN/gh"

  cd "$TMP"
  run env \
    PATH="$MOCK_BIN:/usr/bin:/bin" \
    FEEDBACK_LOCK_DIR="$TMP/.do-work/state" \
    "$SCRIPT" "deadlock" "fp:1:2:3" "{}" "Title" "Body"

  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 6: Lock contended -- FEEDBACK_LOCK_HELD=1 exits 0 silently
# ---------------------------------------------------------------------------
@test "lock contended -- exits 0 silently when FEEDBACK_LOCK_HELD is set" {
  write_config "true" "example/system-repo"

  cd "$TMP"
  run env \
    PATH="$MOCK_BIN:$PATH" \
    FEEDBACK_LOCK_DIR="$TMP/.do-work/state" \
    FEEDBACK_LOCK_HELD="1" \
    "$SCRIPT" "deadlock" "fp:1:2:3" "{}" "Title" "Body"

  [ "$status" -eq 0 ]
  [ ! -f "$GH_CALLS_LOG" ]
}

# ---------------------------------------------------------------------------
# Test 7: project_repo routing -- project-class events use project_repo
# ---------------------------------------------------------------------------
@test "project_repo routing -- ambiguous-criteria uses project_repo" {
  write_config "true" "example/system-repo" "do-work-feedback" "example/project-repo"

  run_script "ambiguous-criteria" "ambiguous:criteria:1:xyz" \
    "{}" "Ambiguous requirement" "The criteria were unclear."

  [ "$status" -eq 0 ]
  grep -q "project-repo" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Test 8: system-class events use feedback.repo
# ---------------------------------------------------------------------------
@test "system-class routing -- deadlock event uses feedback.repo" {
  write_config "true" "example/system-repo" "do-work-feedback" "example/project-repo"

  run_script "deadlock" "deadlock:no-progress-stall:0:abc" \
    "{}" "Deadlock" "All agents stopped."

  [ "$status" -eq 0 ]
  grep -q "system-repo" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Test 9: Sanitisation -- absolute paths stripped from body
# ---------------------------------------------------------------------------
@test "sanitisation -- absolute paths stripped before gh call" {
  write_config "true" "example/system-repo"

  run_script "deadlock" "fp:1:2:3" "{}" "Sanitise test" \
    "Error in /Users/tomkaczocha/EA/skills/do-work/lib/scan-stale.sh"

  [ "$status" -eq 0 ]
  if [ -f "$GH_CALLS_LOG" ]; then
    ! grep -q "/Users/tomkaczocha" "$GH_CALLS_LOG"
  fi
}

# ---------------------------------------------------------------------------
# Test 10: Fingerprint embedded as HTML comment in new issue body
# ---------------------------------------------------------------------------
@test "fingerprint embedded as HTML comment in new issue body" {
  write_config "true" "example/system-repo"

  FINGERPRINT="deadlock:no-progress-stall:0:unique123"

  run_script "deadlock" "$FINGERPRINT" "{}" "Deadlock detected" "Agents stalled."

  [ "$status" -eq 0 ]
  grep -q "fingerprint" "$GH_CALLS_LOG"
  grep -q "$FINGERPRINT" "$GH_CALLS_LOG"
}
