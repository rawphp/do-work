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

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Escape a string for use inside a single-quoted SQL literal.
# Double single-quotes (SQL standard). Do NOT use ${s//\'/\'\'} — bash emits
# backslash-escaped quotes (it\'s) which break SQLite string literals.
sql_quote() {
  local s="${1:-}"
  s="${s//\'/''}"
  printf "'%s'" "$s"
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

# Open path: ensure DB exists and return absolute path. Echoes path only.
open_db() {
  local root="${1:-}"
  [ -n "$root" ] || die "project root required"
  cmd_ensure "$root" >/dev/null
  resolve_db "$root"
}

sql_exec() {
  local db="$1"; shift
  # PRAGMAs are connection-local — must run on the same sqlite3 process as the write.
  # Write-only helper: discard stdout (journal_mode may print "wal").
  sqlite3 "$db" >/dev/null <<SQL
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
$*
SQL
}

# Run a multi-line SQL script with PRAGMAs prepended.
sql_script() {
  local db="$1"
  local script="$2"
  sqlite3 "$db" <<SQL
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
$script
SQL
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

# outer retry helper for write commands
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

# Numeric slug allocation: max integer suffix + 1, min width 3, grows past 3.
# NEVER use string MAX(slug). Call inside BEGIN IMMEDIATE transaction (or alone).
# Args: db kind(UR|REQ) → prints KIND-NNN
next_slug() {
  local db="$1"
  local kind="$2"  # UR | REQ
  local table
  case "$kind" in
    UR) table=urs ;;
    REQ) table=reqs ;;
    *) die "next_slug: kind must be UR or REQ" ;;
  esac
  local max_n
  # Cast suffix after first '-' as integer; ignore non-matching shapes.
  max_n="$(sqlite3 "$db" "SELECT COALESCE(MAX(CAST(substr(slug, instr(slug,'-')+1) AS INTEGER)), 0) FROM $table WHERE slug LIKE '${kind}-%';")"
  [ -n "$max_n" ] || max_n=0
  local n=$((max_n + 1))
  local s="$n"
  while [ ${#s} -lt 3 ]; do
    s="0$s"
  done
  echo "${kind}-$s"
}

normalize_status() {
  case "$1" in
    in-progress) echo in_progress ;;
    backlog|in_progress|stopped|done) echo "$1" ;;
    *) die "invalid status: $1 (want backlog|in-progress|in_progress|stopped|done)" ;;
  esac
}

# Resolve REQ slug → internal id. Empty if missing.
req_id_for_slug() {
  local db="$1"
  local slug="$2"
  sqlite3 "$db" "SELECT id FROM reqs WHERE slug=$(sql_quote "$slug");"
}

ur_id_for_slug() {
  local db="$1"
  local slug="$2"
  sqlite3 "$db" "SELECT id FROM urs WHERE slug=$(sql_quote "$slug");"
}

# Run a write transaction; only SELECT results that match KIND-digits are returned.
# PRAGMAs ride on the same connection as the write (foreign_keys is connection-local).
tx_slug_insert() {
  local db="$1"
  local sql="$2"
  local out rc
  out="$(sqlite3 "$db" <<SQL
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
$sql
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  # Last line that looks like a slug (filters PRAGMA journal_mode "wal" noise)
  printf '%s\n' "$out" | grep -E '^(UR|REQ)-[0-9]+$' | tail -1
}

# --- create-ur <root> --title T --brief B [--class C] ---
cmd_create_ur() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "create-ur: project root required"
  local title="" brief="" class=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift 2 ;;
      --brief) brief="${2:-}"; shift 2 ;;
      --class) class="${2:-}"; shift 2 ;;
      *) die "create-ur: unknown arg: $1" ;;
    esac
  done
  [ -n "$title" ] || die "create-ur: --title required"
  [ -n "$brief" ] || die "create-ur: --brief required"
  require_sqlite3
  local db now out
  db="$(open_db "$root")"
  now="$(iso_now)"
  out="$(tx_slug_insert "$db" "
