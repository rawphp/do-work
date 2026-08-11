#!/usr/bin/env bash
# check-footprint.sh — overlap detection across `.do-work/working/` slots.
#
# Usage: check-footprint.sh <req-path>
#   <req-path>  Path (relative or absolute) to a REQ file. The REQ may live at
#               the backlog root, under `working/`, or anywhere — the script
#               only parses its `**Files:**` line.
#
# Behavior:
#   1. Parses this REQ's `**Files:**` field into a path/glob list.
#   2. Expands globs against the working tree (CWD), including `**` (globstar,
#      walked manually for bash 3.2). A plain entry that matches nothing is
#      retained as a literal so two REQs claiming the same not-yet-existing
#      path still conflict.
#   3. For each `.do-work/working/REQ-*.md` slot (excluding the input REQ's
#        own path if it happens to be one of them):
#        - Parses its `**Files:**`, expands globs.
#        - If the intersection with this REQ's set is non-empty, prints
#          `<slot-req-id>: <comma-separated-intersecting-paths>` on stdout,
#          one slot per line.
#   4. Exits 0 in all non-error cases. Empty stdout = no overlap.
#
# Notes:
#   - Field parsing, glob expansion, and the files-for-REQ walker come from the
#     shared `lib/eligibility-common.sh` so check-footprint, check-deps, and
#     pick-req cannot drift apart (F1 / UR-003).
#   - `.do-work/` is located via CWD (callers run from the project root, same
#     convention as pick-req.sh / claim-req.sh).
#   - An empty or missing `**Files:**` produces empty output regardless of
#     other slots.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4. Standard POSIX tools only.

set -u

REQ_PATH="${1:-}"

if [ -z "$REQ_PATH" ]; then
  echo "Usage: check-footprint.sh <req-path>" >&2
  exit 1
fi

if [ ! -e "$REQ_PATH" ]; then
  echo "check-footprint.sh: REQ not found: $REQ_PATH" >&2
  exit 1
fi

DOWORK=".do-work"
if [ ! -d "$DOWORK" ]; then
  # No backlog directory — nothing to compare against. Silent exit.
  exit 0
fi

# --- shared eligibility helpers (canonical; sourced, not duplicated) ---------
_SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=eligibility-common.sh
source "$_SELF_DIR/eligibility-common.sh"

# --- helpers -----------------------------------------------------------------

# Normalise a path for self-comparison. Resolves to canonical form via cd+pwd
# where possible; falls back to the input if the file no longer exists.
# (check-footprint-specific — pick-req compares via an index, not path canon.)
normalise_path() {
  local p="$1"
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *)  printf '%s\n' "$(pwd)/$p" ;;
  esac
}

# --- main -------------------------------------------------------------------

# Parse the input REQ's files. Empty or missing → exit 0 with no output.
TARGET_FILES_FILE="$(mktemp -t check-footprint-target.XXXXXX)"
trap 'rm -f "$TARGET_FILES_FILE" "${SLOT_FILES_FILE:-}"' EXIT

elig_files_for_req "$REQ_PATH" | LC_ALL=C sort -u > "$TARGET_FILES_FILE"

if [ ! -s "$TARGET_FILES_FILE" ]; then
  # No declared files → no overlap possible.
  exit 0
fi

# Compute the absolute path of the input REQ for self-exclusion.
INPUT_ABS="$(normalise_path "$REQ_PATH")"

SLOT_FILES_FILE="$(mktemp -t check-footprint-slot.XXXXXX)"

# Iterate working/ slots in lexical order (deterministic output).
shopt -s nullglob 2>/dev/null || true
# shellcheck disable=SC2206
SLOTS=( "$DOWORK"/working/REQ-*.md )

# Stable sort the slots for deterministic stdout ordering.
if [ "${#SLOTS[@]}" -gt 0 ]; then
  SORTED_SLOTS="$(printf '%s\n' "${SLOTS[@]}" | LC_ALL=C sort)"
else
  SORTED_SLOTS=""
fi

while IFS= read -r slot; do
  [ -n "$slot" ] || continue
  [ -e "$slot" ] || continue

  # Self-exclusion: skip if this slot's absolute path equals the input REQ's.
  slot_abs="$(normalise_path "$slot")"
  if [ "$slot_abs" = "$INPUT_ABS" ]; then
    continue
  fi

  # Build slot's expanded file set.
  elig_files_for_req "$slot" | LC_ALL=C sort -u > "$SLOT_FILES_FILE"
  if [ ! -s "$SLOT_FILES_FILE" ]; then
    continue
  fi

  # Intersect with target set.
  intersection="$(LC_ALL=C comm -12 "$TARGET_FILES_FILE" "$SLOT_FILES_FILE")"
  if [ -z "$intersection" ]; then
    continue
  fi

  # Join intersection paths with ", " for compact output.
  joined="$(printf '%s\n' "$intersection" | awk 'BEGIN{first=1} NF{ if(first){printf "%s", $0; first=0} else {printf ", %s", $0} } END{ if(!first) printf "\n" }')"

  slot_id="$(elig_req_id_from_path "$slot")"
  printf '%s: %s\n' "$slot_id" "$joined"
done <<EOF
$SORTED_SLOTS
EOF

exit 0
