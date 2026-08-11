#!/usr/bin/env bash
# eligibility-common.sh — canonical markdown eligibility helpers.
#
# Single source of truth for the dependency + footprint eligibility primitives
# that check-deps.sh, check-footprint.sh, pick-req.sh (and synth-status.sh's
# dep-parse mirror) share. Sourcing this kills the hand-copied duplicates that
# silently drifted (F1 / UR-003).
#
# This file defines FUNCTIONS ONLY. It must not execute anything on source.
# Callers `source` it after setting DOWORK (default ".do-work") if they need the
# archive predicate.
#
# Canonical definitions (port.md is the authority — "a dependency is satisfied
# only when the depended-on REQ is archived/done"; "free footprint = no
# in-flight REQ's footprint overlaps the candidate's declared paths"):
#
#   * dep satisfied  → archive/<id>-*.md glob matches OR exact archive/<id>.md
#                      exists (union of the two historical definitions; does not
#                      regress pick-req, tightens check-deps to agree).
#   * Files expansion → `**`-globstar-aware (manual walker; bash 3.2 has no
#                      `shopt globstar`). A plain entry that matches nothing is
#                      RETAINED as a literal so two REQs claiming the same
#                      not-yet-existing path still conflict.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4. Standard POSIX tools only.

# Extract a single header field value from a REQ file.
# Args: $1 = field name (e.g. "Files", "Depends on"), $2 = file path.
# Prints value to stdout (empty if absent).
elig_extract_field() {
  local field="$1"
  local file="$2"
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

# Split a comma-separated list (the **Files:** field), trim whitespace, print
# one item per line. (Do NOT use for **Depends on:** — use elig_split_dep_ids.)
elig_split_csv() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  # bash 3.2 + `set -u`: relax nounset around empty arrays; disable globbing so
  # an entry containing `*` is not expanded during the split.
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

# Split a **Depends on:** value on commas AND/OR runs of whitespace.
# Delimiter-tolerant: "REQ-144 REQ-145" and "REQ-144, REQ-145" tokenize the same.
# Does not validate id shape — callers that need validation do so themselves.
elig_split_dep_ids() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  set +u
  set -f
  s="${s//,/ }"
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

# Extract the REQ id from a REQ filename or first-line heading.
# REQ-NNN-slug.md → REQ-NNN ; REQ-M<n>-NNN-slug.md → REQ-M<n>-NNN.
elig_req_id_from_path() {
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
# Translates the pattern into a directory prefix + tail filter so that
# `src/**/*.ts` matches all .ts under src/ recursively.
elig_expand_globstar_pattern() {
  local pattern="$1"
  local before="${pattern%%\*\**}"
  local after="${pattern#*\*\*}"
  local root="$before"
  root="${root%/}"
  if [ -z "$root" ]; then
    root="."
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi
  local suffix="${after#/}"
  local f
  while IFS= read -r f; do
    case "$f" in
      ./*) f="${f#./}" ;;
    esac
    local tail_ok=0
    if [ -z "$suffix" ]; then
      tail_ok=1
    else
      case "$f" in
        $before*$suffix) tail_ok=1 ;;
      esac
    fi
    if [ "$tail_ok" = "1" ]; then
      if [ -f "$f" ]; then
        printf '%s\n' "$f"
      fi
    fi
  done < <(find "$root" -type f -print 2>/dev/null)
}

# Expand a single Files entry into one path per line (resolved against CWD).
# `**` patterns use the manual walker; plain entries use bash glob expansion and
# RETAIN the literal token when nothing matches (so two REQs declaring the same
# not-yet-existing path still conflict). Empty input produces no output.
elig_expand_files_entry() {
  local entry="$1"
  if [ -z "$entry" ]; then
    return 0
  fi
  case "$entry" in
    *\*\**)
      elig_expand_globstar_pattern "$entry"
      return 0
      ;;
  esac
  local _old_nullglob
  _old_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob 2>/dev/null || true
  # shellcheck disable=SC2206,SC2086
  local matches=( $entry )
  eval "$_old_nullglob" 2>/dev/null || true
  if [ "${#matches[@]}" -eq 0 ]; then
    # No filesystem matches — retain the literal for literal comparison.
    printf '%s\n' "$entry"
  else
    local m
    for m in "${matches[@]}"; do
      printf '%s\n' "$m"
    done
  fi
}

# Print all files (expanded) declared by a REQ at $1. One path per line.
elig_files_for_req() {
  local path="$1"
  local raw
  raw="$(elig_extract_field "Files" "$path")"
  if [ -z "$raw" ]; then
    return 0
  fi
  local item
  while IFS= read -r item; do
    elig_expand_files_entry "$item"
  done < <(elig_split_csv "$raw")
}

# Return 0 if a dep id is satisfied — i.e. at least one archive file matches
# `archive/<id>-*.md` OR an exact `archive/<id>.md` exists. 1 otherwise.
# Uses $DOWORK (default ".do-work") as the store root.
elig_is_dep_satisfied() {
  local id="$1"
  local dw="${DOWORK:-.do-work}"
  shopt -s nullglob 2>/dev/null || true
  # shellcheck disable=SC2206
  local archive_matches=( "$dw"/archive/"$id"-*.md )
  if [ "${#archive_matches[@]}" -gt 0 ]; then
    return 0
  fi
  if [ -e "$dw/archive/$id.md" ]; then
    return 0
  fi
  return 1
}
