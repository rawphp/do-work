#!/usr/bin/env bash
# dw-db-pick.test.sh — list-claimable order, pick head, filters (deps/footprint/milestone).
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

TMP="$(mktemp -d -t dw-pick.XXXXXX)"
mkdir -p "$TMP/.do-work" "$TMP/lib"
echo "x" > "$TMP/lib/a.sh"
echo "y" > "$TMP/lib/b.sh"
echo "z" > "$TMP/lib/c.sh"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

ur="$(bash "$DW" create-ur "$TMP" --title "Pick UR" --brief "b")" || {
  fail "create-ur"; rm -rf "$TMP"; exit 1
}

# Create REQs with different priorities / order.
# Insert order: low-pri first, then high, then default (null→2), then mid.
# Forced created_at so numeric/created tie-breaks are stable.
r_low="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Low" --priority 1 --files "lib/a.sh")" || fail "r_low"
r_high="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "High" --priority 3 --files "lib/b.sh")" || fail "r_high"
r_null="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Null pri" --files "lib/c.sh")" || fail "r_null"
# second priority-2 with higher numeric id
r_mid="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Mid2" --priority 2 --files "lib/a.sh")" || fail "r_mid"

# Ensure created_at ordering: set r_null earlier than r_mid (both effective pri 2)
sqlite3 "$db" "UPDATE reqs SET created_at='2026-01-01T00:00:00Z' WHERE slug='$r_null';"
sqlite3 "$db" "UPDATE reqs SET created_at='2026-01-02T00:00:00Z' WHERE slug='$r_mid';"
sqlite3 "$db" "UPDATE reqs SET created_at='2026-01-01T00:00:00Z' WHERE slug='$r_low';"
sqlite3 "$db" "UPDATE reqs SET created_at='2026-01-01T00:00:00Z' WHERE slug='$r_high';"

# Expected order: priority DESC → high(3), null(2)/mid(2) by numeric ASC, low(1)
# Numeric: r_low=REQ-001, r_high=REQ-002, r_null=REQ-003, r_mid=REQ-004
# So: REQ-002 (3), REQ-003 (null→2), REQ-004 (2), REQ-001 (1)
list="$(bash "$DW" list-claimable "$TMP" 2>/dev/null)" || { fail "list-claimable failed"; list=""; }
first_line="$(printf '%s\n' "$list" | head -1)"
[ "$first_line" = "$r_high" ] || fail "list-claimable head want $r_high got $first_line"
# full order
expect_order="$r_high
$r_null
$r_mid
$r_low"
# Normalize trailing newlines
got_order="$(printf '%s\n' "$list" | sed '/^$/d')"
expect_n="$(printf '%s\n' "$expect_order")"
[ "$got_order" = "$expect_n" ] || fail "list-claimable order
want:
$expect_n
got:
$got_order"

# pick = first of list
picked="$(bash "$DW" pick "$TMP" 2>/dev/null)" || { fail "pick failed"; picked=""; }
[ "$picked" = "$r_high" ] || fail "pick want $r_high got $picked"
[ "$picked" = "$first_line" ] || fail "pick head must match list-claimable head"

# --- dep filter: blocked when dep not done ---
ur2="$(bash "$DW" create-ur "$TMP" --title "UR2" --brief "b2")" || fail "ur2"
dep="$(bash "$DW" create-req "$TMP" --ur "$ur2" --title "Dep not done" --priority 3 --files "lib/dep.sh")" || fail "dep"
blocked="$(bash "$DW" create-req "$TMP" --ur "$ur2" --title "Blocked high" --priority 3 --deps "$dep" --files "lib/only.sh")" || fail "blocked"
list2="$(bash "$DW" list-claimable "$TMP" --ur "$ur2" 2>/dev/null || true)"
case "$list2" in
  *"$blocked"*) fail "blocked REQ should not be claimable while dep open: $list2" ;;
esac
# dep itself is claimable
case "$list2" in
  *"$dep"*) : ;;
  *) fail "dep REQ should be claimable: $list2" ;;
esac
bash "$DW" set-status "$TMP" "$dep" done || fail "mark dep done"
list3="$(bash "$DW" list-claimable "$TMP" --ur "$ur2" 2>/dev/null || true)"
case "$list3" in
  *"$blocked"*) : ;;
  *) fail "after dep done, blocked should be claimable: $list3" ;;
esac

# --- footprint filter: skip when overlap with in-flight ---
# claim r_high (holds lib/b.sh) — nothing else has b, so others remain
bash "$DW" claim "$TMP" "$r_high" "agent-P" 2>/dev/null || fail "claim high"
# Create another with same files as in-flight
overlap="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Overlap high files" --priority 3 --files "lib/b.sh")" || fail "overlap"
list4="$(bash "$DW" list-claimable "$TMP" --ur "$ur" 2>/dev/null || true)"
case "$list4" in
  *"$overlap"*) fail "overlap REQ should not be claimable: $list4" ;;
esac
# claimed r_high itself not in list (not backlog)
case "$list4" in
  *"$r_high"*) fail "in_progress claimed REQ should not list: $list4" ;;
esac

# --- milestone filter (scoped --ur) ---
ur3="$(bash "$DW" create-ur "$TMP" --title "UR3" --brief "b3")" || fail "ur3"
# set active milestone M2 for ur3 via SQL (set-active-milestone may be Task 5)
uid3="$(sqlite3 "$db" "SELECT id FROM urs WHERE slug='$ur3';")"
sqlite3 "$db" "INSERT INTO milestone_state(ur_id, active, checklist_json) VALUES($uid3, 'M2', '');"
rm1="$(bash "$DW" create-req "$TMP" --ur "$ur3" --title "M1 only" --path-milestone M1 --priority 3)" || fail "rm1"
rm2="$(bash "$DW" create-req "$TMP" --ur "$ur3" --title "M2 match" --path-milestone M2 --priority 1)" || fail "rm2"
rm0="$(bash "$DW" create-req "$TMP" --ur "$ur3" --title "No milestone" --priority 3)" || fail "rm0"
list_m="$(bash "$DW" list-claimable "$TMP" --ur "$ur3" 2>/dev/null || true)"
case "$list_m" in
  *"$rm2"*) : ;;
  *) fail "M2 REQ should be claimable under active M2: $list_m" ;;
esac
case "$list_m" in
  *"$rm1"*) fail "M1 REQ should be filtered out: $list_m" ;;
esac
case "$list_m" in
  *"$rm0"*) fail "null path_milestone should be filtered when cursor active: $list_m" ;;
esac

# --- pick empty when nothing claimable ---
# claim the only remaining claimable on ur3
bash "$DW" claim "$TMP" "$rm2" "agent-M" 2>/dev/null || fail "claim rm2"
set +e
bash "$DW" pick "$TMP" --ur "$ur3" >/dev/null 2>&1
pick_rc=$?
set -e
[ "$pick_rc" -eq 1 ] || fail "pick with no claimable want exit 1 got $pick_rc"

rm -rf "$TMP"

if [ "$FAILED" -ne 0 ]; then
  echo "dw-db-pick: $FAILED failure(s)" >&2
  exit 1
fi
echo "PASS dw-db-pick"
exit 0
