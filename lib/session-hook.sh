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

# Read the whole hook payload from stdin. Tolerate an empty stdin.
PAYLOAD="$(cat 2>/dev/null || true)"

# Minimal, dependency-free extraction of a top-level JSON string field's value.
json_field() {
  printf '%s' "$PAYLOAD" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | head -n1
}

SESSION="$(json_field session_id)"
CWD="$(json_field cwd)"

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

DATA=""
if [ "$MODE" = "start" ] && [ -n "${DO_WORK_UI_MARKER:-}" ]; then
  M="${DO_WORK_UI_MARKER}"
  M="${M//\\/\\\\}"
  M="${M//\"/\\\"}"
  M="${M//$'\r'/}"
  M="${M//$'\n'/}"
  DATA="{\"marker\":\"$M\"}"
fi

bash "$SCRIPT_DIR/emit-event.sh" "$PROJECT" "$EVENT_TYPE" "$SESSION" "$DATA" || true
exit 0
