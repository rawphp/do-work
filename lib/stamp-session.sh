#!/usr/bin/env bash
# stamp-session.sh — insert or replace the optional **Session:** field inside a
# working/ REQ slot's claim stamp (filesystem-only, no git commit).
#
# Usage: stamp-session.sh <req-path> [session-id]
#   <req-path>    Path (relative or absolute) to a REQ file living under
#                 `.../.do-work/working/`. The file must contain a claim stamp
#                 wrapped in `<!-- claimed-start --> ... <!-- claimed-end -->`.
#   [session-id]  Optional session id to stamp. If omitted or empty, the script
#                 calls lib/resolve-session.sh with the project root derived
#                 from the REQ path. If resolve prints nothing, any existing
#                 **Session:** line is left untouched and the script exits 0
#                 (resume must not clear a known session by guessing).
#
# Behaviour:
#   - If <req-path> does not exist: print to stderr, exit 1.
#   - If <req-path> is not under a `.do-work/working/` directory: warn on
#     stderr, exit 1. Session stamp is only meaningful for in-progress slots.
#   - If the claim stamp is missing entirely: exit 1. Never creates a claim
#     stamp (resume assumes claim exists).
#   - If [session-id] is non-empty (or resolve returns non-empty):
#       * If `**Session:**` already present inside the stamp: replace its value.
#       * If absent: insert `**Session:** <id>` immediately before
#         `<!-- claimed-end -->` (after Heartbeat / other stamp fields).
#   - If resolved/arg session id is empty: leave existing Session line alone
#     (or leave absent), exit 0.
#
#   No git commands. No staging. No commit. Sibling agents read the stamp
#   directly from the filesystem — same contract as lib/heartbeat.sh.
#
# Exit codes:
#   0  Session updated (insert/replace) or intentionally left untouched.
#   1  Any failure: missing file, file outside working/, no claim stamp,
#      sed/awk write failure.
#
# Compatible with macOS bash 3.2 + BSD sed/awk.
# Standard POSIX tools only.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# --- args -------------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  echo "Usage: stamp-session.sh <req-path> [session-id]" >&2
  exit 1
fi

REQ_PATH="$1"
SESSION_ARG="${2:-}"

# --- validate file exists ---------------------------------------------------

if [ ! -e "$REQ_PATH" ]; then
  echo "stamp-session.sh: REQ file not found: $REQ_PATH" >&2
  exit 1
fi

if [ ! -f "$REQ_PATH" ]; then
  echo "stamp-session.sh: REQ path is not a regular file: $REQ_PATH" >&2
  exit 1
fi

# --- validate file is under .do-work/working/ -------------------------------

# Inspect the parent directory's basename and its parent's basename. We need
# the file to live in `<...>/.do-work/working/<file>`, so:
#   parent basename       == "working"
#   grandparent basename  == ".do-work"
REQ_PARENT="$(dirname "$REQ_PATH")"
REQ_PARENT_BASE="$(basename "$REQ_PARENT")"
REQ_GRANDPARENT="$(dirname "$REQ_PARENT")"
REQ_GRANDPARENT_BASE="$(basename "$REQ_GRANDPARENT")"

if [ "$REQ_PARENT_BASE" != "working" ] || [ "$REQ_GRANDPARENT_BASE" != ".do-work" ]; then
  echo "stamp-session.sh: refusing to stamp session — REQ is outside .do-work/working/: $REQ_PATH" >&2
  exit 1
fi

# Project root is the parent of `.do-work/` (grandparent of working/).
PROJECT_ROOT="$(dirname "$REQ_GRANDPARENT")"

# --- locate claim stamp block ----------------------------------------------

START_LINE="$(grep -n '^<!-- claimed-start -->$' "$REQ_PATH" | head -1 | cut -d: -f1)"
END_LINE="$(grep -n '^<!-- claimed-end -->$' "$REQ_PATH" | head -1 | cut -d: -f1)"

if [ -z "$START_LINE" ] || [ -z "$END_LINE" ]; then
  echo "stamp-session.sh: claim stamp not found in $REQ_PATH" >&2
  exit 1
fi

if [ "$START_LINE" -ge "$END_LINE" ]; then
  echo "stamp-session.sh: malformed claim stamp (start >= end) in $REQ_PATH" >&2
  exit 1
fi

# --- resolve session id -----------------------------------------------------

SESSION_ID="$SESSION_ARG"
if [ -z "$SESSION_ID" ]; then
  # Prefer resolve-session next to this script; fall back silently if missing.
  RESOLVE="$SCRIPT_DIR/resolve-session.sh"
  if [ -x "$RESOLVE" ] || [ -f "$RESOLVE" ]; then
    SESSION_ID="$(bash "$RESOLVE" "$PROJECT_ROOT" 2>/dev/null || true)"
  fi
  # Trim trailing newline / whitespace from resolve output.
  SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -d '\r\n')"
fi

# Empty id → leave any existing Session line untouched; do not clear by guessing.
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# --- find existing Session line inside the claim block ----------------------

SESS_LINE=""
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  hit_n="$(printf '%s' "$hit" | cut -d: -f1)"
  if [ "$hit_n" -gt "$START_LINE" ] && [ "$hit_n" -lt "$END_LINE" ]; then
    SESS_LINE="$hit_n"
    break
  fi
done <<EOF
$(grep -n '^\*\*Session:\*\*' "$REQ_PATH" || true)
EOF

# --- rewrite -----------------------------------------------------------------

TMP_OUT="$(mktemp -t stamp-session-out.XXXXXX)"

if [ -n "$SESS_LINE" ]; then
  MODE="replace"
else
  MODE="insert"
fi

awk -v mode="$MODE" \
    -v sess_line="${SESS_LINE:-0}" \
    -v end_line="$END_LINE" \
    -v sid="$SESSION_ID" '
{
  if (mode == "replace" && NR == sess_line) {
    print "**Session:** " sid
    next
  }
  if (mode == "insert" && NR == end_line) {
    print "**Session:** " sid
    print $0
    next
  }
  print
}
' "$REQ_PATH" > "$TMP_OUT" || {
  rm -f "$TMP_OUT"
  echo "stamp-session.sh: awk rewrite failed for $REQ_PATH" >&2
  exit 1
}

if [ ! -s "$TMP_OUT" ]; then
  rm -f "$TMP_OUT"
  echo "stamp-session.sh: rewrite produced empty file for $REQ_PATH" >&2
  exit 1
fi
if ! grep -q '^\*\*Session:\*\*' "$TMP_OUT"; then
  rm -f "$TMP_OUT"
  echo "stamp-session.sh: rewrite did not produce a Session line in $REQ_PATH" >&2
  exit 1
fi

if ! mv "$TMP_OUT" "$REQ_PATH"; then
  rm -f "$TMP_OUT"
  echo "stamp-session.sh: failed to write updated REQ to $REQ_PATH" >&2
  exit 1
fi

exit 0
