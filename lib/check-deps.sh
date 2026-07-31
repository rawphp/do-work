#!/usr/bin/env bash
# check-deps.sh — dependency satisfaction check for a REQ.
#
# Usage: check-deps.sh <req-path>
#   <req-path>  Path (relative or absolute) to a REQ file. The script parses
#               its `**Depends on:**` field and reports any ids that are NOT
#               yet satisfied.
#
# Behavior:
#   1. Parses this REQ's `**Depends on:**` field — REQ ids separated by commas
#      and/or runs of whitespace (may be empty). The field line may be omitted
#      entirely (treated as empty).
#   2. Validates each id against `REQ-\d+` or `REQ-M\d+-\d+` (milestone form).
#      Malformed ids are logged to stderr and NOT included in the missing-list.
#   3. For each valid id, globs `{project}/.do-work/archive/<id>-*.md`.
#      If no file matches, prints the id to stdout (one per line).
#   4. Empty `**Depends on:**` → empty stdout. Exits 0 in all non-error cases.
#
# Notes:
#   - `.do-work/` is located via CWD (callers run from the project root, same
#     convention as pick-req.sh / check-footprint.sh).
#   - The glob uses the trailing hyphen (`<id>-*.md`) so REQ-005 does not match
#     REQ-0050-foo.md.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep, sed, awk).

set -u

REQ_PATH="${1:-}"

if [ -z "$REQ_PATH" ]; then
  echo "Usage: check-deps.sh <req-path>" >&2
  exit 1
fi

if [ ! -e "$REQ_PATH" ]; then
  echo "check-deps.sh: REQ not found: $REQ_PATH" >&2
  exit 1
fi

DOWORK=".do-work"
# If there's no .do-work dir we can't resolve archive — but the script should
# still emit the ids as "missing" (an absent archive means nothing is satisfied).
# However, for now treat no archive dir as no archived files (all valid deps
# will be reported missing). This matches the spirit of pick-req.sh's archive
# glob behavior.

# --- helpers -----------------------------------------------------------------

# Extract a single header field value from a REQ file.
# Args: $1 = field name (e.g. "Depends on"), $2 = file path
# Prints value to stdout (empty if absent).
extract_field() {
  local field="$1"
  local file="$2"
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

# Split a **Depends on:** value on commas AND/OR runs of whitespace.
# Trim each token, drop empties, print one id per line. Delimiter-tolerant so
# both "REQ-144 REQ-145" and "REQ-144, REQ-145" (and mixed) tokenize the same.
# Must agree with pick-req.sh's split_dep_ids.
split_dep_ids() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  # bash 3.2 + `set -u` treats `${arr[@]}` on a zero-element array as unbound,
  # so we relax nounset for the duration of this helper. Disable pathname
  # expansion so entries containing `*` don't get expanded during the split.
  set +u
  set -f
  # Normalize commas to spaces, then word-split on whitespace runs.
  s="${s//,/ }"
  # shellcheck disable=SC2206
  local arr=($s)
  set +f
  local item
  for item in "${arr[@]}"; do
    # Trim leading/trailing whitespace.
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [ -n "$item" ]; then
      printf '%s\n' "$item"
    fi
  done
  set -u
}

# Validate a REQ id matches REQ-\d+ or REQ-M\d+-\d+.
# Returns 0 if valid, 1 otherwise.
is_valid_req_id() {
  local id="$1"
  case "$id" in
    REQ-M[0-9]*-[0-9]*)
      # Confirm the M<digits> and trailing digits sub-segments are all numeric.
      # Use awk for portable regex validation.
      echo "$id" | awk '/^REQ-M[0-9]+-[0-9]+$/ { ok=1 } END { exit (ok ? 0 : 1) }'
      return $?
      ;;
    REQ-[0-9]*)
      echo "$id" | awk '/^REQ-[0-9]+$/ { ok=1 } END { exit (ok ? 0 : 1) }'
      return $?
      ;;
  esac
  return 1
}

# Check if a dep id is satisfied — i.e. at least one file matching <id>-*.md
# exists in `.do-work/archive/`.
# Returns 0 if satisfied, 1 otherwise.
is_satisfied() {
  local id="$1"
  shopt -s nullglob 2>/dev/null || true
  # shellcheck disable=SC2206
  local archive_matches=( "$DOWORK"/archive/"$id"-*.md )
  if [ "${#archive_matches[@]}" -gt 0 ]; then
    return 0
  fi
  return 1
}

# --- main -------------------------------------------------------------------

DEPS_RAW="$(extract_field "Depends on" "$REQ_PATH")"

if [ -z "$DEPS_RAW" ]; then
  exit 0
fi

while IFS= read -r dep; do
  [ -n "$dep" ] || continue
  if ! is_valid_req_id "$dep"; then
    printf 'check-deps: malformed REQ id ignored: %s\n' "$dep" >&2
    continue
  fi
  if ! is_satisfied "$dep"; then
    printf '%s\n' "$dep"
  fi
done < <(split_dep_ids "$DEPS_RAW")

exit 0
