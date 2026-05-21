#!/usr/bin/env bash
# synth-status.sh — render the live do-work situation room as a GitHub-flavored
# markdown table to stdout. Optional UR filter scopes the output.
#
# Usage: synth-status.sh [UR-NNN]
#   [UR-NNN]   Optional UR id to filter. Only REQs whose `**UR:**` field
#              matches will be rendered.
#
# Output structure:
#   1. Totals header: backlog / working / archived counts.
#   2. Markdown table — one row per REQ:
#         | REQ | UR | Status | Layer | Claimer | Heartbeat-age | Deps-status | Footprint |
#      Sources:
#        - `.do-work/REQ-*.md`              (Status: backlog)
#        - `.do-work/working/REQ-*.md`      (Status: in-progress / stopped)
#        - `.do-work/archive/REQ-*.md`      (Status: done; only shown when
#                                            present so the snapshot reflects
#                                            completed work in this run)
#   3. Empty case: a single "no REQs" message in place of the table when there
#      are zero REQs across all three buckets.
#   4. Footer: deadlock warnings from `lib/deadlock-check.sh` if executable;
#      otherwise the footer is silently skipped (REQ-154 wires this up later).
#
# Heartbeat-age:
#   - working slots only — seconds since the `**Heartbeat:**` field; suffix
#     `(STALE)` when the age has crossed the threshold from
#     `.do-work/config.yml`'s `parallel.stale_threshold_seconds` (default 300).
#   - Missing or unparseable heartbeats are reported as `(STALE)` with `?` age
#     so the operator notices.
#   - Non-working rows render `—`.
#
# Deps-status:
#   - Delegates to `lib/check-deps.sh`. Empty stdout → `ready`; otherwise
#     `blocked: <missing-ids-csv>`.
#
# Footprint:
#   - The `**Files:**` field, with whitespace collapsed and truncated to 60
#     characters (suffix `…` when truncated).
#
# Exit codes:
#   0  Render succeeded (including the empty-bucket case).
#
# Compatible with macOS bash 3.2 + BSD utilities.

set -u

DOWORK=".do-work"
BACKLOG_DIR="$DOWORK"
WORKING_DIR="$DOWORK/working"
ARCHIVE_DIR="$DOWORK/archive"
CONFIG="$DOWORK/config.yml"
DEFAULT_THRESHOLD=300
FOOTPRINT_MAX=60

# Resolve sibling lib scripts via $0's directory so the script works from any
# cwd inside the project.
SELF_DIR="$( cd "$( dirname "$0" )" 2>/dev/null && pwd )"
CHECK_DEPS="$SELF_DIR/check-deps.sh"
DEADLOCK_CHECK="$SELF_DIR/deadlock-check.sh"

# When forking `check-deps.sh` once per REQ, render time on slow shells (BSD
# bash 3.2) balloons past the < 1s target for 200 REQs. We pre-compute an
# in-memory set of archived REQ ids by globbing once, then resolve deps in
# pure shell. `check-deps.sh` remains the source of truth — synth-status only
# duplicates its parsing logic for the read-only render path.
ARCHIVED_IDS=" "
if [ -d "$ARCHIVE_DIR" ]; then
  shopt -s nullglob 2>/dev/null || true
  for f in "$ARCHIVE_DIR"/REQ-*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    id="$(printf '%s' "$base" | awk '{
      if (match($0, /^REQ-M[0-9]+-[0-9]+/)) { print substr($0, RSTART, RLENGTH) }
      else if (match($0, /^REQ-[0-9]+/))     { print substr($0, RSTART, RLENGTH) }
    }')"
    [ -n "$id" ] && ARCHIVED_IDS="${ARCHIVED_IDS}${id} "
  done
fi

UR_FILTER="${1:-}"

