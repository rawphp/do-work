#!/usr/bin/env bash
# pick-req.sh — central deterministic REQ picker for the do-work coordination layer.
#
# Usage: pick-req.sh <scope> <agent-id>
#   <scope>     "any" or a UR id ("UR-NNN") to restrict candidates to one UR.
#   <agent-id>  Caller's agent id (reserved for future logging; not currently used
#               for filtering — the same agent may legitimately re-pick its own
#               released REQs).
#
# Output:
#   stdout: absolute path of the first claimable REQ, or empty.
#   stderr: one line per rejected candidate in the form "<reason>:<detail>",
#           where <reason> is one of: dep | overlap | scope.
#   exit:   0 if a REQ was printed, 1 otherwise.
#
# Decision logic (top to bottom):
#   1. Glob {project}/.do-work/REQ-*.md (milestone-aware if
#      state/active-milestone.md exists — only REQ-M<active>-*.md considered).
#   2. Sort ascending by the leading numeric REQ id (post-M prefix when present).
#   3. For each candidate, in order:
#        a. scope filter: skip if <scope> is a UR id and **UR:** mismatches.
#        b. dep filter: skip if any **Depends on:** id is absent from archive/.
#        c. overlap filter: skip if any **Files:** entry intersects the file set
#           held by any working/ slot (globs expanded against the working tree).
#   4. Print first survivor; exit 0. No survivor → exit 1.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep, sed, awk, sort, cut).

set -u

SCOPE="${1:-any}"
AGENT_ID="${2:-unknown}"
# AGENT_ID currently unused — reserved for future logging/audit.
: "$AGENT_ID"

# Locate the project's .do-work directory.
# Pattern: caller runs the script from the project root, so .do-work is relative.
DOWORK=".do-work"
if [ ! -d "$DOWORK" ]; then
  # Nothing to do — no backlog directory in CWD.
  exit 1
fi

# --- helpers -----------------------------------------------------------------

# Extract a single header field value from a REQ file.
# Args: $1 = field name (e.g. "UR", "Files", "Depends on")
#       $2 = file path
# Prints value to stdout (empty if absent).
extract_field() {
  local field="$1"
  local file="$2"
  # Escape regex specials in field name minimally (we control inputs).
  # Match line: **<field>:** <value>
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

# Split a comma-separated list, trim whitespace around each item, print one per line.
split_csv() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  # POSIX-compatible split. macOS bash 3.2-safe.
  local IFS=','
  # shellcheck disable=SC2206
  local arr=($s)
  local item
  for item in "${arr[@]}"; do
    # Trim leading/trailing whitespace.
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [ -n "$item" ]; then
      printf '%s\n' "$item"
    fi
  done
}

# Extract the REQ id from a REQ filename or first-line heading.
# Filename convention: REQ-NNN-slug.md or REQ-M<n>-NNN-slug.md
# Returns just the REQ id stem we use in **Depends on:** and stderr labels.
req_id_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  # Strip trailing -slug.md, keep REQ-... prefix up through the numeric part.
  # Examples:
  #   REQ-007-add-foo.md       → REQ-007
  #   REQ-M2-041-bar.md        → REQ-M2-041
  # Algorithm: drop the .md, then drop the trailing "-<slug>" by keeping the
  # longest prefix that matches REQ-(M[0-9]+-)?[0-9]+.
  local stem="${base%.md}"
  # Match with awk for portability.
  echo "$stem" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[A-Za-z0-9]+/)) {
      # Fallback for non-numeric ids (test fixtures, alpha labels).
      # Stop at first hyphen after REQ-.
      print substr($0, RSTART, RLENGTH)
    } else {
      print ""
    }
  }'
}

# Extract a sortable numeric key from a REQ path.
# For REQ-NNN → NNN. For REQ-M<m>-NNN → NNN (within a milestone we still sort by NNN).
sort_key_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  echo "$base" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      # extract the trailing number after M<m>-
      s = substr($0, RSTART, RLENGTH)
      sub(/^REQ-M[0-9]+-/, "", s)
      printf "%010d\n", s + 0
    } else if (match($0, /^REQ-[0-9]+/)) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^REQ-/, "", s)
      printf "%010d\n", s + 0
    } else {
      print "9999999999"
    }
  }'
}

# Expand a single Files entry into one path per line (resolved against CWD).
# Globs that don't match anything yield the literal entry (so it can still be
# compared verbatim against another REQ's literal entry).
expand_files_entry() {
  local entry="$1"
  if [ -z "$entry" ]; then
    return 0
  fi
  # Use bash glob expansion. nullglob is bash 3.2-compatible.
  local _old_nullglob
  _old_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob 2>/dev/null || true
  # shellcheck disable=SC2206,SC2086
  local matches=( $entry )
  eval "$_old_nullglob" 2>/dev/null || true
  if [ "${#matches[@]}" -eq 0 ]; then
    # No filesystem matches — return the literal entry for literal comparison.
    printf '%s\n' "$entry"
  else
    local m
    for m in "${matches[@]}"; do
      printf '%s\n' "$m"
    done
  fi
}