CREATE TEMP TABLE IF NOT EXISTS _alloc(n INTEGER);
DELETE FROM _alloc;
INSERT INTO _alloc(n)
  SELECT COALESCE(MAX(CAST(substr(slug, instr(slug,'-')+1) AS INTEGER)), 0) + 1
  FROM urs WHERE slug LIKE 'UR-%';
INSERT INTO urs(slug, title, class, brief, created_at)
SELECT
  'UR-' || CASE
    WHEN length(CAST(n AS TEXT)) < 3 THEN substr('000' || CAST(n AS TEXT), -3)
    ELSE CAST(n AS TEXT)
  END,
  $(sql_quote "$title"),
  $(sql_quote "$class"),
  $(sql_quote "$brief"),
  $(sql_quote "$now")
FROM _alloc;
SELECT slug FROM urs WHERE id = last_insert_rowid();
")" || die "create-ur: insert failed"
  [ -n "$out" ] || die "create-ur: no slug returned"
  echo "$out"
}

# --- create-req <root> --ur UR --title T [opts] ---
cmd_create_req() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "create-req: project root required"
  local ur="" title="" body="" priority="" files="" deps="" parent="" layer="" path_milestone="" size=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ur) ur="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --body) body="${2:-}"; shift 2 ;;
      --priority) priority="${2:-}"; shift 2 ;;
      --files) files="${2:-}"; shift 2 ;;
      --deps) deps="${2:-}"; shift 2 ;;
      --parent) parent="${2:-}"; shift 2 ;;
      --layer) layer="${2:-}"; shift 2 ;;
      --path-milestone) path_milestone="${2:-}"; shift 2 ;;
      --size) size="${2:-}"; shift 2 ;;
      *) die "create-req: unknown arg: $1" ;;
    esac
  done
  [ -n "$ur" ] || die "create-req: --ur required"
  [ -n "$title" ] || die "create-req: --title required"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local now
  now="$(iso_now)"

  local ur_id
  ur_id="$(ur_id_for_slug "$db" "$ur")"
  [ -n "$ur_id" ] || die "create-req: unknown UR slug: $ur"

  local parent_sql="NULL"
  if [ -n "$parent" ]; then
    local pid
    pid="$(req_id_for_slug "$db" "$parent")"
    [ -n "$pid" ] || die "create-req: unknown parent slug: $parent"
    parent_sql="$pid"
  fi

  local pri_sql="NULL"
  if [ -n "$priority" ]; then
    case "$priority" in
      *[!0-9]*|"") die "create-req: --priority must be a non-negative integer" ;;
    esac
    pri_sql="$priority"
  fi

  local pm_sql="NULL"
  if [ -n "$path_milestone" ]; then
    pm_sql="$(sql_quote "$path_milestone")"
  fi

  # Build dep resolution inside transaction; pre-validate slugs for clear errors.
  local dep_slugs="" d
  if [ -n "$deps" ]; then
    # tokenize on comma and whitespace
    deps="$(printf '%s' "$deps" | tr ',\t' '  ')"
    for d in $deps; do
      [ -n "$d" ] || continue
      local did
      did="$(req_id_for_slug "$db" "$d")"
      [ -n "$did" ] || die "create-req: unknown dep slug: $d"
      dep_slugs="$dep_slugs $d"
    done
  fi

  local out
  out="$(tx_slug_insert "$db" "
CREATE TEMP TABLE IF NOT EXISTS _alloc(n INTEGER);
DELETE FROM _alloc;
INSERT INTO _alloc(n)
  SELECT COALESCE(MAX(CAST(substr(slug, instr(slug,'-')+1) AS INTEGER)), 0) + 1
  FROM reqs WHERE slug LIKE 'REQ-%';
