#!/usr/bin/env bash
# Tests for lib/claim-req.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CLAIMER="$LIB_DIR/claim-req.sh"

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

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [ ! -e "$path" ]; then
    fail "$label: expected file to exist: $path"
  fi
}

assert_file_absent() {
  local path="$1"
  local label="$2"
  if [ -e "$path" ]; then
    fail "$label: expected file NOT to exist: $path"
  fi
}

# Write a backlog REQ file.
write_req() {
  local path="$1"
  local id="$2"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** backlog
**Created:** 2026-05-21
**Layer:** agents
**Files:** src/a.ts
**Depends on:**

## Task

Do the thing.
EOF
}

# Set up a TRACKED fixture: a real git repo with .do-work/ committed (no gitignore).
setup_tracked_fixture() {
  TMP="$(mktemp -d -t claim-req-tracked.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive"
  (
    cd "$TMP"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    # Ensure .do-work is NOT ignored.
    : > .gitkeep
    git add .gitkeep
    git commit -q -m "init"
  )
}

# Set up an UNTRACKED fixture: a git repo where .do-work/ is gitignored.
setup_untracked_fixture() {
  TMP="$(mktemp -d -t claim-req-untracked.XXXXXX)"
  mkdir -p "$TMP/.do-work/working" "$TMP/.do-work/archive"
  (
    cd "$TMP"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo ".do-work/" > .gitignore
    git add .gitignore
    git commit -q -m "init with gitignore"
  )
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Run claim-req.sh inside $TMP. Stores PICK_RC, PICK_STDOUT, PICK_STDERR.
run_claim() {
  local req_path="$1"
  local agent="$2"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$CLAIMER" "$req_path" "$agent" > "$out_file" 2> "$err_file" )
  PICK_RC=$?
  PICK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  PICK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: happy path (tracked .do-work/)
# ----------------------------------------------------------------------
CURRENT_CASE="happy-path-tracked"
CASES=$((CASES + 1))
setup_tracked_fixture
write_req "$TMP/.do-work/REQ-001-foo.md" "REQ-001"
(
  cd "$TMP"
  git add .do-work/REQ-001-foo.md
  git commit -q -m "add REQ-001"
)
run_claim ".do-work/REQ-001-foo.md" "test-agent.1234"

assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_file_exists "$TMP/.do-work/working/REQ-001-foo.md" "$CURRENT_CASE moved into working/"
assert_file_absent "$TMP/.do-work/REQ-001-foo.md" "$CURRENT_CASE removed from backlog root"

# Stamp present with all three lines + Status updated
moved_content="$(cat "$TMP/.do-work/working/REQ-001-foo.md")"
assert_contains "<!-- claimed-start -->" "$moved_content" "$CURRENT_CASE stamp start"
assert_contains "**Claimed by:** test-agent.1234" "$moved_content" "$CURRENT_CASE Claimed by"
assert_contains "**Claimed at:**" "$moved_content" "$CURRENT_CASE Claimed at"
assert_contains "**Heartbeat:**" "$moved_content" "$CURRENT_CASE Heartbeat"
assert_contains "<!-- claimed-end -->" "$moved_content" "$CURRENT_CASE stamp end"
assert_contains "**Status:** in-progress" "$moved_content" "$CURRENT_CASE Status updated"

# Verify Claimed at == Heartbeat at claim time
claimed_at="$(grep -m1 '^\*\*Claimed at:\*\*' "$TMP/.do-work/working/REQ-001-foo.md" | sed 's/^\*\*Claimed at:\*\* //')"
heartbeat="$(grep -m1 '^\*\*Heartbeat:\*\*' "$TMP/.do-work/working/REQ-001-foo.md" | sed 's/^\*\*Heartbeat:\*\* //')"
assert_eq "$claimed_at" "$heartbeat" "$CURRENT_CASE Claimed at == Heartbeat"

# stdout should contain a short hash (hex chars, length >= 7)
case "$PICK_STDOUT" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) : ;;
  *) fail "$CURRENT_CASE: expected short commit hash on stdout, got '$PICK_STDOUT'" ;;
esac

# Verify the commit subject
subject="$(cd "$TMP" && git log -1 --format=%s)"
assert_eq "chore(REQ-001): claim by test-agent.1234" "$subject" "$CURRENT_CASE commit subject"

