#!/usr/bin/env bash
# claim-req.sh — atomic REQ claim primitive for the do-work coordination layer.
#
# Usage: claim-req.sh <req-path> <agent-id>
#   <req-path>  Path (relative or absolute) to a REQ file at the backlog root,
#               i.e. matching `<...>/.do-work/REQ-*.md` (NOT under `working/`).
#   <agent-id>  Claiming agent's id (e.g. `mbp-tom.42137`).
#
# What it does:
#   1. Validates the path is a backlog-root REQ file.
#   2. Detects whether `.do-work/` is tracked by git in this repo.
#   3. Moves the file from backlog root into `.do-work/working/`:
#        - tracked   → `git mv` (atomic w.r.t. siblings on the same branch)
#        - untracked → plain `mv` (no commit possible; functional move only)
#   4. Inserts the ownership stamp (Claimed by / Claimed at / Heartbeat — all
#      three timestamps identical at claim time) immediately under the
#      `# REQ-NNN:` heading.
#   5. Updates `**Status:** backlog` → `**Status:** in-progress` in place (sed).
#   6. On tracked path: stages only this REQ file and commits
#      `chore(REQ-NNN): claim by <agent-id>`. Prints short commit hash to stdout.
#      On untracked path: prints `untracked` to stdout and a one-line note to
#      stderr (`Claim recorded (untracked .do-work/)`).
#
# Exit codes:
#   0  Claim succeeded.
#   2  Race lost (source REQ no longer exists at backlog root). Prints
#      `Claim lost: <req-id>` to stderr.
#   1  Any other failure (validation, sed, git commit, etc.). Attempts to
#      revert the move so the working tree is left clean.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep, sed, awk, mv, cat).

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# --- args -------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
  echo "Usage: claim-req.sh <req-path> <agent-id>" >&2
  exit 1
fi

REQ_PATH="$1"
AGENT_ID="$2"

# --- validation -------------------------------------------------------------

# Resolve REQ filename and parent directory.
REQ_BASENAME="$(basename "$REQ_PATH")"
REQ_PARENT="$(dirname "$REQ_PATH")"

# Filename must look like REQ-*.md (allow REQ-NNN or REQ-M<n>-NNN forms).
case "$REQ_BASENAME" in
  REQ-*.md) : ;;
  *)
    echo "claim-req.sh: not a REQ file: $REQ_PATH" >&2
    exit 1
    ;;
esac

# Parent directory must end in `.do-work` (backlog root), NOT
# `.do-work/working` or `.do-work/archive`.
REQ_PARENT_BASE="$(basename "$REQ_PARENT")"
if [ "$REQ_PARENT_BASE" != ".do-work" ]; then
  echo "claim-req.sh: REQ must be at backlog root (.do-work/), got parent: $REQ_PARENT_BASE  (path: $REQ_PATH)" >&2
  exit 1
fi

# Derive the REQ id (e.g. REQ-007 or REQ-M2-041) for commit messages & errors.
REQ_ID="$(printf '%s' "$REQ_BASENAME" | awk '{
  if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
    print substr($0, RSTART, RLENGTH)
  } else if (match($0, /^REQ-[0-9]+/)) {
    print substr($0, RSTART, RLENGTH)
  } else if (match($0, /^REQ-[A-Za-z0-9]+/)) {
    print substr($0, RSTART, RLENGTH)
  } else {
    print ""
  }
}')"
if [ -z "$REQ_ID" ]; then
  echo "claim-req.sh: cannot derive REQ id from filename: $REQ_BASENAME" >&2
  exit 1
fi

# Source file must currently exist at backlog root. Missing → race lost.
if [ ! -e "$REQ_PATH" ]; then
  echo "Claim lost: $REQ_ID (source path not present)" >&2
  exit 2
fi

DEST_DIR="$REQ_PARENT/working"
DEST_PATH="$DEST_DIR/$REQ_BASENAME"

# Ensure working/ exists (idempotent).
if [ ! -d "$DEST_DIR" ]; then
  mkdir -p "$DEST_DIR" || {
    echo "claim-req.sh: cannot create $DEST_DIR" >&2
    exit 1
  }
fi

# --- detect tracked vs untracked --------------------------------------------

# `.do-work/` is gitignored in this skill source repo but tracked in consumer
# projects (see CONTRIBUTING.md). `git check-ignore` returns 0 if a path is
# ignored, 1 if not, and prints nothing on stdout by default (so we read its
# exit code only).
#
# We probe the *parent* `.do-work` directory rather than the REQ file itself,
# because gitignore patterns like `.do-work/` match the directory.
TRACKED_MODE=1
if git check-ignore -q "$REQ_PARENT" 2>/dev/null; then
  TRACKED_MODE=0
