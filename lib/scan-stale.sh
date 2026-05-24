#!/usr/bin/env bash
# scan-stale.sh — list working/ REQ slots whose heartbeat is older than the
# stale threshold (heartbeat-based dead-agent detection for the do-work
# coordination layer).
#
# Usage: scan-stale.sh   (no args; run from project root containing .do-work/)
#
# What it does:
#   1. Reads `parallel.stale_threshold_seconds` from `.do-work/config.yml`
#      (default 300s; falls back to default if absent or not a positive int).
#   2. Globs `.do-work/working/REQ-*.md`.
#   3. For each, parses the `**Heartbeat:**` line.
#        - absent → stale (legacy slot)
#        - present but unparseable → stale + diagnostic on stderr
#        - present and (now - heartbeat) >= threshold → stale
#   4. Prints one line per stale slot to stdout:
#        <req-path> <heartbeat-iso-or-"absent"> age=<seconds-or-"unknown">
#
#      The third token is a literal `age=` prefix followed by the integer
#      seconds elapsed between the heartbeat ISO and NOW_EPOCH.  For slots
#      with absent / unparseable heartbeats, `age=unknown` is emitted.
#
# Exit codes:
#   0  Scan completed (zero or more stale slots printed).
#   1  Fatal error (e.g. missing .do-work/working/, unreadable file).
#
# Compatible with macOS bash 3.2 (BSD date) and Linux bash >= 4 (GNU date).
# Standard POSIX tools only (grep, sed, awk).

set -u

DOWORK=".do-work"
WORKING="$DOWORK/working"
CONFIG="$DOWORK/config.yml"
DEFAULT_THRESHOLD=300

# --- threshold from config (best-effort grep/sed) ---------------------------
#
# Looks for:
#   parallel:
#     stale_threshold_seconds: 60
#
# Tolerates extra whitespace. If the key is absent, malformed, or not a
# positive integer, falls back to DEFAULT_THRESHOLD silently.
THRESHOLD="$DEFAULT_THRESHOLD"
if [ -f "$CONFIG" ]; then
  # awk: enter the `parallel:` block on a top-level key match, then within
  # that block (indented), find `stale_threshold_seconds:` and print the
  # integer value. Stops scanning the block when a new top-level key starts.
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
    ''|*[!0-9]*) : ;;   # empty or non-numeric → keep default
    *)
      if [ "$raw_val" -gt 0 ] 2>/dev/null; then
        THRESHOLD="$raw_val"
      fi
      ;;
  esac
fi

# --- working/ directory check ----------------------------------------------
#
# Absence is not a fatal error: it just means there are no in-flight slots.
if [ ! -d "$WORKING" ]; then
  exit 0
fi

# --- iso-8601 → epoch (cross-platform) -------------------------------------
#
# Args: $1 = ISO-8601 UTC string (e.g. 2026-05-21T01:25:59Z)
# Prints epoch seconds on stdout, exit 0 on success.
# Returns 1 if the string is unparseable by both BSD and GNU date.
iso_to_epoch() {
  local ts="$1"
  local epoch
  # BSD date (macOS): -j -f <format>
  epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null)"
  if [ -n "$epoch" ]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  # GNU date (Linux): -d <string>
  epoch="$(date -u -d "$ts" "+%s" 2>/dev/null)"
  if [ -n "$epoch" ]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  return 1
}

# --- current epoch ----------------------------------------------------------
NOW_EPOCH="$(date -u +%s)"

# --- scan working/ slots ----------------------------------------------------
#
# Use a glob; if no matches, the literal pattern survives and we skip it.
shopt -s nullglob 2>/dev/null || true
for req in "$WORKING"/REQ-*.md; do
  [ -e "$req" ] || continue

  # Extract the first **Heartbeat:** line value (text after the colon-space).
  hb_line="$(grep -m1 '^\*\*Heartbeat:\*\*' "$req" 2>/dev/null || true)"

  # Derive REQ id from filename for diagnostics.
  base="$(basename "$req")"
  req_id="$(printf '%s' "$base" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else {
      print ""
    }
  }')"

  if [ -z "$hb_line" ]; then
    # Heartbeat absent → legacy slot, treat as stale.
    printf '%s absent age=unknown\n' "$req"
    continue
  fi

  # Strip the leading "**Heartbeat:**" and any whitespace.
  hb_val="$(printf '%s' "$hb_line" | sed 's/^\*\*Heartbeat:\*\*[[:space:]]*//' | sed 's/[[:space:]]*$//')"

  if [ -z "$hb_val" ]; then
    printf 'scan-stale: %s heartbeat present but empty — treating as stale\n' "$req_id" >&2
    printf '%s absent age=unknown\n' "$req"
    continue
  fi

  # Attempt to parse.
  hb_epoch="$(iso_to_epoch "$hb_val" || true)"
  if [ -z "$hb_epoch" ]; then
    printf 'scan-stale: %s malformed heartbeat (%s) — treating as stale\n' "$req_id" "$hb_val" >&2
    printf '%s %s age=unknown\n' "$req" "$hb_val"
    continue
  fi

  # Compute age.
  age=$(( NOW_EPOCH - hb_epoch ))
  if [ "$age" -ge "$THRESHOLD" ]; then
    printf '%s %s age=%s\n' "$req" "$hb_val" "$age"
  fi
done

exit 0
