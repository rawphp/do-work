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
#   3. For each valid id, checks `.do-work/archive/` for `<id>-*.md` OR an exact
#      `<id>.md`. If neither matches, prints the id to stdout (one per line).
#   4. Empty `**Depends on:**` → empty stdout. Exits 0 in all non-error cases.
#
# Notes:
#   - Field parsing, id splitting, and the dep-satisfied predicate come from the
#     shared `lib/eligibility-common.sh` so check-deps, check-footprint, and
#     pick-req cannot drift apart (F1 / UR-003).
#   - `.do-work/` is located via CWD (callers run from the project root, same
#     convention as pick-req.sh / check-footprint.sh).
#
# Compatible with macOS bash 3.2 and Linux bash >= 4. Standard POSIX tools only.

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
# Treat no archive dir as no archived files (all valid deps reported missing).

# --- shared eligibility helpers (canonical; sourced, not duplicated) ---------
_SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=eligibility-common.sh
source "$_SELF_DIR/eligibility-common.sh"

# --- helpers -----------------------------------------------------------------

# Validate a REQ id matches REQ-\d+ or REQ-M\d+-\d+.
# Returns 0 if valid, 1 otherwise. (check-deps-specific — pick-req does not
# validate id shape.)
is_valid_req_id() {
  local id="$1"
  case "$id" in
    REQ-M[0-9]*-[0-9]*)
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

# --- main -------------------------------------------------------------------

DEPS_RAW="$(elig_extract_field "Depends on" "$REQ_PATH")"

if [ -z "$DEPS_RAW" ]; then
  exit 0
fi

while IFS= read -r dep; do
  [ -n "$dep" ] || continue
  if ! is_valid_req_id "$dep"; then
    printf 'check-deps: malformed REQ id ignored: %s\n' "$dep" >&2
    continue
  fi
  if ! elig_is_dep_satisfied "$dep"; then
    printf '%s\n' "$dep"
  fi
done < <(elig_split_dep_ids "$DEPS_RAW")

exit 0