INSERT INTO reqs(
  slug, ur_id, title, status, layer, parent_req_id, path_milestone,
  files, size, priority, body, created_at, updated_at
)
SELECT
  'REQ-' || CASE
    WHEN length(CAST(n AS TEXT)) < 3 THEN substr('000' || CAST(n AS TEXT), -3)
    ELSE CAST(n AS TEXT)
  END,
  $ur_id,
  $(sql_quote "$title"),
  'backlog',
  $(sql_quote "$layer"),
  $parent_sql,
  $pm_sql,
  $(sql_quote "$files"),
  $(sql_quote "$size"),
  $pri_sql,
  $(sql_quote "$body"),
  $(sql_quote "$now"),
  $(sql_quote "$now")
FROM _alloc;
SELECT slug FROM reqs WHERE id = last_insert_rowid();
")" || die "create-req: insert failed"
  [ -n "$out" ] || die "create-req: no slug returned"

  # Insert deps after (same logical create; still atomic enough — deps validated).
  # Re-open transaction for deps if any.
  if [ -n "$dep_slugs" ]; then
    local rid did
    rid="$(req_id_for_slug "$db" "$out")"
    [ -n "$rid" ] || die "create-req: cannot resolve new slug $out"
    for d in $dep_slugs; do
      did="$(req_id_for_slug "$db" "$d")"
      [ -n "$did" ] || die "create-req: unknown dep slug: $d"
      sql_exec "$db" "INSERT OR IGNORE INTO deps(req_id, depends_on_req_id) VALUES($rid, $did);" \
        || die "create-req: failed to insert dep $d"
    done
  fi
  echo "$out"
}

# --- get-ur <root> <slug> ---
cmd_get_ur() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "get-ur: usage: get-ur <root> <UR-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local s t c b ca cl
  s="$(sqlite3 "$db" "SELECT slug FROM urs WHERE slug=$(sql_quote "$slug");")"
  [ -n "$s" ] || die "get-ur: not found: $slug"
  t="$(sqlite3 "$db" "SELECT title FROM urs WHERE slug=$(sql_quote "$slug");")"
  c="$(sqlite3 "$db" "SELECT class FROM urs WHERE slug=$(sql_quote "$slug");")"
  b="$(sqlite3 "$db" "SELECT brief FROM urs WHERE slug=$(sql_quote "$slug");")"
  ca="$(sqlite3 "$db" "SELECT created_at FROM urs WHERE slug=$(sql_quote "$slug");")"
  cl="$(sqlite3 "$db" "SELECT COALESCE(closed_at,'') FROM urs WHERE slug=$(sql_quote "$slug");")"
  printf 'slug=%s\ntitle=%s\nclass=%s\nbrief=%s\ncreated_at=%s\nclosed_at=%s\n' \
    "$s" "$t" "$c" "$b" "$ca" "$cl"
}

# --- list-urs <root> ---
cmd_list_urs() {
  local root="${1:-}"
  [ -n "$root" ] || die "list-urs: project root required"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  sqlite3 -separator $'\t' "$db" "
SELECT slug, title, class, COALESCE(closed_at,'') FROM urs ORDER BY
  CAST(substr(slug, instr(slug,'-')+1) AS INTEGER) ASC;"
}

