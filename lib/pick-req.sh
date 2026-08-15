#!/usr/bin/env bash
# pick-req.sh — central deterministic REQ picker for the do-work coordination layer.
#
# Usage: pick-req.sh <scope> <agent-id>
#   <scope>     "any" or an Issue id ("UR-NNN") to restrict candidates to one Issue.
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
#   2. Sort by Priority descending, then numeric REQ id ascending.
#   3. For each candidate, in order:
#        a. scope filter: skip if <scope> is an Issue id (UR-NNN) and **UR:** mismatches.
#        b. dep filter: skip if any **Depends on:** id is absent from archive/.
#        c. overlap filter: skip if any **Files:** entry intersects the file set
#           held by any working/ slot (globs expanded against the working tree,
#           including `**`).
#   4. Print first survivor; exit 0. No survivor → exit 1.
#
# Field parsing, id splitting, file/glob expansion, and the dep-satisfied
# predicate come from the shared `lib/eligibility-common.sh` so pick-req,
# check-deps, and check-footprint cannot drift apart (F1 / UR-003). The stderr
# wire format (`dep:`/`overlap:`/`scope:`) is consumed by drain-classify.sh and
# is preserved exactly.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4. Standard POSIX tools only.

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

# --- shared eligibility helpers (canonical; sourced, not duplicated) ---------
_SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=eligibility-common.sh
source "$_SELF_DIR/eligibility-common.sh"

# --- helpers (pick-req-specific sort keys) -----------------------------------

# Extract a sortable numeric key from a REQ path.
# For REQ-NNN → NNN. For REQ-M<m>-NNN → NNN (within a milestone we still sort by NNN).
sort_key_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  echo "$base" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
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

# Extract the **Priority:** value from a REQ file as a sortable ascending key.
# Priority is 1-3 (3 = most urgent). An absent or malformed Priority sorts
# exactly as Priority 2. Returns an inverted key (higher Priority => smaller
# key) so a plain ascending sort selects the most urgent REQ first.
priority_sort_key_from_path() {
  local path="$1"
  local raw
  raw="$(elig_extract_field "Priority" "$path")"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  local pri=2
  case "$raw" in
    1|2|3) pri="$raw" ;;
    *) pri=2 ;;
  esac
  printf '%d' "$(( 9 - pri ))"
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

# Order claimable candidates by Priority descending, then by numeric REQ id
# ascending (the historical tiebreak). An absent **Priority:** field maps to
# Priority 2, so a backlog with no Priority fields sorts purely by REQ number
# exactly as before this feature existed.
SORTED_LIST=""
for c in "${CANDIDATES[@]}"; do
  pri_key="$(priority_sort_key_from_path "$c")"
  num_key="$(sort_key_from_path "$c")"
  SORTED_LIST="${SORTED_LIST}${pri_key}	${num_key}	${c}
"
done
SORTED_CANDIDATES="$(printf '%s' "$SORTED_LIST" | sort -k1,1 -k2,2 | cut -f3-)"

# Precompute the set of files held by working/ slots.
# Format: each line = "<req-id>\t<expanded-path>"
WORKING_FOOTPRINT_FILE="$(mktemp -t pick-req-footprint.XXXXXX)"
trap 'rm -f "$WORKING_FOOTPRINT_FILE"' EXIT

# Build footprint index.
for slot in "$DOWORK"/working/REQ-*.md; do
  [ -e "$slot" ] || continue
  slot_id="$(elig_req_id_from_path "$slot")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\t%s\n' "$slot_id" "$f" >> "$WORKING_FOOTPRINT_FILE"
  done < <(elig_files_for_req "$slot")
done

# Resolve absolute path of the project root for emitting absolute candidate paths.
PROJECT_ROOT="$(pwd)"

# Iterate candidates in sorted order.
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  [ -e "$candidate" ] || continue

  cand_id="$(elig_req_id_from_path "$candidate")"

  # --- scope filter ---
  if [ "$SCOPE" != "any" ]; then
    cand_ur="$(elig_extract_field "UR" "$candidate")"
    if [ "$cand_ur" != "$SCOPE" ]; then
      printf 'scope:%s\n' "$cand_ur" >&2
      continue
    fi
  fi

  # --- dep filter ---
  deps_raw="$(elig_extract_field "Depends on" "$candidate")"
  dep_blocked=0
  if [ -n "$deps_raw" ]; then
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      if ! elig_is_dep_satisfied "$dep"; then
        printf 'dep:%s\n' "$dep" >&2
        dep_blocked=1
        break
      fi
    done < <(elig_split_dep_ids "$deps_raw")
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
  done < <(elig_files_for_req "$candidate")

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
