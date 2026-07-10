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

# Curated tombstone list of .do-work/config.yml keys the skill itself has
# removed. Only keys listed here are ever flagged — user-added custom keys
# and sections are never touched, regardless of whether they appear in the
# canonical template. Documentation home / fix contract: the stale-config-key
# row in agents/upgrade.md's conformance manifest.
STALE_CONFIG_KEYS="notifications.on_pending_validation"

# stale_key_present <dotted.key.path> <config-file>
# True when the dotted key path is present as a real nested YAML key, matched
# by indentation rather than a bare substring search — e.g.
# "notifications.on_pending_validation" only matches an on_pending_validation:
# line actually nested under a top-level notifications: section, never a
# same-named key elsewhere in the file or a mention inside a comment.
stale_key_present() {
  local dotted_key="$1"
  local file="$2"
  local result
  result="$(awk -v key="$dotted_key" '
    BEGIN {
      ncomp = split(key, comp, ".")
      depth = 0
    }
    {
      raw = $0
      content = raw
      sub(/^[ \t]*/, "", content)
      if (content == "" || content ~ /^#/) next
      indent = length(raw) - length(content)

      while (depth > 0 && indent <= stack[depth]) depth--

      target = comp[depth + 1]
      if (content ~ ("^" target "[ \t]*:")) {
        if (depth == 0 && indent != 0) next
        depth++
        stack[depth] = indent
        if (depth == ncomp) { found = 1; exit }
      }
    }
    END { print (found ? 1 : 0) }
  ' "$file")"
  [ "$result" = "1" ]
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
CONFIG_FILE="$DOT_DIR/config.yml"
DRIFT=0

if [ -d "$LEGACY_DIR" ] && [ -d "$DOT_DIR" ]; then
  echo "dir-conflict blocking both do-work/ and .do-work/ exist"
  DRIFT=1
elif [ -d "$LEGACY_DIR" ] && [ ! -d "$DOT_DIR" ]; then
  echo "legacy-dir safe-blocking do-work/ exists and .do-work/ does not"
  DRIFT=1
fi

if [ -d "$PENDING_DIR" ]; then
  REQ_COUNT="$(find "$PENDING_DIR" -maxdepth 1 -type f -name 'REQ-*.md' -print 2>/dev/null | awk 'END { print NR+0 }')"
  echo "pending-dir destructive .do-work/pending/ exists ($REQ_COUNT REQ files)"
  DRIFT=1
fi

if [ -f "$CONFIG_FILE" ]; then
  for key in $STALE_CONFIG_KEYS; do
    if stale_key_present "$key" "$CONFIG_FILE"; then
      echo "stale-config-key destructive $key"
      DRIFT=1
    fi
  done
fi

if [ "$DRIFT" -eq 1 ]; then
  exit 1
fi

exit 0