# --- get-req <root> <slug> ---
cmd_get_req() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "get-req: usage: get-req <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local s t st ur layer files pri pm body ca ua parent
  s="$(sqlite3 "$db" "SELECT slug FROM reqs WHERE slug=$(sql_quote "$slug");")"
  [ -n "$s" ] || die "get-req: not found: $slug"
  t="$(sqlite3 "$db" "SELECT title FROM reqs WHERE slug=$(sql_quote "$slug");")"
  st="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug=$(sql_quote "$slug");")"
  ur="$(sqlite3 "$db" "SELECT u.slug FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE r.slug=$(sql_quote "$slug");")"
  layer="$(sqlite3 "$db" "SELECT layer FROM reqs WHERE slug=$(sql_quote "$slug");")"
  files="$(sqlite3 "$db" "SELECT files FROM reqs WHERE slug=$(sql_quote "$slug");")"
  pri="$(sqlite3 "$db" "SELECT COALESCE(CAST(priority AS TEXT),'') FROM reqs WHERE slug=$(sql_quote "$slug");")"
  pm="$(sqlite3 "$db" "SELECT COALESCE(path_milestone,'') FROM reqs WHERE slug=$(sql_quote "$slug");")"
  body="$(sqlite3 "$db" "SELECT body FROM reqs WHERE slug=$(sql_quote "$slug");")"
  ca="$(sqlite3 "$db" "SELECT created_at FROM reqs WHERE slug=$(sql_quote "$slug");")"
  ua="$(sqlite3 "$db" "SELECT updated_at FROM reqs WHERE slug=$(sql_quote "$slug");")"
  parent="$(sqlite3 "$db" "SELECT COALESCE(p.slug,'') FROM reqs r LEFT JOIN reqs p ON p.id=r.parent_req_id WHERE r.slug=$(sql_quote "$slug");")"
  printf 'slug=%s\ntitle=%s\nstatus=%s\nur=%s\nlayer=%s\nfiles=%s\npriority=%s\npath_milestone=%s\nparent=%s\ncreated_at=%s\nupdated_at=%s\nbody=%s\n' \
    "$s" "$t" "$st" "$ur" "$layer" "$files" "$pri" "$pm" "$parent" "$ca" "$ua" "$body"
}

# --- list-reqs <root> [--ur UR-NNN] ---
cmd_list_reqs() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "list-reqs: project root required"
  local ur=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ur) ur="${2:-}"; shift 2 ;;
      *) die "list-reqs: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db
  db="$(open_db "$root")"
  if [ -n "$ur" ]; then
    local uid
    uid="$(ur_id_for_slug "$db" "$ur")"
    [ -n "$uid" ] || die "list-reqs: unknown UR slug: $ur"
    sqlite3 -separator $'\t' "$db" "
SELECT r.slug, r.title, r.status, u.slug
FROM reqs r JOIN urs u ON u.id=r.ur_id
WHERE r.ur_id=$uid
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;"
  else
    sqlite3 -separator $'\t' "$db" "
SELECT r.slug, r.title, r.status, u.slug
FROM reqs r JOIN urs u ON u.id=r.ur_id
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;"
  fi
}

# --- update-req <root> <slug> [--title T] [--body B] [--priority N] [--layer L] ... ---
cmd_update_req() {
  local root="${1:-}" slug="${2:-}"
  shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "update-req: usage: update-req <root> <REQ-NNN> [flags]"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "update-req: not found: $slug"
  local sets="" now
  now="$(iso_now)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)
        sets="${sets}title=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --body)
        sets="${sets}body=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --priority)
        case "${2:-}" in
          *[!0-9]*|"") die "update-req: --priority must be a non-negative integer" ;;
        esac
        sets="${sets}priority=${2}, "
        shift 2 ;;
      --layer)
        sets="${sets}layer=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --files)
        sets="${sets}files=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --size)
        sets="${sets}size=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --path-milestone)
        if [ -z "${2:-}" ]; then
          sets="${sets}path_milestone=NULL, "
        else
          sets="${sets}path_milestone=$(sql_quote "$2"), "
        fi
        shift 2 ;;
      --parent)
        if [ -z "${2:-}" ]; then
          sets="${sets}parent_req_id=NULL, "
        else
          local pid
          pid="$(req_id_for_slug "$db" "$2")"
          [ -n "$pid" ] || die "update-req: unknown parent slug: $2"
          sets="${sets}parent_req_id=$pid, "
        fi
        shift 2 ;;
      --entry-point)
        sets="${sets}entry_point=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --terminal-state)
        sets="${sets}terminal_state=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --criteria-approved)
        sets="${sets}criteria_approved=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --closure-proof)
        sets="${sets}closure_proof=$(sql_quote "${2:-}"), "
        shift 2 ;;
      --suite)
        sets="${sets}suite=$(sql_quote "${2:-}"), "
        shift 2 ;;
      *) die "update-req: unknown arg: $1" ;;
    esac
  done
  [ -n "$sets" ] || die "update-req: no fields to update"
  sets="${sets}updated_at=$(sql_quote "$now")"
  sql_exec "$db" "UPDATE reqs SET $sets WHERE id=$rid;" || die "update-req: update failed"
}

