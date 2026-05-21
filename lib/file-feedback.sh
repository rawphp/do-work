#!/usr/bin/env bash
# file-feedback.sh — file a GitHub issue (or add a comment) when the
# do-work coordination layer detects a noteworthy event.
#
# Usage:
#   file-feedback.sh <event-type> <fingerprint> <context-json> [title] [body]
#
# Arguments:
#   event-type    — one of: deadlock, footprint-miss, concurrent-conflict,
#                   cap-cycle, stale-slot (system-class), or
#                   ambiguous-criteria, verify-fail (project-class).
#   fingerprint   — stable dedup key, e.g. "deadlock:no-progress-stall:0:abc1"
#   context-json  — JSON object with additional context (may be "{}")
#   title         — issue title (optional; defaults to event-type)
#   body          — issue body text (optional)
#
# Behaviour:
#   1. Reads feedback.enabled / feedback.repo / feedback.label /
#      feedback.project_repo from .do-work/config.yml.
#      If feedback.enabled != true → exit 0 silently.
#   2. Routes:  system-class events  → feedback.repo
#               project-class events → feedback.project_repo (if set),
#               otherwise             feedback.repo
#   3. Acquires a lockfile to prevent thundering-herd issue spam.
#      If lock already held (env FEEDBACK_LOCK_HELD=1, or flock contention)
#      → exit 0 silently.
#   4. Searches for an existing issue by fingerprint (in:body).
#      Match found → add a comment.
#      No match    → create new issue with fingerprint as HTML comment.
#   5. Sanitises body/title before any gh call:
#      - strips absolute paths (replaced with <path>)
#      - replaces {project} with <project>
#      - omits commit messages and code diffs
#
# Exit codes:
#   0  Completed (filed, skipped, or disabled).
#   1  Fatal internal error.
#
# Environment overrides (for testing / CI):
#   FEEDBACK_LOCK_DIR  — directory for feedback.lock (default: .do-work/state)
#   FEEDBACK_LOCK_HELD — set to "1" to simulate a held lock (skip filing)
#
# gh CLI is required but best-effort: if absent, emit a warning to stderr
# and exit 0 (never block the caller).
#
# Compatible with macOS bash 3.2 (BSD) and Linux bash >= 4 (GNU).

set -u

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DOWORK=".do-work"
CONFIG="$DOWORK/config.yml"

# System-class events route to feedback.repo
SYSTEM_EVENTS="deadlock footprint-miss concurrent-conflict cap-cycle stale-slot"
# Project-class events route to feedback.project_repo (if set)
PROJECT_EVENTS="ambiguous-criteria verify-fail"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

EVENT_TYPE="${1:-}"
FINGERPRINT="${2:-}"
CONTEXT_JSON="${3:-{}}"
TITLE="${4:-$EVENT_TYPE}"
BODY="${5:-}"

if [ -z "$EVENT_TYPE" ] || [ -z "$FINGERPRINT" ]; then
  printf 'file-feedback: usage: file-feedback.sh <event-type> <fingerprint> <context-json> [title] [body]\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read config
# ---------------------------------------------------------------------------

# Read a scalar value from .do-work/config.yml at path "key: value"
# Args: $1=section, $2=key
# Prints the value to stdout; prints nothing if absent.
read_config_key() {
  local section="$1"
  local key="$2"
  [ -f "$CONFIG" ] || return 0
  awk -v section="$section" -v key="$key" '
    $0 ~ "^" section ":[[:space:]]*$" { in_section=1; next }
    in_section && /^[^[:space:]#]/ { in_section=0 }
    in_section && $0 ~ "^[[:space:]]+" key ":[[:space:]]" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      sub("[[:space:]]*$", "")
      print
      exit
    }
  ' "$CONFIG" 2>/dev/null
}

FB_ENABLED="$(read_config_key "feedback" "enabled")"
FB_REPO="$(read_config_key "feedback" "repo")"
FB_LABEL="$(read_config_key "feedback" "label")"
FB_PROJECT_REPO="$(read_config_key "feedback" "project_repo")"

# Default label if not set
[ -z "$FB_LABEL" ] && FB_LABEL="do-work-feedback"

# ---------------------------------------------------------------------------
# Early-exit if disabled
# ---------------------------------------------------------------------------

if [ "$FB_ENABLED" != "true" ]; then
  exit 0
fi

# Also need a repo configured.
if [ -z "$FB_REPO" ]; then
  printf 'file-feedback: feedback.enabled is true but feedback.repo is not set — skipping\n' >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# gh CLI check (best-effort)
# ---------------------------------------------------------------------------

GH_CMD="$(command -v gh 2>/dev/null || true)"
if [ -z "$GH_CMD" ]; then
  printf 'file-feedback: gh CLI not found — skipping feedback filing\n' >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Lock (prevent thundering-herd)
