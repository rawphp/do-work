#!/usr/bin/env bash
# coverage-rollup.sh — summarize intended vs proof-backed completed REQs.
#
# Usage:
#   coverage-rollup.sh [UR-NNN]
#
# Prints one line per UR:
#   UR-001 intended=3 proven=1 unproven=2 unproven_ids=REQ-002,REQ-003 closed=n/a
#
# The trailing `closed=<yes|no|n/a>` field reports end-to-end UR closure
# (per docs/design/ur-closure.md), derived from the UR's path-unit REQs
# (REQs with `**Layer:** none`) and its `user-requests/UR-NNN/closure.md`:
#   yes  — closure.md exists with `overall: closed`
#   no   — closure.md exists with a non-closed `overall` (e.g. gaps),
#          OR no closure.md while the UR has path-unit REQs
#   n/a  — the UR has no path-unit REQs
# This field is additive; the existing intended/proven/unproven math is unchanged.

set -u

SCOPE="${1:-}"
DOWORK=".do-work"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DERIVE="$SCRIPT_DIR/derive-status.sh"

if [ ! -x "$DERIVE" ]; then
  echo "coverage-rollup.sh: derive-status.sh not executable: $DERIVE" >&2
  exit 1
fi

extract_field() {
  local field="$1"
  local file="$2"
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

req_id_from_path() {
  basename "$1" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else {
      print "REQ-UNKNOWN"
    }
  }'
}

# Reads the `overall:` value from a UR's closure.md front matter.
# Prints the value (e.g. "closed", "gaps", "no-path-units") or nothing if absent.
closure_overall() {
  local ur="$1"
  local file="$DOWORK/user-requests/$ur/closure.md"
  [ -f "$file" ] || return 0
  grep -m1 -E "^overall:[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^overall:[[:space:]]*//" | tr -d '[:space:]'
}

TMP_ROWS="$(mktemp -t coverage-rollup.XXXXXX)"
trap 'rm -f "$TMP_ROWS"' EXIT

for dir in "$DOWORK" "$DOWORK/working" "$DOWORK/archive"; do
  [ -d "$dir" ] || continue
  for req in "$dir"/REQ-*.md; do
    [ -e "$req" ] || continue
    ur="$(extract_field "UR" "$req")"
    [ -n "$ur" ] || continue
    if [ -n "$SCOPE" ] && [ "$ur" != "$SCOPE" ]; then
      continue
    fi
    id="$(req_id_from_path "$req")"
    derived="$(bash "$DERIVE" "$req" | awk '{ print $2 }')"
    layer="$(extract_field "Layer" "$req")"
    pathunit=0
    [ "$layer" = "none" ] && pathunit=1
    printf 'ROW %s %s %s %s\n' "$ur" "$id" "$derived" "$pathunit" >> "$TMP_ROWS"
  done
done

if [ ! -s "$TMP_ROWS" ]; then
  exit 0
fi

# Resolve end-to-end closure state per UR and append CLOSURE prelude lines.
# Done before awk so the file-reading stays in bash (portable, no awk getline).
for ur in $(awk '$1=="ROW" { print $2 }' "$TMP_ROWS" | sort -u); do
  overall="$(closure_overall "$ur")"
  printf 'CLOSURE %s %s\n' "$ur" "${overall:-__none__}" >> "$TMP_ROWS"
done

awk '
$1 == "CLOSURE" {
  overall[$2] = $3
  next
}
$1 == "ROW" {
  ur=$2; id=$3; state=$4; pathunit=$5
  if (!(ur in seen)) { order[++n]=ur; seen[ur]=1 }
  intended[ur]++
  if (pathunit == 1) has_pathunit[ur]=1
  if (state == "proven") {
    proven[ur]++
  } else {
    unproven[ur]++
    if (unproven_ids[ur] == "") unproven_ids[ur]=id
    else unproven_ids[ur]=unproven_ids[ur] "," id
  }
}
END {
  for (i=1; i<=n; i++) {
    ur=order[i]
    printf "%s intended=%d proven=%d unproven=%d", ur, intended[ur]+0, proven[ur]+0, unproven[ur]+0
    if ((unproven[ur]+0) > 0) printf " unproven_ids=%s", unproven_ids[ur]
    # End-to-end closure column (additive). See header comment for semantics.
    if (!(ur in has_pathunit)) {
      closed = "n/a"
    } else if (overall[ur] == "closed") {
      closed = "yes"
    } else {
      # gaps, no closure.md (__none__), or any other non-closed overall.
      closed = "no"
    }
    printf " closed=%s", closed
    print ""
  }
}
' "$TMP_ROWS"
