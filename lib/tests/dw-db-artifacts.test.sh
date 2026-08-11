#!/usr/bin/env bash
# dw-db-artifacts.test.sh — ideate/clarifications append, verify/close replace,
# decisions, calibration, milestones, run notes.
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

TMP="$(mktemp -d -t dw-art.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

ur="$(bash "$DW" create-ur "$TMP" --title "Art UR" --brief "ORIGINAL BRIEF")" \
  || { fail "create-ur"; rm -rf "$TMP"; exit 1; }

brief0="$(sqlite3 "$db" "SELECT brief FROM urs WHERE slug='$ur';")"
[ "$brief0" = "ORIGINAL BRIEF" ] || fail "fixture brief mismatch: $brief0"

# --- append-ideate: two appends grow body; brief unchanged ---
bash "$DW" append-ideate "$TMP" "$ur" --body "block one" \
  || fail "append-ideate first failed"
bash "$DW" append-ideate "$TMP" "$ur" --body "block two" \
  || fail "append-ideate second failed"

ideate_body="$(sqlite3 "$db" "SELECT body FROM ur_artifacts a
  JOIN urs u ON u.id=a.ur_id WHERE u.slug='$ur' AND a.kind='ideate';")"
case "$ideate_body" in
  *"block one"* ) : ;;
  *) fail "ideate missing block one: $ideate_body" ;;
esac
case "$ideate_body" in
  *"block two"* ) : ;;
  *) fail "ideate missing block two: $ideate_body" ;;
esac
# both present means append grew (not pure replace of only last)
len1="$(printf '%s' "$ideate_body" | wc -c | tr -d ' ')"
[ "$len1" -gt 15 ] || fail "ideate body too short after two appends: len=$len1"

brief1="$(sqlite3 "$db" "SELECT brief FROM urs WHERE slug='$ur';")"
[ "$brief1" = "ORIGINAL BRIEF" ] || fail "append-ideate must not modify urs.brief (got: $brief1)"

# --- append-clarifications: append semantics ---
bash "$DW" append-clarifications "$TMP" "$ur" --body "Q1: why?\nA1: because" \
  || fail "append-clarifications first failed"
bash "$DW" append-clarifications "$TMP" "$ur" --body "Q2: more?" \
  || fail "append-clarifications second failed"
clar="$(sqlite3 "$db" "SELECT body FROM ur_artifacts a
  JOIN urs u ON u.id=a.ur_id WHERE u.slug='$ur' AND a.kind='clarifications';")"
case "$clar" in
  *"Q1"* ) : ;;
  *) fail "clarifications missing Q1: $clar" ;;
esac
case "$clar" in
  *"Q2"* ) : ;;
  *) fail "clarifications missing Q2: $clar" ;;
esac

# --- write-verify: replace (second write overwrites first) ---
bash "$DW" write-verify "$TMP" "$ur" --body "verify v1" || fail "write-verify v1"
bash "$DW" write-verify "$TMP" "$ur" --body "verify v2 final" || fail "write-verify v2"
ver="$(sqlite3 "$db" "SELECT body FROM ur_artifacts a
  JOIN urs u ON u.id=a.ur_id WHERE u.slug='$ur' AND a.kind='verify';")"
[ "$ver" = "verify v2 final" ] || fail "write-verify replace want 'verify v2 final' got '$ver'"
case "$ver" in
  *"v1"* ) fail "write-verify should replace, not append v1: $ver" ;;
esac

# --- write-close: replace + sets closed_at ---
cl0="$(sqlite3 "$db" "SELECT COALESCE(closed_at,'') FROM urs WHERE slug='$ur';")"
[ -z "$cl0" ] || fail "closed_at should be empty before close (got: $cl0)"

bash "$DW" write-close "$TMP" "$ur" --body "closure report ok" || fail "write-close failed"
close_body="$(sqlite3 "$db" "SELECT body FROM ur_artifacts a
  JOIN urs u ON u.id=a.ur_id WHERE u.slug='$ur' AND a.kind='close';")"
[ "$close_body" = "closure report ok" ] || fail "close body want 'closure report ok' got '$close_body'"

cl1="$(sqlite3 "$db" "SELECT COALESCE(closed_at,'') FROM urs WHERE slug='$ur';")"
[ -n "$cl1" ] || fail "write-close must set urs.closed_at"
# ISO-ish
case "$cl1" in
  20[0-9][0-9]-*T* ) : ;;
  *) fail "closed_at not ISO-like: $cl1" ;;
esac

# replace close body; closed_at remains set
bash "$DW" write-close "$TMP" "$ur" --body "closure revised" || fail "write-close replace failed"
close_body2="$(sqlite3 "$db" "SELECT body FROM ur_artifacts a
  JOIN urs u ON u.id=a.ur_id WHERE u.slug='$ur' AND a.kind='close';")"
[ "$close_body2" = "closure revised" ] || fail "close replace body: $close_body2"
cl2="$(sqlite3 "$db" "SELECT COALESCE(closed_at,'') FROM urs WHERE slug='$ur';")"
[ -n "$cl2" ] || fail "closed_at cleared after second close"

# brief still original after all artifact ops
brief_final="$(sqlite3 "$db" "SELECT brief FROM urs WHERE slug='$ur';")"
[ "$brief_final" = "ORIGINAL BRIEF" ] || fail "brief corrupted after artifacts: $brief_final"

