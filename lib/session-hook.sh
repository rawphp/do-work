#!/usr/bin/env bash
# session-hook.sh — Claude Code SessionStart / Stop hook entry point for
# do-work telemetry. Wired into a consumer project's .claude/settings.json by
# `/do-work install` and `/do-work upgrade` (see lib/install-hooks.sh).
#
# Usage (from a hook command in settings.json):
#   session-hook.sh start     # SessionStart hook      → emits session.start
#   session-hook.sh end       # Stop / session-end hook → emits session.end
#
# Reads the hook payload JSON on stdin (Claude Code provides at least
# `session_id`, usually `cwd`). Behaviour:
#   - Resolve the project dir from the stdin `cwd`, falling back to $PWD.
#   - If the project has no .do-work/ directory: exit 0 WITHOUT writing anything
#     (do-work is not installed here — telemetry is a no-op).
#   - Otherwise emit the event via lib/emit-event.sh:
#       * start → session.start, including data.marker from $DO_WORK_UI_MARKER
#                 when that env var is set and non-empty (omitted otherwise).
#       * end   → session.end (no data).
#
# Always exits 0 — a telemetry hook must never break the user's session.
#
# Compatible with macOS bash 3.2 + BSD userland. No jq dependency.

set -u

MODE="${1:-}"
case "$MODE" in
  start) EVENT_TYPE="session.start" ;;
  end)   EVENT_TYPE="session.end" ;;
  *)
    echo "session-hook.sh: usage: session-hook.sh <start|end>" >&2
    exit 0   # never fail the session, even on misconfiguration
    ;;
esac

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=json-bash.sh
. "$SCRIPT_DIR/json-bash.sh"

# Read the whole hook payload from stdin. Tolerate an empty stdin.
PAYLOAD="$(cat 2>/dev/null || true)"

# Model id of the LAST assistant message in a JSONL transcript. Prints nothing
# when the path is empty/absent or no assistant message carries a model. No jq.
transcript_model() {
  local tpath="$1" line
  [ -n "$tpath" ] || return 0
  [ -f "$tpath" ] || return 0
  line="$(grep '"type"[[:space:]]*:[[:space:]]*"assistant"' "$tpath" 2>/dev/null \
    | grep '"model"' | tail -n1)"
  [ -n "$line" ] || return 0
  json_string_field "$line" model
}

# Most recent model recorded for a session in this project's events.jsonl — the
# last line for the session carrying data.model (session.start / model.change).
recorded_model() {
  local sess="$1" events="$PROJECT/.do-work/state/events.jsonl" line
  [ -f "$events" ] || return 0
  line="$(grep "\"session\":\"$sess\"" "$events" 2>/dev/null | grep '"model"' | tail -n1)"
  [ -n "$line" ] || return 0
  json_string_field "$line" model
}

SESSION="$(json_string_field "$PAYLOAD" session_id)"
CWD="$(json_string_field "$PAYLOAD" cwd)"
TRANSCRIPT="$(json_string_field "$PAYLOAD" transcript_path)"

PROJECT="${CWD:-$PWD}"
[ -n "$PROJECT" ] || PROJECT="$PWD"

# No-op when do-work is not installed in the resolved project.
if [ ! -d "$PROJECT/.do-work" ]; then
  exit 0
fi

# Without a session id there is no meaningful event to emit — no-op.
if [ -z "$SESSION" ]; then
  exit 0
fi

# Compose the session.start data object. It may carry:
#   marker  — from $DO_WORK_UI_MARKER (existing REQ-037 behaviour)
#   model   — the orchestrator model, from stdin `model` (SessionStart provides
#             it, but not always) falling back to the last assistant message's
#             message.model in the transcript. Omitted when neither yields one.
DATA=""
if [ "$MODE" = "start" ]; then
  MODEL="$(json_string_field "$PAYLOAD" model)"
  [ -n "$MODEL" ] || MODEL="$(transcript_model "$TRANSCRIPT")"
  FIELDS=""
  if [ -n "${DO_WORK_UI_MARKER:-}" ]; then
    FIELDS="\"marker\":\"$(json_escape "$DO_WORK_UI_MARKER")\""
  fi
  if [ -n "$MODEL" ]; then
    [ -n "$FIELDS" ] && FIELDS="$FIELDS,"
    FIELDS="$FIELDS\"model\":\"$(json_escape "$MODEL")\""
  fi
  [ -n "$FIELDS" ] && DATA="{$FIELDS}"
fi

bash "$SCRIPT_DIR/emit-event.sh" "$PROJECT" "$EVENT_TYPE" "$SESSION" "$DATA" || true

# Stop hook (end mode): in addition to session.end above, emit a model.change
# event when the orchestrator's current model (last assistant message.model in
# the transcript) differs from the last model recorded for this session. Emits
# nothing when the model is unchanged (no per-turn spam) or undeterminable.
if [ "$MODE" = "end" ]; then
  CUR_MODEL="$(transcript_model "$TRANSCRIPT")"
  if [ -n "$CUR_MODEL" ]; then
    PREV_MODEL="$(recorded_model "$SESSION")"
    if [ "$CUR_MODEL" != "$PREV_MODEL" ]; then
      MC_DATA="{\"model\":\"$(json_escape "$CUR_MODEL")\"}"
      bash "$SCRIPT_DIR/emit-event.sh" "$PROJECT" "model.change" "$SESSION" "$MC_DATA" || true
    fi
  fi
fi
exit 0