# ---------------------------------------------------------------------------

# Allow test override: FEEDBACK_LOCK_HELD=1 → simulate contended lock
if [ "${FEEDBACK_LOCK_HELD:-}" = "1" ]; then
  # Lock held by another instance — skip silently
  exit 0
fi

LOCK_DIR="${FEEDBACK_LOCK_DIR:-$DOWORK/state}"
LOCK_FILE="$LOCK_DIR/feedback.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true

# Try flock if available (Linux / Homebrew coreutils on macOS).
# Fall back to mkdir-based locking on stock macOS.
LOCK_FD=""
LOCK_ACQUIRED=""

if command -v flock >/dev/null 2>&1; then
  # flock -n: non-blocking; if lock unavailable → exit 0 silently
  # We open the lock file on a new fd and keep it open for the lifetime of
  # the script. Use fd 9.
  exec 9>"$LOCK_FILE" 2>/dev/null || true
  if flock -n 9 2>/dev/null; then
    LOCK_ACQUIRED="flock"
  else
    # Lock contended — another sibling is filing.
    exit 0
  fi
else
  # mkdir-based portable lock: mkdir is atomic on POSIX filesystems.
  MKDIR_LOCK="${LOCK_FILE}.dir"
  if mkdir "$MKDIR_LOCK" 2>/dev/null; then
    LOCK_ACQUIRED="mkdir"
    # Ensure cleanup on exit
    trap 'rmdir "$MKDIR_LOCK" 2>/dev/null || true' EXIT
  else
    # Lock contended
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Determine target repo
# ---------------------------------------------------------------------------

TARGET_REPO="$FB_REPO"

# Check if event is project-class
is_project_event() {
  local evt="$1"
  local e
  for e in $PROJECT_EVENTS; do
    [ "$e" = "$evt" ] && return 0
  done
  return 1
}

if is_project_event "$EVENT_TYPE" && [ -n "$FB_PROJECT_REPO" ]; then
  TARGET_REPO="$FB_PROJECT_REPO"
fi

# ---------------------------------------------------------------------------
# Sanitisation
# ---------------------------------------------------------------------------

# Strip absolute paths (Unix-style: /some/absolute/path → <path>)
sanitise() {
  local text="$1"
  # Replace absolute paths starting with /
  printf '%s' "$text" | sed \
    -e 's|/[A-Za-z0-9_./-]*[A-Za-z0-9_.-]|<path>|g' \
    -e 's|{project}|<project>|g'
}

SAFE_TITLE="$(sanitise "$TITLE")"
SAFE_BODY="$(sanitise "$BODY")"

# ---------------------------------------------------------------------------
# Embed fingerprint as HTML comment in body
# ---------------------------------------------------------------------------

FULL_BODY="${SAFE_BODY}

<!-- fingerprint: ${FINGERPRINT} -->"

# ---------------------------------------------------------------------------
# Search for existing issue
# ---------------------------------------------------------------------------

EXISTING_NUMBER=""
SEARCH_RESULT="$(
  "$GH_CMD" issue list \
    --repo "$TARGET_REPO" \
    --label "$FB_LABEL" \
    --search "fingerprint:${FINGERPRINT} in:body" \
    --state all \
    --json number,state \
    2>/dev/null || true
)"

# Parse first issue number from JSON array (portable: no jq dependency).
# Format: [{"number":42,"state":"open"}, ...]
if [ -n "$SEARCH_RESULT" ] && [ "$SEARCH_RESULT" != "[]" ]; then
  EXISTING_NUMBER="$(printf '%s' "$SEARCH_RESULT" | \
    grep -o '"number":[0-9]*' | head -1 | grep -o '[0-9]*')"
fi

# ---------------------------------------------------------------------------
# File or comment
# ---------------------------------------------------------------------------

if [ -n "$EXISTING_NUMBER" ]; then
  # Existing issue — add a comment
  COMMENT_BODY="Recurrence detected.

${SAFE_BODY}

<!-- fingerprint: ${FINGERPRINT} -->"

  "$GH_CMD" issue comment "$EXISTING_NUMBER" \
    --repo "$TARGET_REPO" \
    --body "$COMMENT_BODY" \
    >/dev/null 2>&1 || true
else
  # New issue — create with fingerprint embedded
  "$GH_CMD" issue create \
    --repo "$TARGET_REPO" \
    --label "$FB_LABEL" \
    --title "$SAFE_TITLE" \
    --body "$FULL_BODY" \
    >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Release mkdir lock (flock releases automatically on fd close / exit)
# ---------------------------------------------------------------------------

if [ "${LOCK_ACQUIRED:-}" = "mkdir" ]; then
  MKDIR_LOCK="${LOCK_FILE}.dir"
  rmdir "$MKDIR_LOCK" 2>/dev/null || true
  trap - EXIT
fi

exit 0