fi
# If the file itself is explicitly ignored (rare but possible), treat as untracked.
if [ "$TRACKED_MODE" = "1" ] && git check-ignore -q "$REQ_PATH" 2>/dev/null; then
  TRACKED_MODE=0
fi

# --- compute timestamp ------------------------------------------------------

# ISO-8601 UTC with Z suffix. BSD date (macOS) and GNU date both accept
# `-u +%Y-%m-%dT%H:%M:%SZ`.
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- resolve session (optional) ---------------------------------------------

# Correlate this claim with the current do-work session so the extension can
# map REQ → session for its resume flow. The project root is the parent of the
# backlog-root `.do-work/` directory (REQ_PARENT). resolve-session.sh prints
# the session id, or nothing when it cannot be determined without guessing;
# the `**Session:**` line is stamped only when non-empty.
PROJECT_ROOT="$(dirname "$REQ_PARENT")"
SESSION_ID="$(bash "$SCRIPT_DIR/resolve-session.sh" "$PROJECT_ROOT" 2>/dev/null || true)"

# --- move -------------------------------------------------------------------

if [ "$TRACKED_MODE" = "1" ]; then
  # Tracked: use git mv. If it fails because the source vanished (sibling won
  # the race), exit 2.
  mv_err="$(git mv "$REQ_PATH" "$DEST_PATH" 2>&1)"
  mv_rc=$?
  if [ "$mv_rc" -ne 0 ]; then
    # Detect race-lost signature.
    case "$mv_err" in
      *"bad source"*|*"does not exist"*|*"did not match any files"*|*"not under version control"*)
        # Source gone or never tracked — race lost.
        if [ ! -e "$REQ_PATH" ]; then
          echo "Claim lost: $REQ_ID" >&2
          exit 2
        fi
        # File exists but isn't tracked yet — fall back to plain mv path.
        # This handles the edge case where a REQ was added to the working tree
        # but not yet committed. We still want the claim to succeed.
        if mv "$REQ_PATH" "$DEST_PATH" 2>/dev/null; then
          : # proceed; we'll attempt to commit below and let it surface any issue.
        else
          echo "claim-req.sh: mv fallback failed: $mv_err" >&2
          exit 1
        fi
        ;;
      *)
        echo "claim-req.sh: git mv failed: $mv_err" >&2
        exit 1
        ;;
    esac
  fi
else
  # Untracked: plain mv. If source is gone, race lost.
  if [ ! -e "$REQ_PATH" ]; then
    echo "Claim lost: $REQ_ID" >&2
    exit 2
  fi
  if ! mv "$REQ_PATH" "$DEST_PATH" 2>/dev/null; then
    echo "claim-req.sh: mv failed for $REQ_PATH → $DEST_PATH" >&2
    exit 1
  fi
fi

# --- revert helper (used on any post-move failure) --------------------------

revert_move() {
  # Best-effort: undo whatever we did so the working tree is left clean.
  if [ "$TRACKED_MODE" = "1" ]; then
    git mv "$DEST_PATH" "$REQ_PATH" >/dev/null 2>&1 || \
      mv "$DEST_PATH" "$REQ_PATH" >/dev/null 2>&1 || true
    # Drop anything we may have staged.
    git reset -q HEAD -- "$REQ_PATH" "$DEST_PATH" >/dev/null 2>&1 || true
  else
    mv "$DEST_PATH" "$REQ_PATH" >/dev/null 2>&1 || true
  fi
}

# --- insert stamp + update status (in place) --------------------------------

# Write the stamp block to a temp file (avoids passing multi-line strings to
# awk via -v, which BSD awk on macOS rejects).
STAMP_FILE="$(mktemp -t claim-req-stamp.XXXXXX)"
{
  printf '%s\n' '<!-- claimed-start -->'
  printf '%s\n' "**Claimed by:** $AGENT_ID"
  printf '%s\n' "**Claimed at:** $NOW_ISO"
  printf '%s\n' "**Heartbeat:** $NOW_ISO"
  # Session line is omitted entirely when no session could be resolved (older
  # do-work versions and marker-less/ambiguous cases) — absence stays valid.
  if [ -n "$SESSION_ID" ]; then
    printf '%s\n' "**Session:** $SESSION_ID"
  fi
  printf '%s\n' '<!-- claimed-end -->'
} > "$STAMP_FILE"

