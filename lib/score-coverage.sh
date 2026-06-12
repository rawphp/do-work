#!/usr/bin/env bash
# score-coverage.sh — deterministic verify confidence score.
#
# Computes the single run/no-run gate number from a structured gap manifest
# the verify agent produces. The agent supplies judgment (which requirements
# are full / partial / missing, and how many gaps of each category exist);
# this script supplies the arithmetic, so two runs over identical state always
# produce the same number.
#
# Usage:
#   score-coverage.sh --full N --partial N --missing N \
#     [--ideate-flags N] [--layer-gaps N] [--integration-gaps N] \
#     [--partial-conf-gaps N] [--dangling-deps N] [--path-unit-gaps N]
#
# Prints the integer score (0-100) on stdout.
#
# Composition formula (the one place it is stated):
#   total = full + partial + missing
#   base  = (full + 0.5 * partial) / total * 100          (0 if total == 0)
#   For each gap category: deduction = min(count * per_item, cap)
#   score = round( max(0, base - sum(deductions)) )
#
# Per-category per-item deduction and cap (matches agents/verify.md):
#   ideate flags        -5 each, cap -20   (Step 2b)
#   layer gaps          -10 each, cap -30  (Step 4b)
#   integration gaps    -5 each, cap -25   (Step 4c)
#   partial-confidence  -3 each, cap -15   (Step 4d)
#   dangling deps       -5 each, cap -20   (Step 4e)
#   path-unit gaps      -5 each, cap -20   (Step 4f)

set -u

FULL=0
PARTIAL=0
MISSING=0
IDEATE=0
LAYER=0
INTEGRATION=0
PARTIAL_CONF=0
DANGLING=0
PATH_UNIT=0

usage() {
  grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

require_int() {
  case "$1" in
    ''|*[!0-9]*)
      echo "score-coverage.sh: '$2' expects a non-negative integer, got '$1'" >&2
      exit 2
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full)              require_int "${2:-}" "$1"; FULL="$2"; shift 2 ;;
    --partial)           require_int "${2:-}" "$1"; PARTIAL="$2"; shift 2 ;;
    --missing)           require_int "${2:-}" "$1"; MISSING="$2"; shift 2 ;;
    --ideate-flags)      require_int "${2:-}" "$1"; IDEATE="$2"; shift 2 ;;
    --layer-gaps)        require_int "${2:-}" "$1"; LAYER="$2"; shift 2 ;;
    --integration-gaps)  require_int "${2:-}" "$1"; INTEGRATION="$2"; shift 2 ;;
    --partial-conf-gaps) require_int "${2:-}" "$1"; PARTIAL_CONF="$2"; shift 2 ;;
    --dangling-deps)     require_int "${2:-}" "$1"; DANGLING="$2"; shift 2 ;;
    --path-unit-gaps)    require_int "${2:-}" "$1"; PATH_UNIT="$2"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)
      echo "score-coverage.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

# deduction <count> <per_item> <cap> -> echoes the capped deduction.
deduction() {
  local raw=$(( $1 * $2 ))
  if [ "$raw" -gt "$3" ]; then
    echo "$3"
  else
    echo "$raw"
  fi
}

TOTAL=$(( FULL + PARTIAL + MISSING ))

DED=0
DED=$(( DED + $(deduction "$IDEATE" 5 20) ))
DED=$(( DED + $(deduction "$LAYER" 10 30) ))
DED=$(( DED + $(deduction "$INTEGRATION" 5 25) ))
DED=$(( DED + $(deduction "$PARTIAL_CONF" 3 15) ))
DED=$(( DED + $(deduction "$DANGLING" 5 20) ))
DED=$(( DED + $(deduction "$PATH_UNIT" 5 20) ))

# Base coverage and final score via awk (float math + round-half-up),
# then floor at 0. bash 3.2 has no float arithmetic, so awk owns the
# division and rounding.
SCORE="$(awk -v full="$FULL" -v partial="$PARTIAL" -v total="$TOTAL" -v ded="$DED" '
BEGIN {
  if (total <= 0) {
    base = 0
  } else {
    base = (full + 0.5 * partial) / total * 100
  }
  score = base - ded
  if (score < 0) score = 0
  # round half up to nearest integer
  printf "%d", int(score + 0.5)
}')"

echo "$SCORE"
