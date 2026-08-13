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

# Build a project whose blocked_commands list matches the shipped defaults
# (regex/word-boundary semantics plus the force-class git entries).
setup_project_defaults() {
  TMP="$(mktemp -d -t check-policy-test.XXXXXX)"
  mkdir -p "$TMP/.do-work"
  cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
    - .env.*
  blocked_commands:
    - rm -rf
    - git push --force
    - git push -f
    - git reset --hard
    - git checkout --

risk:
  require_review:
    - migrations
    - auth
    - billing
    - payments
    - files_changed_over: 99
    - acceptance_criteria_over: 99
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

CURRENT_CASE="allowed-env-example"
CASES=$((CASES + 1))
setup_project
printf '.env.example\n' > "$FILES"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

CURRENT_CASE="allowed-env-example-nested"
CASES=$((CASES + 1))
setup_project
printf 'packages/web/.env.example\n' > "$FILES"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

CURRENT_CASE="explicit-excluded-path"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - docs/*
  excluded_paths:
    - docs/public.md
  blocked_commands: []
risk:
  require_review: []
EOF
printf 'docs/public.md\n' > "$FILES"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
printf 'docs/secret.md\n' > "$FILES"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE still-blocked rc"
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

# --- REQ-205: blocked_commands matching semantics ---

# rm-flag normalisation: -rf, -fr, and split -r -f must all be blocked by `rm -rf`.
CURRENT_CASE="rm-rf-canonical"
CASES=$((CASES + 1))
setup_project
printf 'rm -rf /tmp/x\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: rm -rf"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="rm-fr-reordered"
CASES=$((CASES + 1))
setup_project
printf 'rm -fr /tmp/x\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: rm -rf"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="rm-r-f-split"
CASES=$((CASES + 1))
setup_project
printf 'rm -r -f /tmp/x\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: rm -rf"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

# Word-boundary semantics: `production` (regex default) does NOT block a command
# that merely contains the word as a path fragment.
CURRENT_CASE="production-fragment-allowed"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
  blocked_commands:
    - production
risk:
  require_review:
    - files_changed_over: 99
    - acceptance_criteria_over: 99
EOF
printf 'cat docs/production-notes.md\n' > "$COMMANDS"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

# A bare `production` token IS still blocked (word boundary on both sides).
CURRENT_CASE="production-word-blocked"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
  blocked_commands:
    - production
risk:
  require_review:
    - files_changed_over: 99
    - acceptance_criteria_over: 99
EOF
printf 'deploy --env production now\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: production"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

# substr: escape restores literal-substring matching for callers that want it.
CURRENT_CASE="substr-production-blocks-fragment"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
  blocked_commands:
    - "substr:production"
risk:
  require_review:
    - files_changed_over: 99
    - acceptance_criteria_over: 99
EOF
printf 'bash deploy-production.sh\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: substr:production"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

# Force-class git defaults: each new default entry blocks its command.
CURRENT_CASE="git-push-force-long"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git push --force origin main\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: git push --force"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="git-push-force-short"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git push -f origin main\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: git push -f"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="git-reset-hard"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git reset --hard HEAD~1\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: git reset --hard"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

CURRENT_CASE="git-checkout-doubledash"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git checkout -- src/app.ts\n' > "$COMMANDS"
run_policy
assert_eq "1" "$RC" "$CURRENT_CASE rc"
case "$STDOUT" in *"blocked_command: git checkout --"*) : ;; *) fail "$CURRENT_CASE stdout" ;; esac
teardown_project

# Self-test: the do-work system's own legitimate git commands must NOT be blocked
# by the new defaults.
CURRENT_CASE="self-test-git-mv"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git mv old.md new.md\n' > "$COMMANDS"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

CURRENT_CASE="self-test-git-worktree-remove"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git worktree remove .worktrees/req-1\n' > "$COMMANDS"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

CURRENT_CASE="self-test-git-branch-d"
CASES=$((CASES + 1))
setup_project_defaults
printf 'git branch -d req/REQ-001\n' > "$COMMANDS"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

# Regex metacharacters in a default-mode entry are treated as regex, but a
# `substr:` entry containing them is matched literally (no accidental wildcard).
CURRENT_CASE="substr-literal-dot"
CASES=$((CASES + 1))
setup_project
cat > "$TMP/.do-work/config.yml" <<'EOF'
security:
  blocked_paths:
    - .env
  blocked_commands:
    - "substr:a.b"
risk:
  require_review:
    - files_changed_over: 99
    - acceptance_criteria_over: 99
EOF
printf 'echo axb\n' > "$COMMANDS"
run_policy
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_project

echo ""
echo "check-policy tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
