#!/usr/bin/env bash
# dw-db.sh — sqlite work-item store CLI for do-work (tracker.backend: sqlite)
# Usage: dw-db.sh <command> [args...]
# Compatible with macOS bash 3.2.
set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCHEMA="$SCRIPT_DIR/sqlite-schema.sql"
SUPPORTED_USER_VERSION=1

die() { echo "dw-db: $*" >&2; exit 1; }

require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not on PATH (install sqlite)"
}

# resolve_db PROJECT_ROOT [override_path]
resolve_db() {
  local root="$1"
  local override="${2:-}"
  if [ -n "$override" ]; then
    case "$override" in
      /*) echo "$override" ;;
      *) echo "$root/$override" ;;
    esac
  else
    echo "$root/.do-work/work.db"
  fi
}

sql_exec() {
  local db="$1"; shift
  # busy_timeout + WAL on every connection
  sqlite3 "$db" "PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; $*"
}

cmd_ensure() {
  local root="${1:-}"
  [ -n "$root" ] || die "ensure: project root required"
  require_sqlite3
  [ -f "$SCHEMA" ] || die "schema missing: $SCHEMA"
  mkdir -p "$root/.do-work" "$root/.do-work/state" "$root/.do-work/evidence" "$root/.do-work/board"
  local db
  db="$(resolve_db "$root")"
  if [ ! -f "$db" ]; then
    sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;"
    if ! sqlite3 "$db" < "$SCHEMA"; then
      rm -f "$db" "$db-wal" "$db-shm" 2>/dev/null || true
      die "failed to apply schema to $db"
    fi
    sqlite3 "$db" "PRAGMA user_version=$SUPPORTED_USER_VERSION;"
  else
    local ver
    ver="$(sqlite3 "$db" 'PRAGMA user_version;')" || die "cannot read user_version from $db (corrupt?)"
    if [ "$ver" != "$SUPPORTED_USER_VERSION" ]; then
      die "unsupported schema user_version=$ver (supported=$SUPPORTED_USER_VERSION); recreate empty work.db"
    fi
    # Ensure WAL + busy_timeout on existing DB connections path
    sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;" >/dev/null
  fi
  echo "$db"
}

# outer retry helper for later write commands
with_retry() {
  local attempt=1
  local delays="0.05 0.1 0.2"
  local d
  set -- $delays
  while true; do
    if "$@"; then return 0; fi
    if [ "$attempt" -ge 3 ]; then return 1; fi
    d="$1"; shift || true
    sleep "${d:-0.2}"
    attempt=$((attempt+1))
  done
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    ensure) cmd_ensure "$@" ;;
    "") die "usage: dw-db.sh <command> ..." ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
