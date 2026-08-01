#!/usr/bin/env bash
# Tests for lib/doc-lint.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# doc-lint.sh greps the live docs for known stale ("drifted") patterns that
# the UR-035 Part 1 fixes retired, and exits non-zero with file:line diagnostics
# when any fire. These tests plant one violation per check and assert exit 1,
# plant clean content and assert exit 0, and assert excluded paths are skipped.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/doc-lint.sh"

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

setup_fixture() {
  TMP="$(mktemp -d -t doc-lint-test.XXXXXX)"
  mkdir -p "$TMP/agents" "$TMP/docs"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# run_lint [explicit-path]
# With no arg, scans $TMP as the repo root (cd in). With an arg, passes it as
# an explicit scan target (single file or dir) via DOC_LINT_PATHS.
run_lint() {
  local target="${1:-}"
  if [ -n "$target" ]; then
    OUT="$(cd "$TMP" && DOC_LINT_PATHS="$target" bash "$SCRIPT" 2>&1)"
  else
    OUT="$(cd "$TMP" && bash "$SCRIPT" 2>&1)"
  fi
  RC=$?
}

# --- Clean repo: every default root present, no violations -> exit 0 ---
CURRENT_CASE="clean-repo-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# Skill\n\nWorkers run in worktrees only.\n' > "$TMP/SKILL.md"
printf '# Readme\n\nA clean doc with no retired terms.\n' > "$TMP/README.md"
printf '# How it works\n\nWorktree-always is canonical.\n' > "$TMP/docs/HOW-IT-WORKS.md"
printf '# Run Worker\n\n> **JUDGMENT:** J2 explained below.\n\n| # | Step | Decision |\n|---|---|---|\n| J2 | Step 8 | classify |\n' > "$TMP/agents/run-worker.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- same-branch as a stale usage -> exit 1 ---
CURRENT_CASE="same-branch-stale-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Run Worker\n\nisolation: same-branch     # choose per REQ\n' > "$TMP/agents/run-worker.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "agents/run-worker.md:3" "$OUT" "$CURRENT_CASE file:line"
assert_contains "same-branch" "$OUT" "$CURRENT_CASE pattern name"
teardown_fixture

# --- same-branch inside a retirement note is allowed -> exit 0 ---
CURRENT_CASE="same-branch-retirement-note-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# How it works\n\nWorktree-always is canonical; same-branch execution is retired.\n' > "$TMP/docs/HOW-IT-WORKS.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- --creative retired flag -> exit 1 ---
CURRENT_CASE="creative-flag-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Ideate\n\nInvoked by start when the --creative flag is set.\n' > "$TMP/agents/ideate.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "--creative" "$OUT" "$CURRENT_CASE pattern name"
teardown_fixture

# --- --grill retired flag -> exit 1 ---
CURRENT_CASE="grill-flag-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Question\n\nReferences the --grill flag here.\n' > "$TMP/agents/question.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "--grill" "$OUT" "$CURRENT_CASE pattern name"
teardown_fixture

# --- "resume or abort" pre-flight contradiction -> exit 1 ---
CURRENT_CASE="resume-or-abort-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Skill\n\nIf a REQ exists in working, report it and ask: resume or abort?\n' > "$TMP/SKILL.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "resume or abort" "$OUT" "$CURRENT_CASE pattern name"
teardown_fixture

# --- judgment marker missing from the file's own table -> exit 1 ---
CURRENT_CASE="judgment-marker-orphan-exit-1"
CASES=$((CASES + 1))
setup_fixture
# J4 is referenced inline but the table only declares J2.
printf '# Run Worker\n\n| # | Step | Decision |\n|---|---|---|\n| J2 | Step 8 | classify |\n\n> **JUDGMENT:** J4 at this step.\n' > "$TMP/agents/run-worker.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "J4" "$OUT" "$CURRENT_CASE marker id"
teardown_fixture

# --- judgment marker present in the table -> exit 0 ---
CURRENT_CASE="judgment-marker-in-table-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# Run Worker\n\n| # | Step | Decision |\n|---|---|---|\n| J2 | Step 8 | classify |\n\n> **JUDGMENT:** J2 at this step.\n' > "$TMP/agents/run-worker.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- excluded paths (.do-work/, CHANGELOG.md, docs/superpowers/) are never scanned ---
CURRENT_CASE="excluded-do-work-archive-exit-0"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/.do-work/archive"
printf '# Archived REQ\n\nisolation: same-branch\n' > "$TMP/.do-work/archive/REQ-001-old.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

CURRENT_CASE="excluded-changelog-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# Changelog\n\nRetired the --grill flag and same-branch mode.\n' > "$TMP/CHANGELOG.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

CURRENT_CASE="excluded-superpowers-spec-exit-0"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/docs/superpowers/specs"
printf '# Old design\n\nThe --grill flag triggered the question agent; same-branch was the default.\n' > "$TMP/docs/superpowers/specs/old-design.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- explicit single-file target via DOC_LINT_PATHS (verification step 3 shape) ---
CURRENT_CASE="explicit-path-target-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Fixture\n\nisolation: same-branch\n' > "$TMP/dl-fixture.md"
run_lint "$TMP/dl-fixture.md"
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "dl-fixture.md:3" "$OUT" "$CURRENT_CASE file:line"
teardown_fixture

# --- bare runtime `bash lib/` under agents/ (runtime invocation) -> exit 1 ---
CURRENT_CASE="bare-runtime-bash-lib-agents-exit-1"
CASES=$((CASES + 1))
setup_fixture
printf '# Run\n\nbash lib/claim-req.sh "$REQ_PATH"\n' > "$TMP/agents/run.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "bare-runtime-bash-lib" "$OUT" "$CURRENT_CASE pattern name"
assert_contains "agents/run.md" "$OUT" "$CURRENT_CASE file"
teardown_fixture

# --- bare runtime `bash lib/` under references/ -> exit 1 ---
CURRENT_CASE="bare-runtime-bash-lib-references-exit-1"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/references"
printf '# Loop\n\nREQ_PATH=$(bash lib/pick-req.sh "$SCOPE" "$AGENT_ID")\n' > "$TMP/references/run-loop.md"
run_lint
assert_eq "1" "$RC" "$CURRENT_CASE rc"
assert_contains "bare-runtime-bash-lib" "$OUT" "$CURRENT_CASE pattern name"
assert_contains "references/run-loop.md" "$OUT" "$CURRENT_CASE file"
teardown_fixture

# --- skill-dev allowlist: bash lib/tests/... under agents/ -> exit 0 ---
CURRENT_CASE="bare-runtime-bash-lib-allowlist-tests-exit-0"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/agents/tracker"
printf '# Markdown\n\nRun `bash lib/tests/run-all.sh` as the regression gate.\n' > "$TMP/agents/tracker/markdown.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- skill-dev allowlist: bash lib/conformance-scan.sh under agents/ -> exit 0 ---
CURRENT_CASE="bare-runtime-bash-lib-allowlist-conformance-exit-0"
CASES=$((CASES + 1))
setup_fixture
mkdir -p "$TMP/agents/tracker"
printf '# Port\n\n`bash lib/conformance-scan.sh` remains the regression gate.\n' > "$TMP/agents/tracker/port.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- correct skill-root form is allowed under agents/ -> exit 0 ---
CURRENT_CASE="skill-root-bash-lib-agents-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# Run\n\nbash {skill-root}/lib/claim-req.sh "$REQ_PATH"\n' > "$TMP/agents/run.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

# --- bare bash lib/ outside agents/ and references/ is out of scope -> exit 0 ---
CURRENT_CASE="bare-bash-lib-docs-out-of-scope-exit-0"
CASES=$((CASES + 1))
setup_fixture
printf '# How\n\nHistorically agents ran bash lib/claim-req.sh from CWD.\n' > "$TMP/docs/HOW-IT-WORKS.md"
run_lint
assert_eq "0" "$RC" "$CURRENT_CASE rc"
teardown_fixture

echo ""
echo "doc-lint tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
