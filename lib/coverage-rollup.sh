#!/usr/bin/env bash
# coverage-rollup.sh — summarize intended vs proof-backed completed REQs.
#
# Usage:
#   coverage-rollup.sh [UR-NNN]
#
# Prints one line per UR:
#   UR-001 intended=3 proven=1 unproven=2 unproven_ids=REQ-002,REQ-003

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
    printf '%s %s %s\n' "$ur" "$id" "$derived" >> "$TMP_ROWS"
  done
done

if [ ! -s "$TMP_ROWS" ]; then
  exit 0
fi

awk '
{
  ur=$1; id=$2; state=$3
  if (!(ur in seen)) { order[++n]=ur; seen[ur]=1 }
  intended[ur]++
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
    print ""
  }
}
' "$TMP_ROWS"