# --- decisions: append-only ---
bash "$DW" append-decision "$TMP" "2026-08-11 | $ur | use sqlite | sole store" \
  || fail "append-decision 1"
bash "$DW" append-decision "$TMP" "2026-08-11 | $ur | gates local | gate-owner.md" \
  || fail "append-decision 2"
dec_n="$(sqlite3 "$db" "SELECT COUNT(*) FROM decisions;")"
[ "$dec_n" = "2" ] || fail "decisions count want 2 got $dec_n"
dec_lines="$(sqlite3 "$db" "SELECT line FROM decisions ORDER BY id;")"
case "$dec_lines" in
  *"use sqlite"* ) : ;;
  *) fail "decision line missing: $dec_lines" ;;
esac

# --- calibration: replace ---
bash "$DW" write-calibration "$TMP" --body "calib v1" || fail "write-calibration v1"
bash "$DW" write-calibration "$TMP" --body "calib v2" || fail "write-calibration v2"
cal_out="$(bash "$DW" read-calibration "$TMP" 2>&1)" || fail "read-calibration failed"
[ "$cal_out" = "calib v2" ] || fail "read-calibration want 'calib v2' got '$cal_out'"
cal_n="$(sqlite3 "$db" "SELECT COUNT(*) FROM calibration;")"
[ "$cal_n" = "1" ] || fail "calibration must be single-row, got count $cal_n"

# --- milestone_state per-UR ---
bash "$DW" set-active-milestone "$TMP" "$ur" M1 || fail "set-active-milestone M1"
act="$(bash "$DW" get-active-milestone "$TMP" "$ur" 2>&1)" || fail "get-active-milestone"
[ "$act" = "M1" ] || fail "active milestone want M1 got '$act'"

# second UR independent cursor
ur2="$(bash "$DW" create-ur "$TMP" --title "Other" --brief "b2")" || fail "create-ur 2"
act2="$(bash "$DW" get-active-milestone "$TMP" "$ur2" 2>&1)" || fail "get-active empty ur2"
[ -z "$act2" ] || fail "ur2 should have empty active, got '$act2'"
bash "$DW" set-active-milestone "$TMP" "$ur2" M2 || fail "set ur2 M2"
act1b="$(bash "$DW" get-active-milestone "$TMP" "$ur")"
[ "$act1b" = "M1" ] || fail "ur1 cursor must stay M1, got $act1b"

req_m1="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "M1 work" --path-milestone M1)" \
  || fail "create-req M1"
req_m2="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "M2 work" --path-milestone M2)" \
  || fail "create-req M2"
req_none="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "no mile")" \
  || fail "create-req none"

list_m="$(bash "$DW" list-milestone-reqs "$TMP" "$ur" 2>&1)" || fail "list-milestone-reqs"
case "$list_m" in
  *"$req_m1"* ) : ;;
  *) fail "list-milestone-reqs missing $req_m1: $list_m" ;;
esac
case "$list_m" in
  *"$req_m2"* ) fail "list-milestone-reqs should not include M2 req when active=M1: $list_m" ;;
esac
case "$list_m" in
  *"$req_none"* ) fail "list-milestone-reqs should not include unassigned: $list_m" ;;
esac

# explicit milestone arg
list_m2="$(bash "$DW" list-milestone-reqs "$TMP" "$ur" --milestone M2 2>&1)" \
  || fail "list-milestone-reqs --milestone M2"
case "$list_m2" in
  *"$req_m2"* ) : ;;
  *) fail "list --milestone M2 missing $req_m2: $list_m2" ;;
esac

# clear active
bash "$DW" set-active-milestone "$TMP" "$ur" "" || fail "clear active milestone"
act_clr="$(bash "$DW" get-active-milestone "$TMP" "$ur")"
[ -z "$act_clr" ] || fail "cleared active should be empty, got $act_clr"

# --- run_notes ---
req_note="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "noted")" || fail "req for notes"
bash "$DW" append-run-note "$TMP" "$req_note" --payload "cost: 1\noutcome: ok" \
  || fail "append-run-note 1"
bash "$DW" append-run-note "$TMP" "$req_note" --payload "cost: 2" \
  || fail "append-run-note 2"
rn="$(sqlite3 "$db" "SELECT COUNT(*) FROM run_notes rn
  JOIN reqs r ON r.id=rn.req_id WHERE r.slug='$req_note';")"
[ "$rn" = "2" ] || fail "run_notes count want 2 got $rn"
payload1="$(sqlite3 "$db" "SELECT payload FROM run_notes rn
  JOIN reqs r ON r.id=rn.req_id WHERE r.slug='$req_note' ORDER BY rn.id LIMIT 1;")"
case "$payload1" in
  *"cost: 1"* ) : ;;
  *) fail "run note payload missing: $payload1" ;;
esac

# unknown UR hard-fails
if bash "$DW" append-ideate "$TMP" "UR-99999" --body "x" 2>/dev/null; then
  fail "append-ideate unknown UR should fail"
fi

rm -rf "$TMP"

if [ "$FAILED" -ne 0 ]; then
  echo "FAILED: $FAILED assertion(s)"
  exit 1
fi
echo "PASS: dw-db-artifacts"
exit 0
