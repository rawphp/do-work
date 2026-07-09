#!/usr/bin/env bash
# conformance-scan.sh — detect project conformance drift without fixing it.
#
# Usage:
#   conformance-scan.sh <project-root>
#
# Prints one line per detected drift row:
#   <row-id> <class> <detail>
#
# Exit codes:
#   0  no drift detected
#   1  one or more drift rows detected
#   2  usage error

set -u

usage() {
  echo "Usage: conformance-scan.sh <project-root>" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

PROJECT_ROOT="$1"
if [ ! -d "$PROJECT_ROOT" ]; then
  usage
  echo "conformance-scan.sh: project root not found: $PROJECT_ROOT" >&2
  exit 2
fi

LEGACY_DIR="$PROJECT_ROOT/do-work"
DOT_DIR="$PROJECT_ROOT/.do-work"
PENDING_DIR="$DOT_DIR/pending"
DRIFT=0

if [ -d "$LEGACY_DIR" ] && [ -d "$DOT_DIR" ]; then
  echo "dir-conflict blocking both do-work/ and .do-work/ exist"
  DRIFT=1
elif [ -d "$LEGACY_DIR" ] && [ ! -d "$DOT_DIR" ]; then
  echo "legacy-dir safe-blocking do-work/ exists and .do-work/ does not"
  DRIFT=1
fi

if [ -d "$PENDING_DIR" ]; then
  shopt -s nullglob
  # shellcheck disable=SC2206
  REQ_FILES=( "$PENDING_DIR"/REQ-*.md )
  echo "pending-dir destructive .do-work/pending/ exists (${#REQ_FILES[@]} REQ files)"
  DRIFT=1
fi

if [ "$DRIFT" -eq 1 ]; then
  exit 1
fi

exit 0