# Verify only the REQ file is in the commit (not a sweep)
files_in_commit="$(cd "$TMP" && git show --name-only --format= HEAD | sort)"
assert_eq ".do-work/REQ-001-foo.md
.do-work/working/REQ-001-foo.md" "$files_in_commit" "$CURRENT_CASE only REQ file staged"

teardown_fixture

# ----------------------------------------------------------------------
# Case 2: race lost (REQ already moved by sibling)
# ----------------------------------------------------------------------
CURRENT_CASE="race-lost"
CASES=$((CASES + 1))
setup_tracked_fixture
# REQ does NOT exist at backlog root — already taken.
run_claim ".do-work/REQ-002-gone.md" "test-agent.1234"

assert_eq "2" "$PICK_RC" "$CURRENT_CASE rc=2"
assert_contains "Claim lost" "$PICK_STDERR" "$CURRENT_CASE stderr Claim lost"
assert_contains "REQ-002" "$PICK_STDERR" "$CURRENT_CASE stderr names REQ id"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: malformed REQ path (not under .do-work/REQ-*.md backlog root)
# ----------------------------------------------------------------------
CURRENT_CASE="malformed-path-not-backlog"
CASES=$((CASES + 1))
setup_tracked_fixture
mkdir -p "$TMP/.do-work/working"
write_req "$TMP/.do-work/working/REQ-003-foo.md" "REQ-003"
# Passing a working/ path (not a backlog path) should fail validation.
run_claim ".do-work/working/REQ-003-foo.md" "test-agent.1234"

case "$PICK_RC" in
  0) fail "$CURRENT_CASE: expected non-zero exit, got 0" ;;
  2) fail "$CURRENT_CASE: expected non-zero non-race exit, got 2 (race code)" ;;
  *) : ;;
esac
assert_contains "REQ" "$PICK_STDERR" "$CURRENT_CASE stderr mentions REQ"
# File should still be where it was (untouched).
assert_file_exists "$TMP/.do-work/working/REQ-003-foo.md" "$CURRENT_CASE original file untouched"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: malformed REQ path (no REQ- prefix in filename)
# ----------------------------------------------------------------------
CURRENT_CASE="malformed-path-no-req-prefix"
CASES=$((CASES + 1))
setup_tracked_fixture
mkdir -p "$TMP/.do-work"
echo "# not a REQ" > "$TMP/.do-work/notes.md"
run_claim ".do-work/notes.md" "test-agent.1234"

case "$PICK_RC" in
  0) fail "$CURRENT_CASE: expected non-zero exit, got 0" ;;
  *) : ;;
esac
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: dirty working tree (other unrelated changes present)
#         claim should still succeed and stage ONLY the REQ file.
# ----------------------------------------------------------------------
CURRENT_CASE="dirty-working-tree"
CASES=$((CASES + 1))
setup_tracked_fixture
write_req "$TMP/.do-work/REQ-005-foo.md" "REQ-005"
(
  cd "$TMP"
  git add .do-work/REQ-005-foo.md
  git commit -q -m "add REQ-005"
)
# Introduce an unrelated dirty change.
echo "dirty" > "$TMP/some-unrelated-file.txt"

run_claim ".do-work/REQ-005-foo.md" "test-agent.1234"

assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_file_exists "$TMP/.do-work/working/REQ-005-foo.md" "$CURRENT_CASE moved"

# Unrelated file must NOT be in the commit.
files_in_commit="$(cd "$TMP" && git show --name-only --format= HEAD | sort)"
case "$files_in_commit" in
  *some-unrelated-file*) fail "$CURRENT_CASE: unrelated file leaked into claim commit" ;;
  *) : ;;
esac
# Unrelated file should still be uncommitted in working tree.
assert_file_exists "$TMP/some-unrelated-file.txt" "$CURRENT_CASE unrelated file preserved"
unstaged_status="$(cd "$TMP" && git status --porcelain some-unrelated-file.txt)"
assert_contains "some-unrelated-file" "$unstaged_status" "$CURRENT_CASE unrelated file still untracked"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: untracked .do-work/ (skill source repo case)
#         No commit possible. Functional move + stamp; stdout = "untracked".
# ----------------------------------------------------------------------
CURRENT_CASE="untracked-do-work"
CASES=$((CASES + 1))
setup_untracked_fixture
write_req "$TMP/.do-work/REQ-006-foo.md" "REQ-006"
run_claim ".do-work/REQ-006-foo.md" "test-agent.1234"

assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
assert_file_exists "$TMP/.do-work/working/REQ-006-foo.md" "$CURRENT_CASE moved into working/"
assert_file_absent "$TMP/.do-work/REQ-006-foo.md" "$CURRENT_CASE removed from backlog root"

moved_content="$(cat "$TMP/.do-work/working/REQ-006-foo.md")"
assert_contains "**Claimed by:** test-agent.1234" "$moved_content" "$CURRENT_CASE Claimed by"
assert_contains "**Heartbeat:**" "$moved_content" "$CURRENT_CASE Heartbeat"
assert_contains "**Status:** in-progress" "$moved_content" "$CURRENT_CASE Status updated"

assert_eq "untracked" "$PICK_STDOUT" "$CURRENT_CASE stdout is 'untracked'"
assert_contains "Claim recorded" "$PICK_STDERR" "$CURRENT_CASE stderr explains untracked mode"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: session correlation — marker match stamps **Session:** into the block
# ----------------------------------------------------------------------
CURRENT_CASE="session-stamped-on-marker-match"
CASES=$((CASES + 1))
setup_tracked_fixture
write_req "$TMP/.do-work/REQ-007-foo.md" "REQ-007"
(
  cd "$TMP"
  git add .do-work/REQ-007-foo.md
  git commit -q -m "add REQ-007"
)
# Seed a session.start carrying the terminal marker "mk7".
mkdir -p "$TMP/.do-work/state"
EMIT_EVENT_TS="2026-07-11T00:00:07Z" \
  bash "$LIB_DIR/emit-event.sh" "$TMP" session.start "sess-claim-7" '{"marker":"mk7"}' >/dev/null
# Claim with the matching marker exported (as the run orchestrator would).
claim_err="$TMP/.stderr.$$"
( cd "$TMP" && DO_WORK_UI_MARKER="mk7" "$CLAIMER" ".do-work/REQ-007-foo.md" "test-agent.7" >/dev/null 2>"$claim_err" )
PICK_RC=$?
rm -f "$claim_err"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc"
moved_content="$(cat "$TMP/.do-work/working/REQ-007-foo.md")"
assert_contains "**Session:** sess-claim-7" "$moved_content" "$CURRENT_CASE Session line stamped"
# The Session line must sit INSIDE the claim fences.
between="$(awk '/<!-- claimed-start -->/{f=1} f{print} /<!-- claimed-end -->/{f=0}' "$TMP/.do-work/working/REQ-007-foo.md")"
assert_contains "**Session:** sess-claim-7" "$between" "$CURRENT_CASE Session inside claim fences"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: no events.jsonl (pre-REQ-037 project) — Session omitted, claim succeeds
# ----------------------------------------------------------------------
CURRENT_CASE="session-omitted-without-events"
CASES=$((CASES + 1))
setup_tracked_fixture
write_req "$TMP/.do-work/REQ-008-foo.md" "REQ-008"
(
  cd "$TMP"
  git add .do-work/REQ-008-foo.md
  git commit -q -m "add REQ-008"
)
# No events.jsonl exists in this fixture.
run_claim ".do-work/REQ-008-foo.md" "test-agent.8"
assert_eq "0" "$PICK_RC" "$CURRENT_CASE rc (claim still succeeds)"
assert_file_exists "$TMP/.do-work/working/REQ-008-foo.md" "$CURRENT_CASE moved into working/"
moved_content="$(cat "$TMP/.do-work/working/REQ-008-foo.md")"
case "$moved_content" in
  *"**Session:**"*) fail "$CURRENT_CASE: Session line must be omitted when no session resolvable" ;;
  *) : ;;
esac
# Sanity: the rest of the stamp is intact.
assert_contains "**Claimed by:** test-agent.8" "$moved_content" "$CURRENT_CASE Claimed by intact"
assert_contains "**Heartbeat:**" "$moved_content" "$CURRENT_CASE Heartbeat intact"
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
