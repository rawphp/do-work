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
#      the SessionStart hook — see lib/session-hook.sh).
#   2. Fallback: the single un-ended session. A session is un-ended when it has
#      a `session.start` and no later `session.end`. If exactly one such session
#      exists, print it.
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

# --- 2. fallback: single un-ended session -----------------------------------
STARTED="$(grep -F '"type":"session.start"' "$EVENTS" 2>/dev/null \
           | while IFS= read -r l; do session_of "$l"; done)"
ENDED="$(grep -F '"type":"session.end"' "$EVENTS" 2>/dev/null \
         | while IFS= read -r l; do session_of "$l"; done)"

CANDIDATE=""
COUNT=0
seen=""
for s in $STARTED; do
  [ -n "$s" ] || continue
  # Dedup: a session that restarted (multiple session.start lines) counts once.
  case " $seen " in *" $s "*) continue ;; esac
  seen="$seen $s"
  ended=0
  for e in $ENDED; do
    if [ "$e" = "$s" ]; then ended=1; break; fi
  done
  if [ "$ended" = "0" ]; then
    CANDIDATE="$s"
    COUNT=$((COUNT + 1))
  fi
done

# Exactly one un-ended session → unambiguous. Zero or >1 → omit (never guess).
if [ "$COUNT" = "1" ]; then
  printf '%s\n' "$CANDIDATE"
fi
exit 0
