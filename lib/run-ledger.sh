#!/usr/bin/env bash
# run-ledger.sh — append-only .do-work/runs/RUN-NNN.yml writer.

set -u

PROJECT=""
REQ_PATH=""
AGENT_ID=""
MODEL=""
BRANCH=""
STARTED=""
ENDED=""
RESULT=""
REVIEW=""
COST=""
COMMANDS_PATH=""
TESTS_PATH=""
CHANGED_FILES_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --req) REQ_PATH="${2:-}"; shift 2 ;;
    --agent) AGENT_ID="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --started) STARTED="${2:-}"; shift 2 ;;
    --ended) ENDED="${2:-}"; shift 2 ;;
    --result) RESULT="${2:-}"; shift 2 ;;
    --review) REVIEW="${2:-}"; shift 2 ;;
    --cost) COST="${2:-}"; shift 2 ;;
    --commands) COMMANDS_PATH="${2:-}"; shift 2 ;;
    --tests) TESTS_PATH="${2:-}"; shift 2 ;;
    --changed-files) CHANGED_FILES_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,2p' "$0"
      exit 0
      ;;
    *)
      echo "run-ledger.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PROJECT" ] || [ -z "$REQ_PATH" ] || [ -z "$RESULT" ]; then
  echo "run-ledger.sh: --project, --req, and --result are required" >&2
  exit 1
fi

CONFIG="$PROJECT/.do-work/config.yml"
if [ -f "$CONFIG" ] && awk '
  /^ledger:/ { in_ledger=1; next }
  in_ledger && /^[^[:space:]#][^:]*:/ { in_ledger=0 }
  in_ledger && /^[[:space:]]*enabled:[[:space:]]*false[[:space:]]*($|#)/ { found=1 }
  END { exit found ? 0 : 1 }
' "$CONFIG"; then
  echo "ledger: disabled"
  exit 0
fi

RUNS_DIR="$PROJECT/.do-work/runs"
mkdir -p "$RUNS_DIR"

NEXT_NUM="$(find "$RUNS_DIR" -maxdepth 1 -name 'RUN-[0-9][0-9][0-9].yml' -print 2>/dev/null \
  | sed 's/.*RUN-//;s/\.yml$//' \
  | sort -n \
  | tail -n 1)"
if [ -z "$NEXT_NUM" ]; then
  NEXT_NUM=1
else
  NEXT_NUM=$((10#$NEXT_NUM + 1))
fi
RUN_ID="$(printf 'RUN-%03d' "$NEXT_NUM")"
OUT="$RUNS_DIR/$RUN_ID.yml"

REQ_ID="$(basename "$REQ_PATH" | sed -E 's/^(REQ-[0-9]+).*/\1/')"
UR_ID="$(awk '/^\*\*UR:\*\*/ { print $2; exit }' "$REQ_PATH" 2>/dev/null)"
PROOF_STATUS="unproven"
if [ -x "$PROJECT/lib/derive-status.sh" ]; then
  derived="$(bash "$PROJECT/lib/derive-status.sh" "$REQ_PATH" 2>/dev/null | awk '{ print $2; exit }')"
  [ -n "$derived" ] && PROOF_STATUS="$derived"
fi

yaml_scalar() {
  printf '%s' "$1" | sed 's/"/\\"/g'
}

write_list() {
  local label="$1"
  local file="$2"
  echo "$label:"
  if [ -n "$file" ] && [ -f "$file" ] && [ -s "$file" ]; then
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      echo "  - \"$(yaml_scalar "$item")\""
    done < "$file"
  else
    echo "  []"
  fi
}

{
  echo "run_id: $RUN_ID"
  echo "req: $REQ_ID"
  echo "ur: ${UR_ID:-unknown}"
  echo "agent_id: \"$(yaml_scalar "$AGENT_ID")\""
  echo "model: \"$(yaml_scalar "$MODEL")\""
  echo "branch: \"$(yaml_scalar "$BRANCH")\""
  echo "started_at: \"$(yaml_scalar "$STARTED")\""
  echo "ended_at: \"$(yaml_scalar "$ENDED")\""
  echo "result: \"$(yaml_scalar "$RESULT")\""
  echo "review_outcome: \"$(yaml_scalar "$REVIEW")\""
  echo "proof_status: \"$PROOF_STATUS\""
  echo "cost_estimate: \"$(yaml_scalar "$COST")\""
  write_list "commands" "$COMMANDS_PATH"
  write_list "tests" "$TESTS_PATH"
  write_list "changed_files" "$CHANGED_FILES_PATH"
} > "$OUT"

echo "$OUT"
