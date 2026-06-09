#!/usr/bin/env bash
# Tests for lib/check-policy.sh.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/check-policy.sh"

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

setup_project() {
  TMP="$(mktemp -d -t check-policy-test.XXXXXX)"
  mkdir -p "$TMP/.do-work"
  cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
    - .env.*
  blocked_commands:
    - rm -rf
    - production

risk:
  require_review:
    - migrations
    - auth
    - billing
    - payments
    - files_changed_over: 2
    - acceptance_criteria_over: 2
EOF
  FILES="$TMP/files.txt"
  COMMANDS="$TMP/commands.txt"
  REQ="$TMP/REQ-001-test.md"
  : > "$FILES"
  : > "$COMMANDS"
  cat > "$REQ" <<'EOF'
# REQ-001

## Acceptance Criteria

- [ ] one
- [ ] two
EOF
}

teardown_project() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

run_policy() {
  OUT="$TMP/out"
  ERR="$TMP/err"
  bash "$SCRIPT" --project "$TMP" --files "$FILES" --commands "$COMMANDS" --req "$REQ" >"$OUT" 2>"$ERR"
  RC=$?
  STDOUT="$(cat "$OUT")"
}

CURRENT_CASE="blocked-env"
CASES=$((CASES + 1))
setup_project
printf '.env\n' > "$FILES"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_path: .env matches .env"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="blocked-env-glob"
CASES=$((CASES + 1))
setup_project
printf '.env.local\n' > "$FILES"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_path: .env.local matches .env.*"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="blocked-command"
CASES=$((CASES + 1))
setup_project
printf 'rm -rf /tmp/example\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: rm -rf"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="allowed-adjacent-path"
CASES=$((CASES + 1))
setup_project
printf 'src/env.ts\n' > "$FILES"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

CURRENT_CASE="review-required-path"
CASES=$((CASES + 1))
setup_project
printf 'database/migrations/001_create.sql\n' > "$FILES"
run_policy
assert_eq "2" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"review_required: migrations"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="review-required-file-count"
CASES=$((CASES + 1))
setup_project
printf 'a\nb\nc\n' > "$FILES"
run_policy
assert_eq "2" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"review_required: files_changed_over (3 > 2)"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="review-required-ac-count"
CASES=$((CASES + 1))
setup_project
cat >> "$REQ" <<'EOF'
- [ ] three
EOF
run_policy
assert_eq "2" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"review_required: acceptance_criteria_over (3 > 2)"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

echo ""
echo "check-policy tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