# --- set-status <root> <slug> <status> ---
cmd_set_status() {
  local root="${1:-}" slug="${2:-}" status="${3:-}"
  [ -n "$root" ] && [ -n "$slug" ] && [ -n "$status" ] || die "set-status: usage: set-status <root> <REQ-NNN> <status>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "set-status: not found: $slug"
  local norm now
  norm="$(normalize_status "$status")"
  now="$(iso_now)"
  sql_exec "$db" "UPDATE reqs SET status=$(sql_quote "$norm"), updated_at=$(sql_quote "$now") WHERE id=$rid;" \
    || die "set-status: update failed"
}

# --- set-files <root> <slug> <files-text> ---
cmd_set_files() {
  local root="${1:-}" slug="${2:-}" files="${3:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "set-files: usage: set-files <root> <REQ-NNN> <files>"
  # files may be empty
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid now
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "set-files: not found: $slug"
  now="$(iso_now)"
  sql_exec "$db" "UPDATE reqs SET files=$(sql_quote "$files"), updated_at=$(sql_quote "$now") WHERE id=$rid;" \
    || die "set-files: update failed"
}

# --- set-blocked-by <root> <slug> <dep-slugs...> ---
# Replace deps for REQ. Inputs: REQ slugs (comma and/or whitespace). Invalid → hard error.
cmd_set_blocked_by() {
  local root="${1:-}" slug="${2:-}"
  shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "set-blocked-by: usage: set-blocked-by <root> <REQ-NNN> [dep slugs...]"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "set-blocked-by: not found: $slug"

  # Collect dep tokens from remaining args (each arg may contain commas/spaces)
  local tokens="" raw t
  for raw in "$@"; do
    raw="$(printf '%s' "$raw" | tr ',\t' '  ')"
    for t in $raw; do
      [ -n "$t" ] || continue
      tokens="$tokens $t"
    done
  done

  # Validate all deps first
  local dep_ids="" did
  for t in $tokens; do
    did="$(req_id_for_slug "$db" "$t")"
    [ -n "$did" ] || die "set-blocked-by: unknown dep slug: $t"
    dep_ids="$dep_ids $did"
  done

  local now
  now="$(iso_now)"
  # Replace in one transaction (PRAGMAs on same connection as writes)
  local inserts=""
  for did in $dep_ids; do
    inserts="${inserts}INSERT INTO deps(req_id, depends_on_req_id) VALUES($rid, $did);
"
  done
  sqlite3 "$db" >/dev/null <<SQL || die "set-blocked-by: transaction failed"
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
DELETE FROM deps WHERE req_id=$rid;
$inserts
UPDATE reqs SET updated_at=$(sql_quote "$now") WHERE id=$rid;
COMMIT;
SQL
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    ensure) cmd_ensure "$@" ;;
    create-ur) cmd_create_ur "$@" ;;
    create-req) cmd_create_req "$@" ;;
    get-ur) cmd_get_ur "$@" ;;
    get-req) cmd_get_req "$@" ;;
    list-urs) cmd_list_urs "$@" ;;
    list-reqs) cmd_list_reqs "$@" ;;
    update-req) cmd_update_req "$@" ;;
    set-status) cmd_set_status "$@" ;;
    set-files) cmd_set_files "$@" ;;
    set-blocked-by) cmd_set_blocked_by "$@" ;;
    "") die "usage: dw-db.sh <command> ..." ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
