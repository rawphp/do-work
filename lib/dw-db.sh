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

# Default stale threshold (seconds). Design §8.3: parallel.stale_threshold_seconds default 900.
DEFAULT_STALE_MAX=900

# HTML-escape user-derived text for static board output (& first, then < > ").
html_escape() {
  printf '%s' "${1:-}" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# ISO-8601 UTC → epoch seconds (macOS BSD date + GNU date).
iso_to_epoch() {
  local ts="$1"
  local epoch
  epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null)" || true
  if [ -n "${epoch:-}" ]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  epoch="$(date -u -d "$ts" "+%s" 2>/dev/null)" || true
  if [ -n "${epoch:-}" ]; then
    printf '%s\n' "$epoch"
    return 0
  fi
  return 1
}

# Age in seconds of an ISO heartbeat; empty if unparseable.
heartbeat_age_secs() {
  local hb="$1"
  local now_e hb_e
  now_e="$(date -u +%s)"
  hb_e="$(iso_to_epoch "$hb" 2>/dev/null)" || true
  if [ -z "${hb_e:-}" ]; then
    return 1
  fi
  echo $(( now_e - hb_e ))
}

# Return 0 if active claim heartbeat is stale (age > stale_max) or unparseable/missing.
# Args: heartbeat_iso stale_max
is_stale_heartbeat() {
  local hb="$1"
  local max="$2"
  if [ -z "$hb" ]; then
    return 0
  fi
  local age
  age="$(heartbeat_age_secs "$hb" 2>/dev/null)" || return 0
  if [ "$age" -gt "$max" ]; then
    return 0
  fi
  return 1
}

# Tokenize files field: whitespace and commas are separators.
tokenize_files() {
  local raw="$1"
  raw="$(printf '%s' "$raw" | tr ',\t' '  ')"
  local t
  for t in $raw; do
    [ -n "$t" ] || continue
    printf '%s\n' "$t"
  done
}

