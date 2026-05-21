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
#   2. Expands globs against the working tree (CWD), using `globstar` for `**`
#      and `nullglob` to drop patterns that match nothing (so an unmatched
#      literal does NOT collide with another unmatched literal).
#   3. For each `.do-work/working/REQ-*.md` slot (excluding the input REQ's
#      own path if it happens to be one of them):
#        - Parses its `**Files:**`, expands globs.
#        - If the intersection with this REQ's set is non-empty, prints
#          `<slot-req-id>: <comma-separated-intersecting-paths>` on stdout,
#          one slot per line.
#   4. Exits 0 in all non-error cases. Empty stdout = no overlap.
#
# Notes:
#   - `.do-work/` is located via CWD (callers run from the project root, same
#     convention as pick-req.sh / claim-req.sh).
#   - An empty or missing `**Files:**` produces empty output regardless of
#     other slots (REQ-147 acceptance criteria).
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep, sed, awk, sort, comm).

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

# --- helpers -----------------------------------------------------------------

# Extract a single header field value from a REQ file.
# Args: $1 = field name (e.g. "Files"), $2 = file path
# Prints value to stdout (empty if absent).
extract_field() {
  local field="$1"
  local file="$2"
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

# Split a comma-separated list, trim whitespace, print one item per line.
split_csv() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  # bash 3.2 + `set -u` treats `${arr[@]}` on a zero-element array as unbound,
  # so we relax nounset for the duration of this helper. We also disable
  # pathname expansion (`set -f`) — otherwise an entry containing `*` or `**`
  # would be glob-expanded by the array-from-$s split, and with nullglob set
  # at the top of the script the resulting array would be empty.
  set +u
  set -f
  local IFS=','
  # shellcheck disable=SC2206
  local arr=($s)
  set +f
  local item
  for item in "${arr[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [ -n "$item" ]; then
      printf '%s\n' "$item"
    fi
  done
  set -u
}

# Extract the REQ id from a REQ filename. (Same algorithm as pick-req.sh.)
req_id_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  local stem="${base%.md}"
  echo "$stem" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[A-Za-z0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else {
      print ""
    }
  }'
}

# Expand a `**` (globstar) pattern by walking the tree with `find`.
# Translates the pattern into a directory prefix + a `find -path` expression
# so that `src/**/*.ts` matches all .ts under src/ recursively (including
# `src/foo.ts` and `src/a/b.ts`).
#
# Algorithm (kept simple — the design spec calls out `**/*<ext>` and
# `<dir>/**/*<ext>` as the supported globstar forms):
#   1. Split pattern at the first `**`.
#   2. Pre-prefix = everything before `**` (may end in `/`); used as the
#      `find` search root (default `.` if empty).
#   3. Post-suffix = everything after `**` (typically `/*.ts`, `/*`, etc.).
#   4. Run find rooted at the prefix, then filter results with a shell
#      pattern match against `<prefix>**<suffix>` semantics: any path whose
#      tail matches the suffix glob.
expand_globstar_pattern() {
  local pattern="$1"
  # Split on the first occurrence of "**".
  local before="${pattern%%\*\**}"
  local after="${pattern#*\*\*}"
  # Determine search root.
  local root="$before"
  # Strip trailing slash from root (find handles it either way, but keep tidy).
  root="${root%/}"
  if [ -z "$root" ]; then
    root="."
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi
  # Strip leading slash from the suffix so we can compare cleanly.
  local suffix="${after#/}"
  # If the suffix is empty, the pattern was `<prefix>/**` — match all files
  # below the prefix.
  # If suffix contains no further globs, match exact tail.
  # General approach: walk all files under root, then test each path against
  # the original pattern using bash's `case` glob, treating `**` as `*` (since
  # we already constrained to descendants of root).
  # We swap `**` for `*` in the original pattern and use case-glob matching
  # against the full path.
  local match_glob
  match_glob="$(printf '%s' "$pattern" | sed 's|\*\*|*|g')"
  # Walk all regular files under root.
  local f
  # Use find -print to enumerate; restrict to files (not dirs).
  while IFS= read -r f; do
    # Strip leading "./" if root was "."
    case "$f" in
      ./*) f="${f#./}" ;;
    esac
    # Bash `case` glob does not cross `/` with `*`, so a multi-segment
    # remainder needs explicit handling. The trick: split the path into
    # exactly the parts the pattern expects.
    #
    # Simpler approach: re-test using the original pattern's prefix + walk.
    # Match by checking: starts with `before` AND ends with the suffix glob.
    local tail_ok=0
    if [ -z "$suffix" ]; then
      tail_ok=1
    else
      # Compare the basename or trailing segment against the suffix glob.
      # Suffix may itself contain `*` or `?`. Use bash case to test the
      # ending of $f.
      case "$f" in
        $before*$suffix) tail_ok=1 ;;
      esac
    fi
    if [ "$tail_ok" = "1" ]; then
      # Also reject directories.
      if [ -f "$f" ]; then
        printf '%s\n' "$f"
      fi
    fi
  done < <(find "$root" -type f -print 2>/dev/null)
  : "$match_glob"  # silence shellcheck
}

# Expand a single Files entry into one path per line (resolved against CWD).
# Empty input produces no output. Patterns that match nothing produce no
# output (nullglob). For `**` patterns we walk the tree manually (bash 3.2
# does not support `shopt -s globstar`).
expand_files_entry() {
  local entry="$1"
  if [ -z "$entry" ]; then
    return 0
  fi
  case "$entry" in
    *\*\**)
      # Contains `**` — use the manual walker.
      expand_globstar_pattern "$entry"
      return 0
      ;;
  esac
  # Save & restore shopt state to avoid leaking into the caller.
  local _old_nullglob
  _old_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob 2>/dev/null || true
  # shellcheck disable=SC2206,SC2086
  local matches=( $entry )
  eval "$_old_nullglob" 2>/dev/null || true
  local m
  for m in "${matches[@]}"; do
    printf '%s\n' "$m"
  done
}

# Print all files (expanded) declared by a REQ at $1. One path per line.
files_for_req() {
  local path="$1"
  local raw
  raw="$(extract_field "Files" "$path")"
  if [ -z "$raw" ]; then
    return 0
  fi
  local item
  while IFS= read -r item; do
    expand_files_entry "$item"
  done < <(split_csv "$raw")
}

# Normalise a path for self-comparison. Resolves to canonical form via cd+pwd
# where possible; falls back to the input if the file no longer exists.
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

files_for_req "$REQ_PATH" | LC_ALL=C sort -u > "$TARGET_FILES_FILE"

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
  files_for_req "$slot" | LC_ALL=C sort -u > "$SLOT_FILES_FILE"
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

  slot_id="$(req_id_from_path "$slot")"
  printf '%s: %s\n' "$slot_id" "$joined"
done <<EOF
$SORTED_SLOTS
EOF

exit 0