# --- threshold from config (best-effort awk, mirrors scan-stale.sh) ---------
THRESHOLD="$DEFAULT_THRESHOLD"
if [ -f "$CONFIG" ]; then
  raw_val="$(awk '
    /^parallel:[[:space:]]*$/ { in_parallel = 1; next }
    in_parallel && /^[^[:space:]#]/ { in_parallel = 0 }
    in_parallel && /^[[:space:]]+stale_threshold_seconds:[[:space:]]*[0-9]+/ {
      sub(/^[[:space:]]+stale_threshold_seconds:[[:space:]]*/, "")
      sub(/[[:space:]].*$/, "")
      print
      exit
    }
  ' "$CONFIG" 2>/dev/null)"
  case "$raw_val" in
    ''|*[!0-9]*) : ;;
    *) [ "$raw_val" -gt 0 ] 2>/dev/null && THRESHOLD="$raw_val" ;;
  esac
fi

NOW_EPOCH="$(date -u +%s)"

# --- helpers ----------------------------------------------------------------

# Extract all fields-of-interest from a REQ file in a single awk pass. This
# avoids the per-field grep/sed/awk fork explosion that makes per-REQ field
# extraction O(N * fields) processes.
#
# Sets these globals (overwritten on every call):
#   F_UR, F_STATUS, F_LAYER, F_FILES, F_DEPS, F_CLAIMED_BY, F_HEARTBEAT
parse_req_fields() {
  local file="$1"
  F_UR=""; F_STATUS=""; F_LAYER=""; F_FILES=""; F_DEPS=""
  F_CLAIMED_BY=""; F_HEARTBEAT=""

  # Single awk reads each header field once. Inside the claim stamp block,
  # **Claimed by:** and **Heartbeat:** are picked up.
  local out
  out="$(awk '
    function strip(s) {
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    /^<!-- claimed-start -->$/ { in_block = 1; next }
    /^<!-- claimed-end -->$/   { in_block = 0; next }
    in_block && /^\*\*Claimed by:\*\*/ {
      v = $0; sub(/^\*\*Claimed by:\*\*[[:space:]]*/, "", v)
      printf "CLAIMED_BY=%s\n", strip(v); next
    }
    in_block && /^\*\*Heartbeat:\*\*/ {
      v = $0; sub(/^\*\*Heartbeat:\*\*[[:space:]]*/, "", v)
      printf "HEARTBEAT=%s\n", strip(v); next
    }
    !in_block && /^\*\*UR:\*\*/ {
      v = $0; sub(/^\*\*UR:\*\*[[:space:]]*/, "", v)
      printf "UR=%s\n", strip(v); next
    }
    !in_block && /^\*\*Status:\*\*/ {
      v = $0; sub(/^\*\*Status:\*\*[[:space:]]*/, "", v)
      printf "STATUS=%s\n", strip(v); next
    }
    !in_block && /^\*\*Layer:\*\*/ {
      v = $0; sub(/^\*\*Layer:\*\*[[:space:]]*/, "", v)
      printf "LAYER=%s\n", strip(v); next
    }
    !in_block && /^\*\*Files:\*\*/ {
      v = $0; sub(/^\*\*Files:\*\*[[:space:]]*/, "", v)
      printf "FILES=%s\n", strip(v); next
    }
    !in_block && /^\*\*Depends on:\*\*/ {
      v = $0; sub(/^\*\*Depends on:\*\*[[:space:]]*/, "", v)
      printf "DEPS=%s\n", strip(v); next
    }
    /^## / { exit }   # Stop at the first section heading.
  ' "$file" 2>/dev/null)"

  # Parse KEY=VALUE lines into the corresponding globals.
  local line key val
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
      UR)         F_UR="$val" ;;
      STATUS)     F_STATUS="$val" ;;
      LAYER)      F_LAYER="$val" ;;
      FILES)      F_FILES="$val" ;;
      DEPS)       F_DEPS="$val" ;;
      CLAIMED_BY) F_CLAIMED_BY="$val" ;;
      HEARTBEAT)  F_HEARTBEAT="$val" ;;
    esac
  done <<EOF
$out
EOF
}

# Parse an ISO-8601 UTC string to epoch seconds. Prints epoch on stdout; empty
# stdout (and non-zero rc) on failure. Tries BSD then GNU date.
iso_to_epoch() {
  local ts="$1"
  local epoch
  epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null)"
  if [ -n "$epoch" ]; then printf '%s\n' "$epoch"; return 0; fi
  epoch="$(date -u -d "$ts" "+%s" 2>/dev/null)"
  if [ -n "$epoch" ]; then printf '%s\n' "$epoch"; return 0; fi
  return 1
}

