#!/usr/bin/env bash
# resolve-session.sh — resolve the current do-work session id from a project's
# events.jsonl telemetry stream, for stamping into a REQ claim block's
# `**Session:**` field.
#
# Usage: resolve-session.sh <project-root>
#   <project-root>  Directory containing .do-work/ (events are read from
#                   <project-root>/.do-work/state/events.jsonl).
#
# Resolution order:
#   1. Marker correlation. When $DO_WORK_UI_MARKER is set and non-empty, print
#      the session id of the LATEST `session.start` line whose `data.marker`
#      equals it. This is the terminal→session correlation the extension relies
#      on (the marker is exported per-terminal and echoed into session.start by
#      the SessionStart hook — see lib/session-hook.sh). Preferred when the
#      marker matches; unchanged by fallback semantics.
#   2. Fallback: the single un-ended session (last-event semantics). A session
#      is un-ended when its *last* event for that session id is `session.start`
#      — i.e. it has a start and no later end. A prior `session.end` does not
#      permanently retire the id: start→end→start is un-ended again.
#      Implementation: one pass over events.jsonl tracking the last
#      start|end type per session id; candidates are ids whose last type is
#      start. If exactly one candidate, print it.
#   3. Otherwise print NOTHING — no events file, no candidate, or more than one
#      un-ended session with no marker match. The claim block then omits the
#      `**Session:**` line entirely rather than guessing between candidates.
#
# Always exits 0. Prints at most one session id (nothing else) to stdout.
# Compatible with macOS bash 3.2 + BSD userland. No jq dependency.

set -u

PROJECT="${1:-}"
[ -n "$PROJECT" ] || exit 0

EVENTS="$PROJECT/.do-work/state/events.jsonl"
[ -f "$EVENTS" ] || exit 0

# Extract the "session" string field value from a single JSON line. Tolerant of
# optional whitespace around the colon; the emitter writes it compact.
session_of() {
  # NOTE: feed sed a trailing newline. BSD sed preserves a missing final
  # newline, which would glue accumulated tokens together (sess-Xsess-Y).
  printf '%s\n' "$1" \
    | sed -n 's/.*"session"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

MARKER="${DO_WORK_UI_MARKER:-}"

# --- 1. marker correlation --------------------------------------------------
if [ -n "$MARKER" ]; then
  # Latest session.start line carrying data.marker == MARKER. Both the event
  # type and the full `"marker":"<value>"` fragment (with trailing quote) are
  # matched as FIXED strings, so m1 never false-matches m10.
  line="$(grep -F '"type":"session.start"' "$EVENTS" 2>/dev/null \
          | grep -F -- "\"marker\":\"$MARKER\"" | tail -n1)"
  if [ -n "$line" ]; then
    sid="$(session_of "$line")"
    if [ -n "$sid" ]; then
      printf '%s\n' "$sid"
      exit 0
    fi
  fi
fi

# --- 2. fallback: single un-ended session (last-event semantics) ------------
# One pass over events.jsonl: track last session.start|session.end type per id.
# Candidates = sessions whose last event is session.start.
# Exactly one candidate → print; zero or >1 → omit (never guess).
# bash 3.2: no associative arrays — keep "sid:type" tokens in last_map.

CANDIDATE=""
COUNT=0
last_map=""

while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  case "$line" in
    *'"type":"session.start"'*) typ="start" ;;
    *'"type":"session.end"'*)   typ="end" ;;
    *) continue ;;
  esac
  sid="$(session_of "$line")"
  [ -n "$sid" ] || continue
  # Drop any prior entry for this sid so the final token is the last event.
  rebuilt=""
  for tok in $last_map; do
    case "$tok" in
      "${sid}:"*) ;;
      *) rebuilt="$rebuilt $tok" ;;
    esac
  done
  last_map="$rebuilt ${sid}:$typ"
done < "$EVENTS"

for tok in $last_map; do
  case "$tok" in
    *:start)
      CANDIDATE="${tok%:*}"
      COUNT=$((COUNT + 1))
      ;;
  esac
done

# Exactly one un-ended session → unambiguous. Zero or >1 → omit (never guess).
if [ "$COUNT" = "1" ]; then
  printf '%s\n' "$CANDIDATE"
fi
exit 0
