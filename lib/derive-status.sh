#!/usr/bin/env bash
# derive-status.sh — compute a proof-backed status view for REQ files.
#
# Usage:
#   derive-status.sh <req-path> [<req-path> ...]
#
# Prints one line per REQ: "<REQ-ID> proven" or "<REQ-ID> unproven".
# A REQ is proven only when it is done/archived and has a non-empty
# `**Closure proof:**` field. This deliberately does not replace writable
# `**Status:**`, which remains coordination state.
#
# An orchestrator-stamped `**Suite:** not-run` header downgrades an
# otherwise-proven REQ to unproven — its test/build suite never ran, so
# "proven" would overclaim. Absent or any-other-value `**Suite:**` leaves
# derivation unchanged. Human/device advisory items never affect this.

set -u

if [ "$#" -lt 1 ]; then
  echo "Usage: derive-status.sh <req-path> [<req-path> ...]" >&2
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

for req_path in "$@"; do
  if [ ! -e "$req_path" ]; then
    echo "derive-status.sh: REQ not found: $req_path" >&2
    exit 1
  fi

  req_id="$(req_id_from_path "$req_path")"
  status="$(extract_field "Status" "$req_path")"
  proof="$(extract_field "Closure proof" "$req_path")"
  suite="$(extract_field "Suite" "$req_path")"

  # Archive location is accepted as done even if an older file's Status line
  # has drifted. Backlog/working files must explicitly say done to be proven.
  archived=0
  case "$req_path" in
    */.do-work/archive/REQ-*.md|.do-work/archive/REQ-*.md) archived=1 ;;
  esac

  if { [ "$status" = "done" ] || [ "$archived" = "1" ]; } && [ -n "$proof" ] && [ "$suite" != "not-run" ]; then
    printf '%s proven\n' "$req_id"
  else
    printf '%s unproven\n' "$req_id"
  fi
done