# Extract the REQ id from a REQ filename (REQ-NNN or REQ-MN-NNN). Pure bash —
# no awk fork — because this is called once per REQ on the hot path.
req_id_from_path() {
  local path="$1"
  local base="${path##*/}"
  # Strip trailing -*.md to get just `REQ-NNN` or `REQ-MN-NNN`.
  case "$base" in
    REQ-M[0-9]*-[0-9]*-*.md)
      # REQ-M<digits>-<digits>-...
      printf '%s' "${base%%-*.md}"  # Greedy strip — but we want to keep the second segment.
      # Fallback to a simpler form below.
      ;;
  esac
  # Use bash regex when available (3.2 supports [[ =~ ]]).
  local id=""
  if [[ "$base" =~ ^(REQ-M[0-9]+-[0-9]+) ]]; then
    id="${BASH_REMATCH[1]}"
  elif [[ "$base" =~ ^(REQ-[0-9]+) ]]; then
    id="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$id"
}

# Truncate a string to FOOTPRINT_MAX chars; append `…` when truncated. Pure
# bash parameter expansion — no fork.
truncate_footprint() {
  local s="$1"
  # Collapse newlines and runs of whitespace (best-effort, pure bash).
  s="${s//$'\n'/ }"
  # Trim leading/trailing whitespace.
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  if [ "${#s}" -gt "$FOOTPRINT_MAX" ]; then
    local cut=$(( FOOTPRINT_MAX - 1 ))
    printf '%s…' "${s:0:$cut}"
  else
    printf '%s' "$s"
  fi
}

# Escape a string for safe inclusion in a markdown table cell. Pure bash —
# no fork — to keep the per-row cost low.
md_cell() {
  local s="$1"
  s="${s//$'\n'/ }"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

# Render one row given the REQ path and its bucket label.
# Bucket: backlog | working | archive
# Status column is derived from the file's own `**Status:**` field so that
# `stopped` is rendered correctly when a worker has marked a working slot
# stopped.
render_row() {
  local path="$1"
  local bucket="$2"

  local req_id ur status layer files claimer hb_age deps_status footprint

  req_id="$(req_id_from_path "$path")"

  # Single awk pass for all fields.
  parse_req_fields "$path"

  ur="$F_UR"
  [ -z "$ur" ] && ur="—"

  # If a UR filter is set, only emit rows for matching UR. Use plain equality
  # rather than substring so e.g. UR-1 doesn't match UR-10.
  if [ -n "$UR_FILTER" ] && [ "$ur" != "$UR_FILTER" ]; then
    return 0
  fi

  status="$F_STATUS"
  [ -z "$status" ] && status="—"

  layer="$F_LAYER"
  [ -z "$layer" ] && layer="—"

  files="$F_FILES"

  # Claimer + heartbeat-age (working slots only).
  if [ "$bucket" = "working" ]; then
    claimer="$F_CLAIMED_BY"
    [ -z "$claimer" ] && claimer="—"
    local hb_val hb_epoch age
    hb_val="$F_HEARTBEAT"
    if [ -z "$hb_val" ]; then
      hb_age="? (STALE)"
    else
      hb_epoch="$(iso_to_epoch "$hb_val" || true)"
      if [ -z "$hb_epoch" ]; then
        hb_age="? (STALE)"
      else
        age=$(( NOW_EPOCH - hb_epoch ))
        if [ "$age" -ge "$THRESHOLD" ]; then
          hb_age="${age}s (STALE)"
        else
          hb_age="${age}s"
        fi
      fi
    fi
  else
    claimer="—"
    hb_age="—"
  fi

  # Deps-status: resolve against the pre-computed ARCHIVED_IDS set.
  # Mirrors check-deps.sh parsing (Depends on: csv of REQ ids).
  local deps_raw missing dep
  deps_raw="$F_DEPS"
  missing=""
  if [ -n "$deps_raw" ]; then
    # Split on commas, trim, check membership in ARCHIVED_IDS.
    set +u
    set -f
    local oldIFS="$IFS"
    IFS=','
    # shellcheck disable=SC2206
    local arr=( $deps_raw )
    IFS="$oldIFS"
    set +f
    for dep in "${arr[@]}"; do
      dep="${dep#"${dep%%[![:space:]]*}"}"
      dep="${dep%"${dep##*[![:space:]]}"}"
      [ -z "$dep" ] && continue
      case "$ARCHIVED_IDS" in
        *" $dep "*) : ;;  # archived → satisfied
        *) missing="${missing}${missing:+,}$dep" ;;
      esac
    done
    set -u
  fi
  if [ -z "$missing" ]; then
    deps_status="ready"
  else
    deps_status="blocked: $missing"
  fi

  footprint="$(truncate_footprint "$files")"
  [ -z "$footprint" ] && footprint="—"

  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$(md_cell "$req_id")" \
    "$(md_cell "$ur")" \
    "$(md_cell "$status")" \
    "$(md_cell "$layer")" \
    "$(md_cell "$claimer")" \
    "$(md_cell "$hb_age")" \
    "$(md_cell "$deps_status")" \
    "$(md_cell "$footprint")"
}