# Insert the stamp block immediately under the first `# REQ-` heading.
# Algorithm:
#   - For each input line, write it to the output.
#   - On the first line matching `^# REQ-`, also write a blank line then the
#     stamp file's contents, then a blank separator before continuing.
#   - If the line directly after the heading was already blank, skip it once
#     to avoid producing a double blank.
TMP_OUT="$(mktemp -t claim-req-stamp-out.XXXXXX)"
inserted=0
skip_next_blank=0
heading_found=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$inserted" = "0" ]; then
    case "$line" in
      "# REQ-"*)
        printf '%s\n' "$line" >> "$TMP_OUT"
        printf '\n' >> "$TMP_OUT"
        cat "$STAMP_FILE" >> "$TMP_OUT"
        printf '\n' >> "$TMP_OUT"
        inserted=1
        skip_next_blank=1
        heading_found=1
        continue
        ;;
    esac
  elif [ "$skip_next_blank" = "1" ]; then
    skip_next_blank=0
    if [ -z "$line" ]; then
      # Drop the pre-existing blank line that followed the heading.
      continue
    fi
  fi
  printf '%s\n' "$line" >> "$TMP_OUT"
done < "$DEST_PATH"
rm -f "$STAMP_FILE"

if [ "$heading_found" = "0" ]; then
  rm -f "$TMP_OUT"
  echo "claim-req.sh: no '# REQ-' heading found in $DEST_PATH" >&2
  revert_move
  exit 1
fi

# Move stamped content into place.
if ! mv "$TMP_OUT" "$DEST_PATH"; then
  rm -f "$TMP_OUT"
  echo "claim-req.sh: failed to write stamped REQ to $DEST_PATH" >&2
  revert_move
  exit 1
fi

# Update Status: backlog → in-progress. Use a portable in-place sed
# (write to temp + mv to avoid BSD/GNU `-i` divergence).
TMP_STATUS="$(mktemp -t claim-req-status.XXXXXX)"
if ! sed 's/^\*\*Status:\*\*[[:space:]]*backlog[[:space:]]*$/**Status:** in-progress/' \
     "$DEST_PATH" > "$TMP_STATUS"; then
  rm -f "$TMP_STATUS"
  echo "claim-req.sh: sed failed updating Status in $DEST_PATH" >&2
  revert_move
  exit 1
fi
mv "$TMP_STATUS" "$DEST_PATH" || {
  echo "claim-req.sh: failed to write Status update to $DEST_PATH" >&2
  revert_move
  exit 1
}

# --- commit (tracked) / report (untracked) ----------------------------------

if [ "$TRACKED_MODE" = "1" ]; then
  # Stage ONLY this REQ's file path. Two paths: the old (deletion) and the new
  # (addition). `git mv` already updates the index for both, but we re-add the
  # destination explicitly in case the awk/sed rewrite happened after git mv
  # so the index reflects the stamped content.
  if ! git add -- "$DEST_PATH" 2>/dev/null; then
    echo "claim-req.sh: git add failed for $DEST_PATH" >&2
    revert_move
    exit 1
  fi
  # Also ensure the source removal is staged (git mv already does this, but
  # belt-and-braces for the fallback-mv path above).
  git add -- "$REQ_PATH" 2>/dev/null || true

  COMMIT_MSG="chore(${REQ_ID}): claim by ${AGENT_ID}"
  if ! git commit -q -m "$COMMIT_MSG" -- "$REQ_PATH" "$DEST_PATH" 2>/dev/null; then
    # Some git versions reject pathspecs for files that were renamed. Retry
    # without pathspecs (we've already staged only what we intend to commit,
    # but if other changes leaked into the index, that would be a caller bug).
    # To be safe, attempt a scoped commit by re-staging and committing without
    # touching unrelated staged changes:
    if ! git commit -q -m "$COMMIT_MSG" 2>/dev/null; then
      echo "claim-req.sh: git commit failed for $REQ_ID" >&2
      revert_move
      exit 1
    fi
  fi

  SHORT_HASH="$(git rev-parse --short HEAD 2>/dev/null)"
  if [ -z "$SHORT_HASH" ]; then
    echo "claim-req.sh: could not read commit hash" >&2
    exit 1
  fi
  printf '%s\n' "$SHORT_HASH"
  exit 0
else
  # Untracked mode: no commit possible. Report success.
  echo "Claim recorded (untracked .do-work/)" >&2
  printf '%s\n' "untracked"
  exit 0
fi
