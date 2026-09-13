#!/usr/bin/env bash
# Wiring guard for /do-work code-review (personas + orchestrator + archive gate).
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
REPO_ROOT="$( cd "$LIB_DIR/.." && pwd )"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() { echo "FAIL [$CURRENT_CASE]: $*" >&2; FAILED=$((FAILED + 1)); }

assert_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    fail "missing $path"
  fi
}

assert_contains() {
  local needle="$1"
  local file="$2"
  local label="$3"
  if ! grep -q -F "$needle" "$file"; then
    fail "$label: expected '$needle' in $file"
  fi
}

# --- SKILL.md lists the invocable command ---
CURRENT_CASE="skill-lists-code-review"
CASES=$((CASES + 1))
assert_file "$REPO_ROOT/SKILL.md"
BEFORE=$FAILED
assert_contains "/do-work code-review" "$REPO_ROOT/SKILL.md" "$CURRENT_CASE"
if [ "$FAILED" -eq "$BEFORE" ]; then
  echo "ok: $CURRENT_CASE"
fi

# --- orchestrator exists ---
CURRENT_CASE="orchestrator-exists"
CASES=$((CASES + 1))
if [ -f "$REPO_ROOT/agents/code-review.md" ]; then
  echo "ok: $CURRENT_CASE"
else
  fail "agents/code-review.md does not exist"
fi

# --- nine persona prompt assets ---
CURRENT_CASE="nine-personas"
CASES=$((CASES + 1))
PERSONA_DIR="$REPO_ROOT/references/code-review/personas"
MISSING=""
for f in \
  correctness-reviewer.md \
  project-standards-reviewer.md \
  testing-reviewer.md \
  maintainability-reviewer.md \
  security-reviewer.md \
  performance-reviewer.md \
  api-contract-reviewer.md \
  reliability-reviewer.md \
  adversarial-reviewer.md
do
  if [ ! -f "$PERSONA_DIR/$f" ]; then
    MISSING="$MISSING $f"
  fi
done
if [ -z "$MISSING" ]; then
  echo "ok: $CURRENT_CASE"
else
  fail "missing persona file(s):$MISSING"
fi

# --- archive gate was not replaced ---
CURRENT_CASE="archive-gate-kept"
CASES=$((CASES + 1))
if [ -f "$REPO_ROOT/agents/review.md" ]; then
  echo "ok: $CURRENT_CASE"
else
  fail "agents/review.md missing — archive gate must not be replaced"
fi

echo "code-review-wiring tests: $CASES cases, $FAILED failure(s)"
[ "$FAILED" -eq 0 ]
