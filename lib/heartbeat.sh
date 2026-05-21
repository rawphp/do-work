#!/usr/bin/env bash
# heartbeat.sh — update the **Heartbeat:** field inside a working/ REQ slot's
# claim stamp to the current ISO-8601 UTC timestamp.
#
# Usage: heartbeat.sh <req-path>
#   <req-path>  Path (relative or absolute) to a REQ file living under
#               `.../.do-work/working/`. The file must contain a claim stamp
#               wrapped in `<!-- claimed-start --> ... <!-- claimed-end -->`.
#
# Behaviour:
#   - If <req-path> does not exist: print to stderr, exit 1.
#     (The caller — typically the worker's background heartbeat loop — should
#      treat exit 1 as the signal to stop heartbeating.)
#   - If <req-path> is not under a `.do-work/working/` directory: warn on
#     stderr, exit 1. Heartbeat is only meaningful for in-progress slots.
#   - If the claim stamp already has a `**Heartbeat:** ...` line: replace it
#     in place.
#   - If the claim stamp is present but has no Heartbeat line: insert one
#     immediately before `<!-- claimed-end -->`.
#   - If the claim stamp is missing entirely: exit 1.
#
#   No git commands. No staging. No commit. Sibling agents read the heartbeat
#   directly from the filesystem.
#
# Exit codes:
#   0  Heartbeat updated (insert or replace) successfully.
#   1  Any failure: missing file, file outside working/, no claim stamp,
#      sed/awk write failure.
#
# Compatible with macOS bash 3.2 + BSD sed/awk/date.
# Standard POSIX tools only.

set -u

# --- args -------------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  echo "Usage: heartbeat.sh <req-path>" >&2
  exit 1
fi

REQ_PATH="$1"

# --- validate file exists ---------------------------------------------------

if [ ! -e "$REQ_PATH" ]; then
  echo "heartbeat.sh: REQ file not found: $REQ_PATH" >&2
  exit 1
fi

if [ ! -f "$REQ_PATH" ]; then
  echo "heartbeat.sh: REQ path is not a regular file: $REQ_PATH" >&2
  exit 1
fi

# --- validate file is under .do-work/working/ -------------------------------

# Inspect the parent directory's basename and its parent's basename. We need
# the file to live in `<...>/.do-work/working/<file>`, so:
#   parent basename       == "working"
#   grandparent basename  == ".do-work"
REQ_PARENT="$(dirname "$REQ_PATH")"
REQ_PARENT_BASE="$(basename "$REQ_PARENT")"
REQ_GRANDPARENT="$(dirname "$REQ_PARENT")"
REQ_GRANDPARENT_BASE="$(basename "$REQ_GRANDPARENT")"

if [ "$REQ_PARENT_BASE" != "working" ] || [ "$REQ_GRANDPARENT_BASE" != ".do-work" ]; then
  echo "heartbeat.sh: refusing to heartbeat — REQ is outside .do-work/working/: $REQ_PATH" >&2
  exit 1
fi

# --- compute timestamp ------------------------------------------------------

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- locate claim stamp block ----------------------------------------------

# Find the line numbers of the claim-start and claim-end markers.
START_LINE="$(grep -n '^<!-- claimed-start -->$' "$REQ_PATH" | head -1 | cut -d: -f1)"
END_LINE="$(grep -n '^<!-- claimed-end -->$' "$REQ_PATH" | head -1 | cut -d: -f1)"

if [ -z "$START_LINE" ] || [ -z "$END_LINE" ]; then
  echo "heartbeat.sh: claim stamp not found in $REQ_PATH" >&2
  exit 1
fi

if [ "$START_LINE" -ge "$END_LINE" ]; then
  echo "heartbeat.sh: malformed claim stamp (start >= end) in $REQ_PATH" >&2
  exit 1
fi

# Does a Heartbeat line exist inside the claim block?
# We search the whole file then check whether any matched line number is
# between START_LINE and END_LINE.
HB_LINE=""
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  hit_n="$(printf '%s' "$hit" | cut -d: -f1)"
  if [ "$hit_n" -gt "$START_LINE" ] && [ "$hit_n" -lt "$END_LINE" ]; then
    HB_LINE="$hit_n"
    break
  fi
done <<EOF
$(grep -n '^\*\*Heartbeat:\*\*' "$REQ_PATH" || true)
EOF

# --- rewrite -----------------------------------------------------------------

TMP_OUT="$(mktemp -t heartbeat-out.XXXXXX)"

# Use awk to do the in-place rewrite. We pass the relevant line numbers and
# the new timestamp via -v. BSD awk on macOS supports all of this.
#
# Two modes:
#   mode=replace  → replace the line at HB_LINE with the new Heartbeat line.
#   mode=insert   → emit the new Heartbeat line immediately before END_LINE.
if [ -n "$HB_LINE" ]; then
  MODE="replace"
else
  MODE="insert"
fi

awk -v mode="$MODE" \
    -v hb_line="${HB_LINE:-0}" \
    -v end_line="$END_LINE" \
    -v now="$NOW_ISO" '
{
  if (mode == "replace" && NR == hb_line) {
    print "**Heartbeat:** " now
    next
  }
  if (mode == "insert" && NR == end_line) {
    print "**Heartbeat:** " now
    print $0
    next
  }
  print
}
' "$REQ_PATH" > "$TMP_OUT" || {
  rm -f "$TMP_OUT"
  echo "heartbeat.sh: awk rewrite failed for $REQ_PATH" >&2
  exit 1
}

# Sanity check: ensure the output file is non-empty and contains a Heartbeat
# line. (Catches catastrophic awk truncation.)
if [ ! -s "$TMP_OUT" ]; then
  rm -f "$TMP_OUT"
  echo "heartbeat.sh: rewrite produced empty file for $REQ_PATH" >&2
  exit 1
fi
if ! grep -q '^\*\*Heartbeat:\*\*' "$TMP_OUT"; then
  rm -f "$TMP_OUT"
  echo "heartbeat.sh: rewrite did not produce a Heartbeat line in $REQ_PATH" >&2
  exit 1
fi

if ! mv "$TMP_OUT" "$REQ_PATH"; then
  rm -f "$TMP_OUT"
  echo "heartbeat.sh: failed to write updated REQ to $REQ_PATH" >&2
  exit 1
fi

exit 0