# --- collect file lists -----------------------------------------------------

shopt -s nullglob 2>/dev/null || true

BACKLOG_FILES=()
WORKING_FILES=()
ARCHIVE_FILES=()

if [ -d "$BACKLOG_DIR" ]; then
  for f in "$BACKLOG_DIR"/REQ-*.md; do
    [ -e "$f" ] || continue
    BACKLOG_FILES+=( "$f" )
  done
fi
if [ -d "$WORKING_DIR" ]; then
  for f in "$WORKING_DIR"/REQ-*.md; do
    [ -e "$f" ] || continue
    WORKING_FILES+=( "$f" )
  done
fi
if [ -d "$ARCHIVE_DIR" ]; then
  for f in "$ARCHIVE_DIR"/REQ-*.md; do
    [ -e "$f" ] || continue
    ARCHIVE_FILES+=( "$f" )
  done
fi

# bash 3.2 + set -u: `${arr[@]}` on a zero-element array is unbound. Use the
# array length directly for counts and guard expansions with a length check.
BACKLOG_N=${#BACKLOG_FILES[@]}
WORKING_N=${#WORKING_FILES[@]}
ARCHIVE_N=${#ARCHIVE_FILES[@]}
TOTAL_N=$(( BACKLOG_N + WORKING_N + ARCHIVE_N ))

# --- render -----------------------------------------------------------------

# Header (totals).
printf '# do-work situation room\n\n'
if [ -n "$UR_FILTER" ]; then
  printf '**Scope:** %s\n' "$UR_FILTER"
fi
printf '**Totals:** backlog=%d, working=%d, archived=%d\n\n' \
  "$BACKLOG_N" "$WORKING_N" "$ARCHIVE_N"

if [ "$TOTAL_N" -eq 0 ]; then
  printf '_no REQs found in backlog, working, or archive._\n'
else
  # Table header.
  printf '| REQ | UR | Status | Layer | Claimer | Heartbeat-age | Deps-status | Footprint |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'

  # Bucket order: working first (most operationally relevant), then backlog,
  # then archive. Within each bucket, preserve glob (sorted) order.
  if [ "$WORKING_N" -gt 0 ]; then
    for f in "${WORKING_FILES[@]}"; do
      render_row "$f" "working"
    done
  fi
  if [ "$BACKLOG_N" -gt 0 ]; then
    for f in "${BACKLOG_FILES[@]}"; do
      render_row "$f" "backlog"
    done
  fi
  if [ "$ARCHIVE_N" -gt 0 ]; then
    for f in "${ARCHIVE_FILES[@]}"; do
      render_row "$f" "archive"
    done
  fi
fi

# Footer: deadlock warnings (when REQ-154 lands).
if [ -x "$DEADLOCK_CHECK" ]; then
  dl_out="$( "$DEADLOCK_CHECK" 2>/dev/null || true )"
  if [ -n "$dl_out" ]; then
    printf '\n## Deadlock warnings\n\n%s\n' "$dl_out"
  fi
fi

exit 0
