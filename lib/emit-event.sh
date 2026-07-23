#!/usr/bin/env bash
# emit-event.sh — append one telemetry event line to a project's
# .do-work/state/events.jsonl stream.
#
# Usage:
#   emit-event.sh <project> <type> <session> [data-json]
#
# Arguments:
#   <project>    Path to the consumer project root (the dir containing .do-work/).
#   <type>       Event type string (e.g. session.start, session.end). Not
#                validated against any enum here — the extension ignores
#                unknown types.
#   <session>    Session id string.
#   [data-json]  Optional raw JSON *object* fragment (e.g. '{"marker":"m1"}').
#                Passed through verbatim as the event's "data" field. Omitted
#                from the line when absent or empty. The caller is responsible
#                for it being valid JSON.
#
# Emits exactly one line of the form (field order mirrors the extension's
# fixtures; JSON key order is not significant to the parser):
#
#   {"ts":"<ISO-8601 UTC>","session":"<session>","type":"<type>","data":<data-json>}
#
# to {project}/.do-work/state/events.jsonl, creating the state/ directory and
# the file defensively. The append is a single O_APPEND write (atomic for a
# line this size), so concurrent emitters never interleave partial lines.
#
# The extension's parser (src/parsers/eventsParser.ts) requires a string `ts`,
# a string `session`, and a known `type`; `data` is an optional object. This
# script's output satisfies that contract.
#
# Exit codes:
#   0  Line appended.
#   1  Usage error (missing required argument) or state-dir creation failure.
#
# Environment overrides (testing only):
#   EMIT_EVENT_TS  If set, used verbatim as the `ts` value instead of `date`.
#
# Compatible with macOS bash 3.2 + BSD userland. No jq dependency.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=json-bash.sh
. "$SCRIPT_DIR/json-bash.sh"

PROJECT="${1:-}"
TYPE="${2:-}"
SESSION="${3:-}"
DATA="${4:-}"

if [ -z "$PROJECT" ] || [ -z "$TYPE" ] || [ -z "$SESSION" ]; then
  echo "emit-event.sh: usage: emit-event.sh <project> <type> <session> [data-json]" >&2
  exit 1
fi

TS="${EMIT_EVENT_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
ESC_SESSION="$(json_escape "$SESSION")"
ESC_TYPE="$(json_escape "$TYPE")"

LINE="{\"ts\":\"$TS\",\"session\":\"$ESC_SESSION\",\"type\":\"$ESC_TYPE\""
if [ -n "$DATA" ]; then
  LINE="$LINE,\"data\":$DATA"
fi
LINE="$LINE}"

STATE_DIR="$PROJECT/.do-work/state"
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  echo "emit-event.sh: cannot create $STATE_DIR" >&2
  exit 1
fi

printf '%s\n' "$LINE" >> "$STATE_DIR/events.jsonl"