# Print all files (expanded) claimed by a REQ at $1.
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

# --- main -------------------------------------------------------------------

# Determine glob pattern based on milestone mode.
MILESTONE_FILE="$DOWORK/state/active-milestone.md"
GLOB_PATTERN="$DOWORK/REQ-*.md"
if [ -f "$MILESTONE_FILE" ]; then
  ACTIVE_MILESTONE="$(head -n1 "$MILESTONE_FILE" | tr -d '[:space:]')"
  if [ -n "$ACTIVE_MILESTONE" ]; then
    GLOB_PATTERN="$DOWORK/REQ-${ACTIVE_MILESTONE}-*.md"
  fi
fi

# Collect candidates.
shopt -s nullglob 2>/dev/null || true
# shellcheck disable=SC2206
CANDIDATES=( $GLOB_PATTERN )

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  exit 1
fi

# Sort ascending by numeric REQ id. Build "<key>\t<path>" then sort -k1n.
SORTED_LIST=""
for c in "${CANDIDATES[@]}"; do
  key="$(sort_key_from_path "$c")"
  SORTED_LIST="${SORTED_LIST}${key}	${c}
"
done
# Remove trailing newline-ambiguity via printf, then sort.
SORTED_CANDIDATES="$(printf '%s' "$SORTED_LIST" | sort -k1,1 | cut -f2-)"

# Precompute the set of files held by working/ slots.
# Format: each line = "<req-id>\t<expanded-path>"
WORKING_FOOTPRINT_FILE="$(mktemp -t pick-req-footprint.XXXXXX)"
# Cleanup on exit.
trap 'rm -f "$WORKING_FOOTPRINT_FILE"' EXIT

# Build footprint index.
for slot in "$DOWORK"/working/REQ-*.md; do
  [ -e "$slot" ] || continue
  slot_id="$(req_id_from_path "$slot")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\t%s\n' "$slot_id" "$f" >> "$WORKING_FOOTPRINT_FILE"
  done < <(files_for_req "$slot")
done

# Resolve absolute path of the project root for emitting absolute candidate paths.
PROJECT_ROOT="$(pwd)"

# Iterate candidates in sorted order.
# Use a here-string fed via printf to be 3.2-safe.
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  [ -e "$candidate" ] || continue

  cand_id="$(req_id_from_path "$candidate")"

  # --- scope filter ---
  if [ "$SCOPE" != "any" ]; then
    cand_ur="$(extract_field "UR" "$candidate")"
    if [ "$cand_ur" != "$SCOPE" ]; then
      printf 'scope:%s\n' "$cand_ur" >&2
      continue
    fi
  fi

  # --- dep filter ---
  deps_raw="$(extract_field "Depends on" "$candidate")"
  dep_blocked=0
  if [ -n "$deps_raw" ]; then
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      # Is there an archive/<dep>-*.md or archive/<dep>.md?
      shopt -s nullglob 2>/dev/null || true
      # shellcheck disable=SC2206
      archived=( "$DOWORK"/archive/"$dep"-*.md )
      found=0
      if [ "${#archived[@]}" -gt 0 ]; then
        for a in "${archived[@]}"; do
          if [ -e "$a" ]; then
            found=1
            break
          fi
        done
      fi
      if [ "$found" -eq 0 ] && [ -e "$DOWORK/archive/$dep.md" ]; then
        found=1
      fi
      if [ "$found" -eq 0 ]; then
        printf 'dep:%s\n' "$dep" >&2
        dep_blocked=1
        break
      fi
    done < <(split_csv "$deps_raw")
  fi
  if [ "$dep_blocked" -eq 1 ]; then
    continue
  fi

  # --- overlap filter ---
  # Build set of candidate's expanded files; check against working footprint.
  overlap_slot=""
  overlap_found=0
  while IFS= read -r cand_file; do
    [ -n "$cand_file" ] || continue
    # Look for any working footprint line whose path equals cand_file.
    if [ -s "$WORKING_FOOTPRINT_FILE" ]; then
      match="$(awk -F'\t' -v p="$cand_file" '$2 == p { print "MATCH:" $1; exit }' "$WORKING_FOOTPRINT_FILE")"
      if [ -n "$match" ]; then
        overlap_slot="${match#MATCH:}"
        overlap_found=1
        break
      fi
    fi
  done < <(files_for_req "$candidate")

  if [ "$overlap_found" -eq 1 ]; then
    printf 'overlap:%s\n' "$overlap_slot" >&2
    continue
  fi

  # --- survivor ---
  # Emit absolute path.
  case "$candidate" in
    /*) printf '%s\n' "$candidate" ;;
    *)  printf '%s/%s\n' "$PROJECT_ROOT" "$candidate" ;;
  esac
  exit 0
done <<EOF
$SORTED_CANDIDATES
EOF

# No survivors.
exit 1