# Expand one files token against project root (nullglob: unmatched → nothing).
# Prints paths relative to root when possible.
expand_files_token() {
  local root="$1"
  local entry="$2"
  if [ -z "$entry" ]; then
    return 0
  fi
  (
    cd "$root" || exit 0
    case "$entry" in
      *\*\**)
        # Manual ** walker (bash 3.2 has no globstar)
        local before="${entry%%\*\**}"
        local after="${entry#*\*\*}"
        local search_root="${before%/}"
        [ -n "$search_root" ] || search_root="."
        [ -d "$search_root" ] || exit 0
        local suffix="${after#/}"
        local f
        while IFS= read -r f; do
          case "$f" in
            ./*) f="${f#./}" ;;
          esac
          if [ -z "$suffix" ]; then
            [ -f "$f" ] && printf '%s\n' "$f"
          else
            case "$f" in
              $before*$suffix) [ -f "$f" ] && printf '%s\n' "$f" ;;
            esac
          fi
        done < <(find "$search_root" -type f -print 2>/dev/null)
        ;;
      *)
        local _old_nullglob
        _old_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
        shopt -s nullglob 2>/dev/null || true
        # shellcheck disable=SC2206,SC2086
        local matches=( $entry )
        eval "$_old_nullglob" 2>/dev/null || true
        local m
        for m in "${matches[@]}"; do
          printf '%s\n' "$m"
        done
        ;;
    esac
  )
}

# Expanded unique file set for a files text field. Args: root files_text
expanded_files_set() {
  local root="$1"
  local files="$2"
  local tok
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    expand_files_token "$root" "$tok"
  done < <(tokenize_files "$files") | LC_ALL=C sort -u
}

# Active claim row for req_id: prints agent_id|heartbeat|id or empty
active_claim_row() {
  local db="$1"
  local rid="$2"
  sqlite3 -separator '|' "$db" \
    "SELECT agent_id, heartbeat, id FROM claims WHERE req_id=$rid AND status='active' LIMIT 1;"
}

# --- claim <root> <REQ-NNN> <agent_id> [--session S] [--stale-max N] ---
cmd_claim() {
  local root="${1:-}" slug="${2:-}" agent="${3:-}"
  shift 3 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] && [ -n "$agent" ] || \
    die "claim: usage: claim <root> <REQ-NNN> <agent_id> [--session S] [--stale-max N]"
  local session="" stale_max="$DEFAULT_STALE_MAX"
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="${2:-}"; shift 2 ;;
      --stale-max)
        case "${2:-}" in
          ''|*[!0-9]*) die "claim: --stale-max must be positive integer" ;;
        esac
        stale_max="$2"
        shift 2 ;;
      *) die "claim: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "claim: not found: $slug"

  local now
  now="$(iso_now)"

  # Pre-read outside tx for clearer concurrent-conflict (re-check inside tx).
  local row agent_cur hb_cur claim_id status_cur
  row="$(active_claim_row "$db" "$rid")"
  status_cur="$(sqlite3 "$db" "SELECT status FROM reqs WHERE id=$rid;")"
  [ "$status_cur" != "done" ] || die "claim: REQ is done: $slug"

  if [ -n "$row" ]; then
    agent_cur="${row%%|*}"
    rest="${row#*|}"
    hb_cur="${rest%%|*}"
    claim_id="${rest##*|}"
    if [ "$agent_cur" = "$agent" ]; then
      # Own active: idempotent refresh
      sql_exec "$db" "UPDATE claims SET heartbeat=$(sql_quote "$now") WHERE id=$claim_id AND status='active';" \
        || die "claim: heartbeat refresh failed"
      return 0
    fi
    if ! is_stale_heartbeat "$hb_cur" "$stale_max"; then
      echo "concurrent-conflict: $slug held by $agent_cur" >&2
      exit 2
    fi
  fi

  # Re-check then release-then-insert / insert in one transaction.
  local re_row re_agent re_hb re_status rest
  re_status="$(sqlite3 "$db" "SELECT status FROM reqs WHERE id=$rid;")"
  [ "$re_status" != "done" ] || die "claim: REQ is done: $slug"
  re_row="$(active_claim_row "$db" "$rid")"

  if [ -n "$re_row" ]; then
    re_agent="${re_row%%|*}"
    rest="${re_row#*|}"
    re_hb="${rest%%|*}"
    if [ "$re_agent" = "$agent" ]; then
      sql_exec "$db" "UPDATE claims SET heartbeat=$(sql_quote "$now") WHERE req_id=$rid AND status='active';" \
        || die "claim: own refresh failed"
      return 0
    fi
    if ! is_stale_heartbeat "$re_hb" "$stale_max"; then
      echo "concurrent-conflict: $slug held by $re_agent" >&2
      exit 2
    fi
    # Stale foreign: release-then-insert in one transaction
    sqlite3 "$db" >/dev/null <<SQL || die "claim: stale takeover failed"
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE claims SET status='released' WHERE req_id=$rid AND status='active';
UPDATE reqs SET status='in_progress', updated_at=$(sql_quote "$now") WHERE id=$rid;
INSERT INTO claims(req_id, agent_id, claimed_at, heartbeat, session, status)
  VALUES($rid, $(sql_quote "$agent"), $(sql_quote "$now"), $(sql_quote "$now"), $(sql_quote "$session"), 'active');
COMMIT;
SQL
    return 0
  fi

  # No active claim: insert + set in_progress
  sqlite3 "$db" >/dev/null <<SQL || die "claim: insert failed"
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE reqs SET status='in_progress', updated_at=$(sql_quote "$now") WHERE id=$rid;
INSERT INTO claims(req_id, agent_id, claimed_at, heartbeat, session, status)
  VALUES($rid, $(sql_quote "$agent"), $(sql_quote "$now"), $(sql_quote "$now"), $(sql_quote "$session"), 'active');
COMMIT;
SQL
}

# --- heartbeat <root> <REQ-NNN> <agent_id> ---
# UPDATE-only; exit 1 if not owner / no active claim. Never INSERT.
cmd_heartbeat() {
  local root="${1:-}" slug="${2:-}" agent="${3:-}"
  [ -n "$root" ] && [ -n "$slug" ] && [ -n "$agent" ] || \
    die "heartbeat: usage: heartbeat <root> <REQ-NNN> <agent_id>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "heartbeat: not found: $slug"
  local now
  now="$(iso_now)"
  local n
  n="$(sqlite3 "$db" "SELECT changes() FROM (
    SELECT 1 WHERE 0
  );" 2>/dev/null || true)"
  # Perform UPDATE and check changes()
  n="$(sqlite3 "$db" <<SQL
PRAGMA busy_timeout=5000;
UPDATE claims SET heartbeat=$(sql_quote "$now")
  WHERE req_id=$rid AND status='active' AND agent_id=$(sql_quote "$agent");
SELECT changes();
SQL
)" || die "heartbeat: update failed"
  # changes() is last line
  n="$(printf '%s\n' "$n" | tail -1)"
  if [ "${n:-0}" = "0" ]; then
    die "heartbeat: not claim owner or no active claim for $slug"
  fi
}

# --- unblock <root> <REQ-NNN> ---
# Set backlog + release active claim.
cmd_unblock() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "unblock: usage: unblock <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid now
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "unblock: not found: $slug"
  now="$(iso_now)"
  sqlite3 "$db" >/dev/null <<SQL || die "unblock: transaction failed"
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE claims SET status='released' WHERE req_id=$rid AND status='active';
UPDATE reqs SET status='backlog', updated_at=$(sql_quote "$now") WHERE id=$rid;
COMMIT;
SQL
}

# --- check-deps <root> <REQ-NNN> ---
# Print unsatisfied dep slugs (status ≠ done), one per line. Exit 0 always if REQ exists.
cmd_check_deps() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "check-deps: usage: check-deps <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "check-deps: not found: $slug"
  sqlite3 "$db" "
SELECT d.slug FROM deps dep
JOIN reqs d ON d.id = dep.depends_on_req_id
WHERE dep.req_id = $rid AND d.status != 'done'
ORDER BY CAST(substr(d.slug, instr(d.slug,'-')+1) AS INTEGER) ASC;"
}

# ----------------------------------------------------------------------
# Cycle detection (parity with lib/cycle-check.sh, but over the sqlite
# deps junction). Two reusable helpers + one command:
#   - graph_from_db <db>: emit a NODE/EDGE stream for cycle_core.
#   - cycle_core [UR-NNN]: iterative-DFS cycle detector over that stream.
#   - cmd_cycle_check: the dw-db cycle-check command.
#
# Stream protocol (line-oriented, fed to cycle_core on stdin):
#   NODE <req-slug> <ur-slug>     — declare a node + its owning UR
#   EDGE <from-slug> <to-slug>    — "from depends on to"
# Hypothetical edges (set-blocked-by "would this create a cycle?" probe)
# are extra EDGE lines appended to the same stream — never persisted.
# A UR argument is a REPORT FILTER only: the subgraph is always the whole
# deps table, so cycles routed through another UR's REQs are still detected;
# a cycle is reported only when at least one node in it belongs to that UR.
# ----------------------------------------------------------------------

# graph_from_db <db> — print NODE/EDGE lines for every req + every dep edge.
# Uses a non-whitespace column separator (field lesson: tab collapses empty
# fields under IFS reads; slugs/URs are non-empty here, but stay bulletproof).
graph_from_db() {
  local db="$1"
  local sep=$'\x1e'
  sqlite3 -separator "$sep" "$db" \
    "SELECT r.slug, u.slug FROM reqs r JOIN urs u ON u.id = r.ur_id;" \
    | awk -F"$sep" '{ printf "NODE %s %s\n", $1, ($2 == "" ? "-" : $2) }'
  sqlite3 -separator "$sep" "$db" "
SELECT r1.slug, r2.slug FROM deps d
JOIN reqs r1 ON r1.id = d.req_id
JOIN reqs r2 ON r2.id = d.depends_on_req_id;" \
    | awk -F"$sep" '{ printf "EDGE %s %s\n", $1, $2 }'
}

# cycle_core [UR-NNN] — reads NODE/EDGE stream on stdin.
# On cycle: prints "A → B → ... → A" to stdout, exits 1.
# Acyclic (or no matching cycle under a filter): silent, exits 0.
# Algorithm: iterative DFS implemented entirely in awk (no shell recursion;
# safe on linear chains of 1000+ REQs). Adapted from lib/cycle-check.sh.
cycle_core() {
  local filter="${1:-}"
  awk -v filter="$filter" '
/^NODE / {
  id = $2
  ur = ($3 == "" || $3 == "-") ? "" : $3
  if (!(id in seen)) {
    seen[id] = 1
    node_ur[id] = ur
    node_list[node_n++] = id
    if (!(id in adj_count)) { adj[id] = ""; adj_count[id] = 0 }
  } else {
    # Keep the UR if a later NODE line provides one.
    if (ur != "") node_ur[id] = ur
  }
  next
}
/^EDGE / {
  from = $2
  to   = $3
  # Ensure both endpoints exist as nodes (defensive: hypothetical edges
  # should already have NODE lines, but never assume).
  if (!(from in seen)) {
    seen[from] = 1; node_ur[from] = ""; node_list[node_n++] = from
    if (!(from in adj_count)) { adj[from] = ""; adj_count[from] = 0 }
  }
  if (!(to in seen)) {
    seen[to] = 1; node_ur[to] = ""; node_list[node_n++] = to
    if (!(to in adj_count)) { adj[to] = ""; adj_count[to] = 0 }
  }
  if (adj_count[from] == 0) adj[from] = to
  else adj[from] = adj[from] " " to
  adj_count[from]++
  next
}
END {
  for (ii = 0; ii < node_n; ii++) {
    start = node_list[ii]
    if (visited[start]) continue

    stack_top = 0
    stack[stack_top] = start
    stack_edge_idx[stack_top] = 0
    delete on_path
    delete path_order
    path_len = 0

    while (stack_top >= 0) {
      node = stack[stack_top]

      if (!visited[node] && !on_path[node]) {
        on_path[node] = 1
        path_order[path_len] = node
        path_len++
      }

      found_child = 0
      if (adj_count[node] > 0) {
        n_children = split(adj[node], children, " ")
        edge_start = stack_edge_idx[stack_top]
        for (ci = edge_start + 1; ci <= n_children; ci++) {
          child = children[ci]
          stack_edge_idx[stack_top] = ci

          if (on_path[child]) {
            # Back-edge → cycle: child ... node -> child.
            cycle_start = -1
            for (k = 0; k < path_len; k++) {
              if (path_order[k] == child) { cycle_start = k; break }
            }
            # Decide whether to REPORT this cycle under the UR filter.
            report = 1
            if (filter != "") {
              report = 0
              if (node_ur[child] == filter) report = 1
              if (!report) {
                for (k = cycle_start + 1; k < path_len; k++) {
                  if (node_ur[path_order[k]] == filter) { report = 1; break }
                }
              }
            }
            if (report) {
              cycle_str = child
              for (k = cycle_start + 1; k < path_len; k++) {
                cycle_str = cycle_str " → " path_order[k]
              }
              cycle_str = cycle_str " → " child
              print cycle_str
              exit 1
            }
            # Filter mismatch: this cycle is out of scope. Skip this
            # back-edge and keep searching for one that involves filter.
            continue
          }

          if (!visited[child]) {
            stack_top++
            stack[stack_top] = child
            stack_edge_idx[stack_top] = 0
            found_child = 1
            break
          }
        }
      }

      if (!found_child) {
        on_path[node] = 0
        path_len--
        visited[node] = 1
        stack_top--
      }
    }
  }
  exit 0
}
'
}

# --- cycle-check <root> [UR-NNN] [--add FROM TO]... ---
# Validate the whole deps graph is acyclic. On cycle: prints the cycle path
# (e.g. REQ-007 → REQ-009 → REQ-007) and exits 1; acyclic: silent, exit 0.
# UR-NNN is a REPORT FILTER (see cycle_core). --add FROM TO adds a
# hypothetical (non-persisting) edge for "would this create a cycle?" probing.
cmd_cycle_check() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "cycle-check: project root required"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local filter="" add_edges="" from to fid tid
  while [ $# -gt 0 ]; do
    case "$1" in
      --add)
        [ $# -ge 3 ] || die "cycle-check: --add requires FROM TO"
        from="${2:-}"; to="${3:-}"
        [ -n "$from" ] && [ -n "$to" ] || die "cycle-check: --add FROM TO must be non-empty"
        fid="$(req_id_for_slug "$db" "$from")"
        tid="$(req_id_for_slug "$db" "$to")"
        [ -n "$fid" ] || die "cycle-check: --add unknown REQ slug: $from"
        [ -n "$tid" ] || die "cycle-check: --add unknown REQ slug: $to"
        add_edges="${add_edges}${from} ${to}
"
        shift 3
        ;;
      --*)
        die "cycle-check: unknown option: $1"
        ;;
      *)
        [ -z "$filter" ] || die "cycle-check: only one UR filter allowed"
        case "$1" in
          UR-*) filter="$1" ;;
          *) die "cycle-check: unexpected argument: $1 (want UR-NNN or --add FROM TO)" ;;
        esac
        shift
        ;;
    esac
  done

  {
    graph_from_db "$db"
    if [ -n "$add_edges" ]; then
      printf '%s' "$add_edges" | while IFS= read -r pair; do
        [ -n "$pair" ] || continue
        # shellcheck disable=SC2086  — pair is "FROM TO", word-split intended
        set -- $pair
        printf 'EDGE %s %s\n' "$1" "$2"
      done
    fi
  } | cycle_core "$filter"
}

# --- check-footprint <root> <REQ-NNN> ---
# Print overlap:<peer-slug> for each in-flight peer with non-empty path intersection.
cmd_check_footprint() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "check-footprint: usage: check-footprint <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid files
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "check-footprint: not found: $slug"
  files="$(sqlite3 "$db" "SELECT files FROM reqs WHERE id=$rid;")"
  if [ -z "$files" ]; then
    return 0
  fi
  local target_file
  target_file="$(mktemp -t dw-fp-target.XXXXXX)"
  expanded_files_set "$root" "$files" > "$target_file"
  if [ ! -s "$target_file" ]; then
    rm -f "$target_file"
    return 0
  fi

  # Peers: status in (in_progress, stopped) AND active claim, exclude self.
  # Use RS=0x1e so empty files fields do not collapse (bash read treats tab as IFS whitespace).
  local peers peer_slug peer_files peer_file intersection
  peers="$(sqlite3 -separator $'\x1e' "$db" "
SELECT r.slug, r.files FROM reqs r
JOIN claims c ON c.req_id = r.id AND c.status = 'active'
WHERE r.status IN ('in_progress', 'stopped')
  AND r.id != $rid
ORDER BY r.slug;")"
  peer_file="$(mktemp -t dw-fp-peer.XXXXXX)"
  while IFS=$'\x1e' read -r peer_slug peer_files; do
    [ -n "$peer_slug" ] || continue
    expanded_files_set "$root" "$peer_files" > "$peer_file"
    [ -s "$peer_file" ] || continue
    intersection="$(LC_ALL=C comm -12 "$target_file" "$peer_file")"
    if [ -n "$intersection" ]; then
      printf 'overlap:%s\n' "$peer_slug"
    fi
  done <<EOF
$peers
EOF
  rm -f "$target_file" "$peer_file"
}

# --- scan-stale <root> [--stale-max N] ---
# Print stale active claims: <slug> <agent_id> <heartbeat> age=<secs|unknown>
cmd_scan_stale() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "scan-stale: usage: scan-stale <root> [--stale-max N]"
  local stale_max="$DEFAULT_STALE_MAX"
  while [ $# -gt 0 ]; do
    case "$1" in
      --stale-max)
        case "${2:-}" in
          ''|*[!0-9]*) die "scan-stale: --stale-max must be positive integer" ;;
        esac
        stale_max="$2"
        shift 2 ;;
      *) die "scan-stale: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local lines slug agent hb age
  lines="$(sqlite3 -separator $'\x1e' "$db" "
SELECT r.slug, c.agent_id, c.heartbeat
FROM claims c JOIN reqs r ON r.id=c.req_id
WHERE c.status='active'
ORDER BY r.slug;")"
  while IFS=$'\x1e' read -r slug agent hb; do
    [ -n "$slug" ] || continue
    if is_stale_heartbeat "$hb" "$stale_max"; then
      age="$(heartbeat_age_secs "$hb" 2>/dev/null || true)"
      if [ -z "${age:-}" ]; then
        age="unknown"
      fi
      printf '%s %s %s age=%s\n' "$slug" "$agent" "$hb" "$age"
    fi
  done <<EOF
$lines
EOF
}

# Count unchecked `- [ ]` under ## Acceptance Criteria in body.
# Prints count to stdout.
count_unchecked_ac() {
  local body="$1"
  printf '%s\n' "$body" | awk '
    /^## *Acceptance Criteria/ { in_ac=1; next }
    /^## / && in_ac { in_ac=0 }
    in_ac && /^[[:space:]]*-[[:space:]]*\[[[:space:]]\]/ { n++ }
    END { print n+0 }
  '
}

# Shared archive criteria checks. Args: db slug
# Sets global __arch_fail reasons on stderr; returns 0 if all pass.
# Mode: full (status done + proof + AC) | gate (proof + AC only for archive-req pre-set)
_check_archive_inner() {
  local db="$1"
  local slug="$2"
  local mode="${3:-full}"  # full | gate
  local rid status proof body unchecked
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || { echo "check-archive: not found: $slug" >&2; return 1; }
  status="$(sqlite3 "$db" "SELECT status FROM reqs WHERE id=$rid;")"
  proof="$(sqlite3 "$db" "SELECT TRIM(closure_proof) FROM reqs WHERE id=$rid;")"
  body="$(sqlite3 "$db" "SELECT body FROM reqs WHERE id=$rid;")"
  local failed=0
  if [ "$mode" = "full" ]; then
    if [ "$status" != "done" ]; then
      echo "check-archive: $slug status not done (got '$status')" >&2
      failed=1
    fi
  fi
  if [ -z "$proof" ]; then
    echo "check-archive: $slug missing closure proof" >&2
    failed=1
  fi
  unchecked="$(count_unchecked_ac "$body")"
  if [ "${unchecked:-0}" -gt 0 ]; then
    echo "check-archive: $slug unchecked acceptance criteria: $unchecked" >&2
    failed=1
  fi
  return "$failed"
}

# --- check-archive <root> <REQ-NNN> ---
# Three criteria: status=done, non-empty closure_proof, no unchecked AC.
cmd_check_archive() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "check-archive: usage: check-archive <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  _check_archive_inner "$db" "$slug" full
}

# --- archive-req <root> <REQ-NNN> ---
# Gate: proof + no unchecked AC; then set done + release active claim.
cmd_archive_req() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "archive-req: usage: archive-req <root> <REQ-NNN>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  local rid
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "archive-req: not found: $slug"
  _check_archive_inner "$db" "$slug" gate || die "archive-req: integrity checks failed for $slug"
  local now
  now="$(iso_now)"
  sqlite3 "$db" >/dev/null <<SQL || die "archive-req: transaction failed"
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
UPDATE reqs SET status='done', updated_at=$(sql_quote "$now") WHERE id=$rid;
UPDATE claims SET status='released' WHERE req_id=$rid AND status='active';
COMMIT;
SQL
}

# Active milestone for a UR id (empty if none).
ur_active_milestone() {
  local db="$1"
  local ur_id="$2"
  sqlite3 "$db" "SELECT COALESCE(active,'') FROM milestone_state WHERE ur_id=$ur_id LIMIT 1;"
}

# Return 0 if REQ passes deps (all deps done).
req_deps_satisfied() {
  local db="$1"
  local rid="$2"
  local missing
  missing="$(sqlite3 "$db" "
SELECT COUNT(*) FROM deps dep
JOIN reqs d ON d.id = dep.depends_on_req_id
WHERE dep.req_id = $rid AND d.status != 'done';")"
  [ "${missing:-0}" = "0" ]
}

# Return 0 if REQ has no fresh active claim, or only stale (takeover-eligible).
# For list-claimable: backlog with fresh active is NOT claimable; stale active IS.
req_claim_slot_free() {
  local db="$1"
  local rid="$2"
  local stale_max="$3"
  local row agent hb
  row="$(active_claim_row "$db" "$rid")"
  if [ -z "$row" ]; then
    return 0
  fi
  hb="$(printf '%s' "$row" | cut -d'|' -f2)"
  if is_stale_heartbeat "$hb" "$stale_max"; then
    return 0
  fi
  return 1
}

# Return 0 if footprint free vs in-flight peers.
req_footprint_free() {
  local root="$1"
  local db="$2"
  local slug="$3"
  local rid="$4"
  local files overlaps
  files="$(sqlite3 "$db" "SELECT files FROM reqs WHERE id=$rid;")"
  if [ -z "$files" ]; then
    return 0
  fi
  overlaps="$(cmd_check_footprint "$root" "$slug" 2>/dev/null || true)"
  [ -z "$overlaps" ]
}

# --- list-claimable <root> [--ur UR-NNN] [--stale-max N] ---
# One REQ slug per line, ordered: priority DESC (null→2), numeric REQ ASC, created_at ASC, slug ASC.
cmd_list_claimable() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "list-claimable: usage: list-claimable <root> [--ur UR-NNN] [--stale-max N]"
  local ur="" stale_max="$DEFAULT_STALE_MAX"
  while [ $# -gt 0 ]; do
    case "$1" in
      --ur) ur="${2:-}"; shift 2 ;;
      --stale-max)
        case "${2:-}" in
          ''|*[!0-9]*) die "list-claimable: --stale-max must be positive integer" ;;
        esac
        stale_max="$2"
        shift 2 ;;
      *) die "list-claimable: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db
  db="$(open_db "$root")"

  local where="r.status = 'backlog'"
  if [ -n "$ur" ]; then
    local uid
    uid="$(ur_id_for_slug "$db" "$ur")"
    [ -n "$uid" ] || die "list-claimable: unknown UR slug: $ur"
    where="$where AND r.ur_id = $uid"
  fi

  # Candidates ordered; filter in bash for footprint/claim/milestone.
  # RS=0x1e — empty files / path_milestone must not collapse under bash read.
  local rows slug rid ur_id files path_m
  rows="$(sqlite3 -separator $'\x1e' "$db" "
SELECT r.slug, r.id, r.ur_id, r.files, COALESCE(r.path_milestone,'')
FROM reqs r
WHERE $where
ORDER BY
  COALESCE(r.priority, 2) DESC,
  CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC,
  r.created_at ASC,
  r.slug ASC;")"

  while IFS=$'\x1e' read -r slug rid ur_id files path_m; do
    [ -n "$slug" ] || continue

    # Milestone filter (per-UR cursor)
    local active_m
    active_m="$(ur_active_milestone "$db" "$ur_id")"
    if [ -n "$active_m" ]; then
      if [ "$path_m" != "$active_m" ]; then
        continue
      fi
    fi

    # Fresh active claim blocks (stale allows takeover via pick/claim)
    if ! req_claim_slot_free "$db" "$rid" "$stale_max"; then
      continue
    fi

    # Deps
    if ! req_deps_satisfied "$db" "$rid"; then
      continue
    fi

    # Footprint
    if ! req_footprint_free "$root" "$db" "$slug" "$rid"; then
      continue
    fi

    printf '%s\n' "$slug"
  done <<EOF
$rows
EOF
}

# --- pick <root> [--ur UR-NNN] [--stale-max N] ---
# First of list-claimable; empty + exit 1 if none.
cmd_pick() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "pick: usage: pick <root> [--ur UR-NNN] [--stale-max N]"
  local first
  first="$(cmd_list_claimable "$root" "$@" | head -1)"
  if [ -z "$first" ]; then
    exit 1
  fi
  printf '%s\n' "$first"
}

# --- artifact helpers (ur_artifacts) ---
# kind write modes: append (concat with blank line) | replace
_artifact_write() {
  local db="$1" ur_id="$2" kind="$3" mode="$4" body="$5" now="$6"
  local kind_q body_q now_q
  kind_q="$(sql_quote "$kind")"
  body_q="$(sql_quote "$body")"
  now_q="$(sql_quote "$now")"
  if [ "$mode" = "append" ]; then
    sql_exec "$db" "
INSERT INTO ur_artifacts(ur_id, kind, body, updated_at)
VALUES($ur_id, $kind_q, $body_q, $now_q)
ON CONFLICT(ur_id, kind) DO UPDATE SET
  body = CASE
    WHEN ur_artifacts.body = '' THEN excluded.body
    ELSE ur_artifacts.body || char(10) || char(10) || excluded.body
  END,
  updated_at = excluded.updated_at;
" || die "artifact write failed (kind=$kind)"
  else
    sql_exec "$db" "
INSERT INTO ur_artifacts(ur_id, kind, body, updated_at)
VALUES($ur_id, $kind_q, $body_q, $now_q)
ON CONFLICT(ur_id, kind) DO UPDATE SET
  body = excluded.body,
  updated_at = excluded.updated_at;
" || die "artifact write failed (kind=$kind)"
  fi
}

_parse_body_arg() {
  # Sets global _BODY from --body VAL or remaining single positional.
  _BODY=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --body) _BODY="${2:-}"; shift 2 ;;
      --) shift; _BODY="${*}"; break ;;
      *)
        if [ -z "$_BODY" ]; then
          _BODY="$1"
          shift
        else
          die "unexpected arg: $1"
        fi
        ;;
    esac
  done
}

# --- append-ideate <root> <UR-NNN> --body TEXT ---
cmd_append_ideate() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "append-ideate: usage: append-ideate <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "append-ideate: --body required"
  require_sqlite3
  local db ur_id now brief_before brief_after
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "append-ideate: unknown UR slug: $slug"
  brief_before="$(sqlite3 "$db" "SELECT brief FROM urs WHERE id=$ur_id;")"
  now="$(iso_now)"
  _artifact_write "$db" "$ur_id" "ideate" "append" "$_BODY" "$now"
  brief_after="$(sqlite3 "$db" "SELECT brief FROM urs WHERE id=$ur_id;")"
  [ "$brief_before" = "$brief_after" ] || die "append-ideate: brief mutated (bug)"
}

# --- append-clarifications <root> <UR-NNN> --body TEXT ---
cmd_append_clarifications() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "append-clarifications: usage: append-clarifications <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "append-clarifications: --body required"
  require_sqlite3
  local db ur_id now
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "append-clarifications: unknown UR slug: $slug"
  now="$(iso_now)"
  _artifact_write "$db" "$ur_id" "clarifications" "append" "$_BODY" "$now"
}

# --- write-verify <root> <UR-NNN> --body TEXT ---
cmd_write_verify() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "write-verify: usage: write-verify <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "write-verify: --body required"
  require_sqlite3
  local db ur_id now
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "write-verify: unknown UR slug: $slug"
  now="$(iso_now)"
  _artifact_write "$db" "$ur_id" "verify" "replace" "$_BODY" "$now"
}

# --- write-close <root> <UR-NNN> --body TEXT ---
# Replace close artifact and set urs.closed_at (first close time preserved).
cmd_write_close() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "write-close: usage: write-close <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "write-close: --body required"
  require_sqlite3
  local db ur_id now body_q now_q
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "write-close: unknown UR slug: $slug"
  now="$(iso_now)"
  body_q="$(sql_quote "$_BODY")"
  now_q="$(sql_quote "$now")"
  sqlite3 "$db" >/dev/null <<SQL || die "write-close: transaction failed"
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
INSERT INTO ur_artifacts(ur_id, kind, body, updated_at)
VALUES($ur_id, 'close', $body_q, $now_q)
ON CONFLICT(ur_id, kind) DO UPDATE SET
  body = excluded.body,
  updated_at = excluded.updated_at;
UPDATE urs SET closed_at = COALESCE(closed_at, $now_q) WHERE id=$ur_id;
COMMIT;
SQL
}

# --- write-open-gaps / write-capture-summary (replace kinds; helpers for agents) ---
cmd_write_open_gaps() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "write-open-gaps: usage: write-open-gaps <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "write-open-gaps: --body required"
  require_sqlite3
  local db ur_id now
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "write-open-gaps: unknown UR slug: $slug"
  now="$(iso_now)"
  _artifact_write "$db" "$ur_id" "open_gaps" "replace" "$_BODY" "$now"
}

cmd_write_capture_summary() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "write-capture-summary: usage: write-capture-summary <root> <UR-NNN> --body TEXT"
  _parse_body_arg "$@"
  [ -n "$_BODY" ] || die "write-capture-summary: --body required"
  require_sqlite3
  local db ur_id now
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "write-capture-summary: unknown UR slug: $slug"
  now="$(iso_now)"
  _artifact_write "$db" "$ur_id" "capture_summary" "replace" "$_BODY" "$now"
}

# --- append-decision <root> <line> ---
cmd_append_decision() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "append-decision: usage: append-decision <root> <line>"
  local line="$*"
  [ -n "$line" ] || die "append-decision: decision line required"
  require_sqlite3
  local db now
  db="$(open_db "$root")"
  now="$(iso_now)"
  sql_exec "$db" "INSERT INTO decisions(line, created_at) VALUES($(sql_quote "$line"), $(sql_quote "$now"));" \
    || die "append-decision: insert failed"
}

# --- write-calibration <root> --body TEXT ---
cmd_write_calibration() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "write-calibration: usage: write-calibration <root> --body TEXT"
  _parse_body_arg "$@"
  # allow empty body (clear)
  require_sqlite3
  local db now
  db="$(open_db "$root")"
  now="$(iso_now)"
  sql_exec "$db" "
INSERT INTO calibration(id, body, updated_at) VALUES(1, $(sql_quote "$_BODY"), $(sql_quote "$now"))
ON CONFLICT(id) DO UPDATE SET body=excluded.body, updated_at=excluded.updated_at;
" || die "write-calibration failed"
}

# --- read-calibration <root> ---
cmd_read_calibration() {
  local root="${1:-}"
  [ -n "$root" ] || die "read-calibration: usage: read-calibration <root>"
  require_sqlite3
  local db
  db="$(open_db "$root")"
  sqlite3 "$db" "SELECT COALESCE(body,'') FROM calibration WHERE id=1;"
}

# --- set-active-milestone <root> <UR-NNN> <M1|''> [--checklist JSON] ---
cmd_set_active_milestone() {
  local root="${1:-}" slug="${2:-}" active="${3:-}"; shift 3 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "set-active-milestone: usage: set-active-milestone <root> <UR-NNN> <M1|''> [--checklist JSON]"
  local checklist=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --checklist) checklist="${2:-}"; shift 2 ;;
      *) die "set-active-milestone: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db ur_id active_sql checklist_sql
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "set-active-milestone: unknown UR slug: $slug"
  if [ -z "$active" ]; then
    active_sql="NULL"
  else
    active_sql="$(sql_quote "$active")"
  fi
  checklist_sql="$(sql_quote "$checklist")"
  sql_exec "$db" "
INSERT INTO milestone_state(ur_id, active, checklist_json)
VALUES($ur_id, $active_sql, $checklist_sql)
ON CONFLICT(ur_id) DO UPDATE SET
  active = excluded.active,
  checklist_json = CASE
    WHEN excluded.checklist_json = '' THEN milestone_state.checklist_json
    ELSE excluded.checklist_json
  END;
" || die "set-active-milestone failed"
}

# --- get-active-milestone <root> <UR-NNN> ---
# Prints active id or empty line when none.
cmd_get_active_milestone() {
  local root="${1:-}" slug="${2:-}"
  [ -n "$root" ] && [ -n "$slug" ] || die "get-active-milestone: usage: get-active-milestone <root> <UR-NNN>"
  require_sqlite3
  local db ur_id
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "get-active-milestone: unknown UR slug: $slug"
  ur_active_milestone "$db" "$ur_id"
}

# --- list-milestone-reqs <root> <UR-NNN> [--milestone M1] ---
# Defaults to that UR's active milestone; empty active → empty list.
cmd_list_milestone_reqs() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "list-milestone-reqs: usage: list-milestone-reqs <root> <UR-NNN> [--milestone M1]"
  local milestone=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --milestone) milestone="${2:-}"; shift 2 ;;
      *) die "list-milestone-reqs: unknown arg: $1" ;;
    esac
  done
  require_sqlite3
  local db ur_id
  db="$(open_db "$root")"
  ur_id="$(ur_id_for_slug "$db" "$slug")"
  [ -n "$ur_id" ] || die "list-milestone-reqs: unknown UR slug: $slug"
  if [ -z "$milestone" ]; then
    milestone="$(ur_active_milestone "$db" "$ur_id")"
  fi
  if [ -z "$milestone" ]; then
    return 0
  fi
  sqlite3 -separator $'\t' "$db" "
SELECT r.slug, r.title, r.status, COALESCE(r.path_milestone,'')
FROM reqs r
WHERE r.ur_id = $ur_id AND r.path_milestone = $(sql_quote "$milestone")
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;"
}

# --- append-run-note <root> <REQ-NNN> --payload TEXT ---
cmd_append_run_note() {
  local root="${1:-}" slug="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$root" ] && [ -n "$slug" ] || die "append-run-note: usage: append-run-note <root> <REQ-NNN> --payload TEXT"
  local payload=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --payload) payload="${2:-}"; shift 2 ;;
      --body) payload="${2:-}"; shift 2 ;;
      *)
        if [ -z "$payload" ]; then
          payload="$1"; shift
        else
          die "append-run-note: unknown arg: $1"
        fi
        ;;
    esac
  done
  [ -n "$payload" ] || die "append-run-note: --payload required"
  require_sqlite3
  local db rid now
  db="$(open_db "$root")"
  rid="$(req_id_for_slug "$db" "$slug")"
  [ -n "$rid" ] || die "append-run-note: unknown REQ slug: $slug"
  now="$(iso_now)"
  sql_exec "$db" "INSERT INTO run_notes(req_id, payload, created_at)
VALUES($rid, $(sql_quote "$payload"), $(sql_quote "$now"));" \
    || die "append-run-note: insert failed"
}

# Derive proven|unproven for one REQ (parity with derive-status.sh + suite not-run).
# Args: status proof suite → prints proven|unproven
_derive_req_state() {
  local status="$1"
  local proof="$2"
  local suite="$3"
  if [ "$status" = "done" ] && [ -n "$proof" ] && [ "$suite" != "not-run" ]; then
    printf 'proven\n'
  else
    printf 'unproven\n'
  fi
}

# --- status-synth <root> [UR-NNN|--ur UR-NNN] ---
# Folds markdown synth-status + derive-status + coverage-rollup (+ closed).
# Never globs REQ-*.md / user-requests/; DB only.
cmd_status_synth() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "status-synth: usage: status-synth <root> [UR-NNN]"
  local ur_filter=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ur) ur_filter="${2:-}"; shift 2 ;;
      UR-*|ur-*)
        ur_filter="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
        shift
        ;;
      *) die "status-synth: unknown arg: $1" ;;
    esac
  done

  require_sqlite3
  local db
  db="$(open_db "$root")"

  local n_backlog n_ip n_stopped n_done
  if [ -n "$ur_filter" ]; then
    local uid
    uid="$(ur_id_for_slug "$db" "$ur_filter")"
    if [ -z "$uid" ]; then
      printf 'Totals: backlog=0 in_progress=0 stopped=0 done=0\n\n'
      printf 'no REQs for %s\n' "$ur_filter"
      return 0
    fi
    n_backlog="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$ur_filter") AND r.status='backlog';")"
    n_ip="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$ur_filter") AND r.status='in_progress';")"
    n_stopped="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$ur_filter") AND r.status='stopped';")"
    n_done="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$ur_filter") AND r.status='done';")"
  else
    n_backlog="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs WHERE status='backlog';")"
    n_ip="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs WHERE status='in_progress';")"
    n_stopped="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs WHERE status='stopped';")"
    n_done="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs WHERE status='done';")"
  fi

  printf 'Totals: backlog=%s in_progress=%s stopped=%s done=%s\n\n' \
    "${n_backlog:-0}" "${n_ip:-0}" "${n_stopped:-0}" "${n_done:-0}"

  local total
  total=$(( ${n_backlog:-0} + ${n_ip:-0} + ${n_stopped:-0} + ${n_done:-0} ))
  if [ "$total" -eq 0 ]; then
    printf 'no REQs captured yet.\n'
    return 0
  fi

  printf '## Situation\n'
  printf '| REQ | UR | Status | Layer | Claimer | Heartbeat-age | Footprint |\n'
  printf '|-----|----|--------|-------|---------|---------------|----------|\n'

  local rows sep
  sep=$'\x1e'
  if [ -n "$ur_filter" ]; then
    rows="$(sqlite3 -separator "$sep" "$db" "
SELECT r.slug, u.slug, r.status, COALESCE(r.layer,''), COALESCE(r.files,''),
       COALESCE(c.agent_id,''), COALESCE(c.heartbeat,''),
       TRIM(COALESCE(r.closure_proof,'')), COALESCE(r.suite,'')
FROM reqs r
JOIN urs u ON u.id=r.ur_id
LEFT JOIN claims c ON c.req_id=r.id AND c.status='active'
WHERE u.slug=$(sql_quote "$ur_filter")
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;")"
  else
    rows="$(sqlite3 -separator "$sep" "$db" "
SELECT r.slug, u.slug, r.status, COALESCE(r.layer,''), COALESCE(r.files,''),
       COALESCE(c.agent_id,''), COALESCE(c.heartbeat,''),
       TRIM(COALESCE(r.closure_proof,'')), COALESCE(r.suite,'')
FROM reqs r
JOIN urs u ON u.id=r.ur_id
LEFT JOIN claims c ON c.req_id=r.id AND c.status='active'
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;")"
  fi

  local proven_lines="" coverage_tmp
  coverage_tmp="$(mktemp -t dw-status-cov.XXXXXX)"

  local rslug rur rstatus rlayer rfiles ragent rhb rproof rsuite
  local display_status claimer hb_age age fp derived pathunit
  while IFS="$sep" read -r rslug rur rstatus rlayer rfiles ragent rhb rproof rsuite; do
    [ -n "${rslug:-}" ] || continue
    display_status="$rstatus"
    [ "$display_status" = "in_progress" ] && display_status="in-progress"

    claimer="—"
    hb_age="—"
    if [ -n "$ragent" ]; then
      claimer="$ragent"
      if [ -z "$rhb" ]; then
        hb_age="? (STALE)"
      else
        age="$(heartbeat_age_secs "$rhb" 2>/dev/null || true)"
        if [ -z "${age:-}" ]; then
          hb_age="? (STALE)"
        elif [ "$age" -ge "$DEFAULT_STALE_MAX" ]; then
          hb_age="${age}s (STALE)"
        else
          hb_age="${age}s"
        fi
      fi
    fi

    fp="$rfiles"
    if [ -z "$fp" ]; then
      fp="—"
    elif [ "${#fp}" -gt 60 ]; then
      fp="${fp:0:59}…"
    fi
    fp="${fp//$'\n'/ }"
    fp="${fp//|/\\|}"
    [ -n "$rlayer" ] || rlayer="—"

    printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
      "$rslug" "$rur" "$display_status" "$rlayer" "$claimer" "$hb_age" "$fp"

    derived="$(_derive_req_state "$rstatus" "$rproof" "$rsuite")"
    proven_lines="${proven_lines}${rslug} ${derived}"$'\n'

    pathunit=0
    [ "$rlayer" = "none" ] && pathunit=1
    printf 'ROW %s %s %s %s\n' "$rur" "$rslug" "$derived" "$pathunit" >> "$coverage_tmp"
  done <<EOF
$rows
EOF

  printf '\n## Proven\n'
  if [ -n "$proven_lines" ]; then
    printf '%s' "$proven_lines"
  else
    printf '(none)\n'
  fi

  local ur_list ur_slug overall closed_at has_close
  if [ -n "$ur_filter" ]; then
    ur_list="$ur_filter"
  else
    ur_list="$(awk '$1=="ROW" { print $2 }' "$coverage_tmp" 2>/dev/null | sort -u)"
  fi

  for ur_slug in $ur_list; do
    [ -n "$ur_slug" ] || continue
    closed_at="$(sqlite3 "$db" "SELECT COALESCE(closed_at,'') FROM urs WHERE slug=$(sql_quote "$ur_slug");")"
    has_close="$(sqlite3 "$db" "
SELECT COUNT(*) FROM ur_artifacts a
JOIN urs u ON u.id=a.ur_id
WHERE u.slug=$(sql_quote "$ur_slug") AND a.kind='close';")"
    if [ -n "$closed_at" ] || [ "${has_close:-0}" -gt 0 ]; then
      overall="closed"
    else
      overall="__none__"
    fi
    printf 'CLOSURE %s %s\n' "$ur_slug" "$overall" >> "$coverage_tmp"
  done

  printf '\n## Coverage\n'
  if [ ! -s "$coverage_tmp" ] || ! grep -q '^ROW ' "$coverage_tmp" 2>/dev/null; then
    printf 'Coverage: no REQs captured yet.\n'
    rm -f "$coverage_tmp"
    return 0
  fi

  awk '
$1 == "CLOSURE" {
  overall[$2] = $3
  next
}
$1 == "ROW" {
  ur=$2; id=$3; state=$4; pathunit=$5
  if (!(ur in seen)) { order[++n]=ur; seen[ur]=1 }
  intended[ur]++
  if (pathunit == 1) has_pathunit[ur]=1
  if (state == "proven") {
    proven[ur]++
  } else {
    unproven[ur]++
    if (unproven_ids[ur] == "") unproven_ids[ur]=id
    else unproven_ids[ur]=unproven_ids[ur] "," id
  }
}
END {
  for (i=1; i<=n; i++) {
    ur=order[i]
    printf "%s intended=%d proven=%d unproven=%d", ur, intended[ur]+0, proven[ur]+0, unproven[ur]+0
    if ((unproven[ur]+0) > 0) printf " unproven_ids=%s", unproven_ids[ur]
    if (!(ur in has_pathunit)) {
      closed = "n/a"
    } else if (overall[ur] == "closed") {
      closed = "yes"
    } else {
      closed = "no"
    }
    printf " closed=%s\n", closed
  }
}
' "$coverage_tmp"
  rm -f "$coverage_tmp"
}

# --- board <root> [--path PATH] [--stale-max N] ---
# Write self-contained static HTML snapshot. Explicit regen only (not claim/archive).
# Prints absolute path of written file on stdout.
cmd_board() {
  local root="${1:-}"; shift || true
  [ -n "$root" ] || die "board: usage: board <root> [--path PATH] [--stale-max N]"
  local out_path="" stale_max="$DEFAULT_STALE_MAX"
  while [ $# -gt 0 ]; do
    case "$1" in
      --path)
        out_path="${2:-}"
        [ -n "$out_path" ] || die "board: --path requires a value"
        shift 2 ;;
      --stale-max)
        case "${2:-}" in
          ''|*[!0-9]*) die "board: --stale-max must be positive integer" ;;
        esac
        stale_max="$2"
        shift 2 ;;
      *) die "board: unknown arg: $1" ;;
    esac
  done

  require_sqlite3
  local db
  db="$(open_db "$root")"

  if [ -z "$out_path" ]; then
    out_path="$root/.do-work/board/index.html"
  else
    case "$out_path" in
      /*) : ;;
      *) out_path="$root/$out_path" ;;
    esac
  fi

  local gen_at project_name
  gen_at="$(iso_now)"
  project_name="$(basename "$root")"

  local sep
  sep=$'\x1e'

  # Stale active claims for banner
  local stale_lines="" stale_count=0
  local s_slug s_agent s_hb s_age
  local stale_rows
  stale_rows="$(sqlite3 -separator "$sep" "$db" "
SELECT r.slug, c.agent_id, c.heartbeat
FROM claims c JOIN reqs r ON r.id=c.req_id
WHERE c.status='active'
ORDER BY r.slug;")"
  while IFS="$sep" read -r s_slug s_agent s_hb; do
    [ -n "${s_slug:-}" ] || continue
    if is_stale_heartbeat "$s_hb" "$stale_max"; then
      s_age="$(heartbeat_age_secs "$s_hb" 2>/dev/null || true)"
      [ -n "${s_age:-}" ] || s_age="unknown"
      stale_count=$((stale_count + 1))
      stale_lines="${stale_lines}<li><code>$(html_escape "$s_slug")</code> claimer=$(html_escape "$s_agent") age=${s_age}s heartbeat=$(html_escape "$s_hb")</li>"
    fi
  done <<EOF
$stale_rows
EOF

  # UR rows with REQ counts
  local ur_rows_html=""
  local ur_lines u_slug u_title u_class u_created u_closed
  local n_req n_backlog n_ip n_done
  ur_lines="$(sqlite3 -separator "$sep" "$db" "
SELECT slug, title, class, created_at, COALESCE(closed_at,'')
FROM urs
ORDER BY CAST(substr(slug, instr(slug,'-')+1) AS INTEGER) ASC;")"
  if [ -z "${ur_lines:-}" ]; then
    ur_rows_html='<tr><td colspan="7" class="empty">No user requests yet.</td></tr>'
  else
    while IFS="$sep" read -r u_slug u_title u_class u_created u_closed; do
      [ -n "${u_slug:-}" ] || continue
      n_req="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$u_slug");")"
      n_backlog="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$u_slug") AND r.status='backlog';")"
      n_ip="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$u_slug") AND r.status='in_progress';")"
      n_done="$(sqlite3 "$db" "SELECT COUNT(*) FROM reqs r JOIN urs u ON u.id=r.ur_id WHERE u.slug=$(sql_quote "$u_slug") AND r.status='done';")"
      ur_rows_html="${ur_rows_html}<tr>
<td><code>$(html_escape "$u_slug")</code></td>
<td>$(html_escape "$u_title")</td>
<td>$(html_escape "$u_class")</td>
<td>${n_req:-0}</td>
<td>${n_backlog:-0}</td>
<td>${n_ip:-0}</td>
<td>${n_done:-0}</td>
</tr>"
    done <<EOF
$ur_lines
EOF
  fi

  # REQ rows with claimer + heartbeat age
  local req_rows_html=""
  local req_lines r_slug r_ur r_title r_status r_layer r_agent r_hb
  local display_status claimer hb_cell age stale_class
  req_lines="$(sqlite3 -separator "$sep" "$db" "
SELECT r.slug, u.slug, r.title, r.status, COALESCE(r.layer,''),
       COALESCE(c.agent_id,''), COALESCE(c.heartbeat,'')
FROM reqs r
JOIN urs u ON u.id=r.ur_id
LEFT JOIN claims c ON c.req_id=r.id AND c.status='active'
ORDER BY CAST(substr(r.slug, instr(r.slug,'-')+1) AS INTEGER) ASC;")"
  if [ -z "${req_lines:-}" ]; then
    req_rows_html='<tr><td colspan="7" class="empty">No REQs yet.</td></tr>'
  else
    while IFS="$sep" read -r r_slug r_ur r_title r_status r_layer r_agent r_hb; do
      [ -n "${r_slug:-}" ] || continue
      display_status="$r_status"
      [ "$display_status" = "in_progress" ] && display_status="in-progress"
      claimer="—"
      hb_cell="—"
      stale_class=""
      if [ -n "$r_agent" ]; then
        claimer="$(html_escape "$r_agent")"
        if [ -z "$r_hb" ]; then
          hb_cell="? (STALE)"
          stale_class=" stale"
        else
          age="$(heartbeat_age_secs "$r_hb" 2>/dev/null || true)"
          if [ -z "${age:-}" ]; then
            hb_cell="? (STALE)"
            stale_class=" stale"
          elif [ "$age" -gt "$stale_max" ]; then
            hb_cell="${age}s (STALE)"
            stale_class=" stale"
          else
            hb_cell="${age}s"
          fi
        fi
      fi
      [ -n "$r_layer" ] || r_layer="—"
      req_rows_html="${req_rows_html}<tr class=\"status-$(html_escape "$r_status")${stale_class}\">
<td><code>$(html_escape "$r_slug")</code></td>
<td><code>$(html_escape "$r_ur")</code></td>
<td>$(html_escape "$r_title")</td>
<td>$(html_escape "$display_status")</td>
<td>$(html_escape "$r_layer")</td>
<td>${claimer}</td>
<td>${hb_cell}</td>
</tr>"
    done <<EOF
$req_lines
EOF
  fi

  local stale_banner=""
  if [ "$stale_count" -gt 0 ]; then
    stale_banner="<div class=\"banner stale-banner\" role=\"alert\"><strong>Stale claims (${stale_count})</strong> — heartbeat older than ${stale_max}s<ul>${stale_lines}</ul></div>"
  fi

  local out_dir esc_project esc_gen
  out_dir="$(dirname "$out_path")"
  mkdir -p "$out_dir"
  esc_project="$(html_escape "$project_name")"
  esc_gen="$(html_escape "$gen_at")"

  # Emit with quoted heredocs + printf so user titles cannot re-expand ($ ` etc.).
  {
    cat <<'HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>do-work board — 
HEAD
    printf '%s' "$esc_project"
    cat <<'HEAD2'
</title>
<style>
  :root { --bg:#0f1419; --fg:#e7ecf1; --muted:#8b9aab; --card:#1a2332; --border:#2a3544;
          --accent:#3d8bfd; --stale:#f0a030; --backlog:#6b7c8f; --ip:#3d8bfd; --done:#3ecf8e; --stopped:#e85d5d; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
         background:var(--bg); color:var(--fg); line-height:1.45; padding:1.5rem; }
  h1 { font-size:1.4rem; margin:0 0 .25rem; }
  h2 { font-size:1.1rem; margin:1.5rem 0 .5rem; border-bottom:1px solid var(--border); padding-bottom:.25rem; }
  .meta { color:var(--muted); font-size:.9rem; margin-bottom:1rem; }
  .meta code { color:var(--fg); }
  .banner { background:#3a2a10; border:1px solid var(--stale); border-radius:6px; padding:.75rem 1rem; margin:1rem 0; }
  .banner ul { margin:.5rem 0 0; padding-left:1.2rem; }
  table { width:100%; border-collapse:collapse; background:var(--card); border-radius:8px; overflow:hidden;
          font-size:.9rem; margin-bottom:1rem; }
  th, td { text-align:left; padding:.5rem .65rem; border-bottom:1px solid var(--border); vertical-align:top; }
  th { background:#121a26; color:var(--muted); font-weight:600; font-size:.8rem; text-transform:uppercase; letter-spacing:.03em; }
  tr:last-child td { border-bottom:none; }
  tr.stale td { background:rgba(240,160,48,.08); }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size:.85em; }
  .empty { color:var(--muted); font-style:italic; }
  .foot { color:var(--muted); font-size:.8rem; margin-top:2rem; }
</style>
</head>
<body>
<header>
  <h1>do-work board</h1>
  <div class="meta">
    project=<code>
HEAD2
    printf '%s' "$esc_project"
    cat <<'HEAD3'
</code>
    · backend=<code>sqlite</code>
    · generated_at=<code>
HEAD3
    printf '%s' "$esc_gen"
    printf '</code>\n    · stale_max=%ss\n  </div>\n</header>\n' "$stale_max"
    # stale_banner already built from escaped fragments; print raw (no re-expand)
    printf '%s\n' "$stale_banner"
    cat <<'MID'
<section>
  <h2>User requests</h2>
  <table>
    <thead><tr><th>UR</th><th>Title</th><th>Class</th><th>REQs</th><th>Backlog</th><th>In progress</th><th>Done</th></tr></thead>
    <tbody>
MID
    printf '%s\n' "$ur_rows_html"
    cat <<'MID2'
    </tbody>
  </table>
</section>
<section>
  <h2>REQs</h2>
  <table>
    <thead><tr><th>REQ</th><th>UR</th><th>Title</th><th>Status</th><th>Layer</th><th>Claimer</th><th>Heartbeat age</th></tr></thead>
    <tbody>
MID2
    printf '%s\n' "$req_rows_html"
    cat <<'TAIL'
    </tbody>
  </table>
</section>
<p class="foot">Static snapshot — regenerate with <code>/do-work board</code> (or <code>dw-db.sh board</code>). Not updated by claim/archive.</p>
</body>
</html>
TAIL
  } > "$out_path"

  printf '%s\n' "$out_path"
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
    claim) cmd_claim "$@" ;;
    heartbeat) cmd_heartbeat "$@" ;;
    unblock) cmd_unblock "$@" ;;
    check-deps) cmd_check_deps "$@" ;;
    cycle-check) cmd_cycle_check "$@" ;;
    check-footprint) cmd_check_footprint "$@" ;;
    scan-stale) cmd_scan_stale "$@" ;;
    check-archive) cmd_check_archive "$@" ;;
    archive-req) cmd_archive_req "$@" ;;
    list-claimable) cmd_list_claimable "$@" ;;
    pick) cmd_pick "$@" ;;
    append-ideate) cmd_append_ideate "$@" ;;
    append-clarifications) cmd_append_clarifications "$@" ;;
    write-verify) cmd_write_verify "$@" ;;
    write-close) cmd_write_close "$@" ;;
    write-open-gaps) cmd_write_open_gaps "$@" ;;
    write-capture-summary) cmd_write_capture_summary "$@" ;;
    append-decision) cmd_append_decision "$@" ;;
    write-calibration) cmd_write_calibration "$@" ;;
    read-calibration) cmd_read_calibration "$@" ;;
    set-active-milestone) cmd_set_active_milestone "$@" ;;
    get-active-milestone) cmd_get_active_milestone "$@" ;;
    list-milestone-reqs) cmd_list_milestone_reqs "$@" ;;
    append-run-note) cmd_append_run_note "$@" ;;
    status-synth) cmd_status_synth "$@" ;;
    board) cmd_board "$@" ;;
    "") die "usage: dw-db.sh <command> ..." ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
