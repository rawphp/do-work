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
#
# ---------------------------------------------------------------------------
# migrate-linear (opt-in; NOT a scanner drift row) — REQ-301 / design §12
# ---------------------------------------------------------------------------
# Markdown→Linear one-shot migration is operator-invoked only via
# `/do-work upgrade migrate` (agents/upgrade.md Step 9 → port op
# migrate_markdown_to_linear in agents/tracker/linear.md).
#
# This scanner intentionally never emits a `migrate-linear` drift line:
# remaining on markdown is the default backend, not non-conformance.
# Do not invent blocking drift for "still on markdown."
#
# After a successful cutover (`tracker.backend: linear`), leftover
# `.do-work/user-requests/`, backlog `REQ-*.md`, and `archive/` trees are
# historical read-only. They are also not drift — work-item ops ignore them
# as the store (Linear is sole truth); runtime/git/config stay local.
#
# sqlite sole store (tracker.backend: sqlite) — ORI-1444 / design
# ---------------------------------------------------------------------------
# When backend is sqlite, work items live only in `.do-work/work.db`
# (lib/dw-db.sh). Missing or empty `.do-work/user-requests/`, backlog
# `REQ-*.md`, and markdown `archive/` trees are **not** conformance drift —
# they are unused by work-item ops under sqlite (greenfield switch; no
# history import). Do not invent scanner rows for "missing user-requests"
# or "no REQ-*.md files" while sqlite is the active backend.
#
# This scanner also never emits sqlite-specific drift for "still on
# markdown" or "sqlite3 not installed" — those are Load Config / runtime
# hard-stops when the operator has opted into `backend: sqlite`, not
# project layout conformance. `/do-work upgrade migrate` refuses under
# sqlite (agents/upgrade.md Step 9 — refused-sqlite-backend).
# ---------------------------------------------------------------------------

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
