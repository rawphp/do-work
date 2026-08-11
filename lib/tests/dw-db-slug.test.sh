#!/usr/bin/env bash
# dw-db-slug.test.sh — numeric slug allocation (never string MAX(slug)).
# After UR-9, next must be UR-010 (9+1, min width 3).
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW="$LIB_DIR/dw-db.sh"
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED+1)); }

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 not installed"
  exit 0
fi

TMP="$(mktemp -d -t dw-slug.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

# Sequential alloc from empty: UR-001, UR-002, UR-003
u1="$(bash "$DW" create-ur "$TMP" --title t1 --brief b1)" || fail "create-ur 1 failed"
u2="$(bash "$DW" create-ur "$TMP" --title t2 --brief b2)" || fail "create-ur 2 failed"
u3="$(bash "$DW" create-ur "$TMP" --title t3 --brief b3)" || fail "create-ur 3 failed"
[ "$u1" = "UR-001" ] || fail "want UR-001 got $u1"
[ "$u2" = "UR-002" ] || fail "want UR-002 got $u2"
[ "$u3" = "UR-003" ] || fail "want UR-003 got $u3"

# Force a high numeric suffix without zero-pad (proves numeric max, not string MAX)
sqlite3 "$db" "INSERT INTO urs(slug,title,class,brief,created_at) VALUES('UR-9','x','','b','2026-01-01');"
next="$(bash "$DW" create-ur "$TMP" --title t --brief brief)" || fail "create-ur after UR-9 failed"
# Want UR-010 (9+1, width >= 3) — NOT UR-10 or lexicographic wrong
[ "$next" = "UR-010" ] || fail "got $next want UR-010 (numeric max after UR-9)"

# REQ side: empty → REQ-001; after manual REQ-9 → REQ-010
ur="$(bash "$DW" create-ur "$TMP" --title for-req --brief br)"
r1="$(bash "$DW" create-req "$TMP" --ur "$ur" --title rt1)" || fail "create-req 1 failed"
[ "$r1" = "REQ-001" ] || fail "want REQ-001 got $r1"
sqlite3 "$db" "INSERT INTO reqs(slug,ur_id,title,status,created_at,updated_at)
  SELECT 'REQ-9', id, 'x', 'backlog', '2026-01-01', '2026-01-01' FROM urs WHERE slug='$ur';"
rnext="$(bash "$DW" create-req "$TMP" --ur "$ur" --title rt2)" || fail "create-req after REQ-9 failed"
[ "$rnext" = "REQ-010" ] || fail "got $rnext want REQ-010"

# Width grows past 3: after forcing max suffix 999, next is REQ-1000
sqlite3 "$db" "INSERT INTO reqs(slug,ur_id,title,status,created_at,updated_at)
  SELECT 'REQ-999', id, 'x', 'backlog', '2026-01-01', '2026-01-01' FROM urs WHERE slug='$ur';"
rbig="$(bash "$DW" create-req "$TMP" --ur "$ur" --title rt3)" || fail "create-req after REQ-999 failed"
[ "$rbig" = "REQ-1000" ] || fail "got $rbig want REQ-1000 (width grows past 3)"

rm -rf "$TMP"
[ "$FAILED" -eq 0 ] || exit 1
echo "PASS dw-db-slug"
