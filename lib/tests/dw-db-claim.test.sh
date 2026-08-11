#!/usr/bin/env bash
# dw-db-claim.test.sh — claim race, stale takeover, heartbeat UPDATE-only, unblock.
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

TMP="$(mktemp -d -t dw-claim.XXXXXX)"
mkdir -p "$TMP/.do-work" "$TMP/src"
echo "a" > "$TMP/src/a.ts"
echo "b" > "$TMP/src/b.ts"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

ur="$(bash "$DW" create-ur "$TMP" --title "Claim UR" --brief "brief")" || {
  fail "create-ur"; rm -rf "$TMP"; exit 1
}
req="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Claim me" --files "src/a.ts")" || {
  fail "create-req"; rm -rf "$TMP"; exit 1
}

# --- First claim succeeds ---
err="$(mktemp -t dw-claim-err.XXXXXX)"
if ! bash "$DW" claim "$TMP" "$req" "agent-A" --session "sess-1" 2>"$err"; then
  fail "first claim should exit 0; stderr=$(cat "$err")"
fi
st="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req';")"
[ "$st" = "in_progress" ] || fail "after claim status want in_progress got $st"
active_n="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_n" = "1" ] || fail "want 1 active claim after first claim, got $active_n"
agent="$(sqlite3 "$db" "SELECT agent_id FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$agent" = "agent-A" ] || fail "claimer want agent-A got $agent"
sess="$(sqlite3 "$db" "SELECT session FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$sess" = "sess-1" ] || fail "session want sess-1 got $sess"

# --- Second claim on fresh foreign active → exit 2 + concurrent-conflict ---
set +e
bash "$DW" claim "$TMP" "$req" "agent-B" 2>"$err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "foreign fresh claim want exit 2 got $rc"
errtxt="$(cat "$err")"
case "$errtxt" in
  *concurrent-conflict*) : ;;
  *) fail "stderr should mention concurrent-conflict: $errtxt" ;;
esac
active_n2="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_n2" = "1" ] || fail "after race still 1 active, got $active_n2"
agent2="$(sqlite3 "$db" "SELECT agent_id FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$agent2" = "agent-A" ] || fail "after race owner still agent-A, got $agent2"

# --- Own claim is idempotent ---
if ! bash "$DW" claim "$TMP" "$req" "agent-A" 2>"$err"; then
  fail "own re-claim should succeed; stderr=$(cat "$err")"
fi
active_n3="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_n3" = "1" ] || fail "own re-claim must not create second active, got $active_n3"

# --- Heartbeat UPDATE-only (same agent) ---
old_hb="$(sqlite3 "$db" "SELECT heartbeat FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
# Force an older heartbeat so we can see an update
sqlite3 "$db" "UPDATE claims SET heartbeat='2000-01-01T00:00:00Z'
  WHERE req_id=(SELECT id FROM reqs WHERE slug='$req') AND status='active';"
if ! bash "$DW" heartbeat "$TMP" "$req" "agent-A" 2>"$err"; then
  fail "heartbeat owner should succeed; stderr=$(cat "$err")"
fi
new_hb="$(sqlite3 "$db" "SELECT heartbeat FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$new_hb" != "2000-01-01T00:00:00Z" ] || fail "heartbeat should update timestamp"
active_after_hb="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_after_hb" = "1" ] || fail "heartbeat must not insert second active, got $active_after_hb"
total_claims="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req';")"
# only one claim row still (no insert from heartbeat)
# (may be 1 unless prior takeover; here still 1)
[ "$total_claims" = "1" ] || fail "heartbeat must not insert claim rows; total=$total_claims"

# Foreign heartbeat → fail
set +e
bash "$DW" heartbeat "$TMP" "$req" "agent-B" 2>"$err"
hb_rc=$?
set -e
[ "$hb_rc" -ne 0 ] || fail "foreign heartbeat should fail"

# --- Stale foreign takeover: release old, insert new; one active max ---
sqlite3 "$db" "UPDATE claims SET heartbeat='2000-01-01T00:00:00Z'
  WHERE req_id=(SELECT id FROM reqs WHERE slug='$req') AND status='active';"
if ! bash "$DW" claim "$TMP" "$req" "agent-B" --stale-max 60 2>"$err"; then
  fail "stale takeover claim should succeed; stderr=$(cat "$err")"
fi
active_owner="$(sqlite3 "$db" "SELECT agent_id FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_owner" = "agent-B" ] || fail "after stale takeover owner want agent-B got $active_owner"
active_n4="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_n4" = "1" ] || fail "after takeover exactly 1 active, got $active_n4"
released_n="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='released' AND c.agent_id='agent-A';")"
[ "$released_n" -ge 1 ] || fail "old agent-A claim should be released"

# --- unblock: backlog + release claim ---
if ! bash "$DW" unblock "$TMP" "$req" 2>"$err"; then
  fail "unblock should succeed; stderr=$(cat "$err")"
fi
st_u="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req';")"
[ "$st_u" = "backlog" ] || fail "unblock status want backlog got $st_u"
active_u="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req' AND c.status='active';")"
[ "$active_u" = "0" ] || fail "unblock should release active claim, got $active_u"

# --- check-deps: unsatisfied when dep not done ---
dep="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Dep")" || fail "create dep"
req_d="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Blocked" --deps "$dep")" || fail "create blocked"
missing="$(bash "$DW" check-deps "$TMP" "$req_d" 2>/dev/null || true)"
case "$missing" in
  *"$dep"*) : ;;
  *) fail "check-deps should list $dep when not done; got '$missing'" ;;
esac
bash "$DW" set-status "$TMP" "$dep" done || fail "set dep done"
missing2="$(bash "$DW" check-deps "$TMP" "$req_d" 2>/dev/null || true)"
[ -z "$missing2" ] || fail "check-deps empty when deps done; got '$missing2'"

# --- check-footprint: overlap with in-flight active claim ---
req_f1="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "F1" --files "src/a.ts")" || fail "f1"
req_f2="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "F2" --files "src/a.ts")" || fail "f2"
bash "$DW" claim "$TMP" "$req_f1" "agent-F" 2>/dev/null || fail "claim f1"
fp="$(bash "$DW" check-footprint "$TMP" "$req_f2" 2>/dev/null || true)"
case "$fp" in
  *overlap:*"$req_f1"*|*"$req_f1"*) : ;;
  *) fail "check-footprint should report overlap with $req_f1; got '$fp'" ;;
esac
# empty files → free
req_empty="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Empty files")" || fail "empty"
fp_e="$(bash "$DW" check-footprint "$TMP" "$req_empty" 2>/dev/null || true)"
[ -z "$fp_e" ] || fail "empty files footprint should be free; got '$fp_e'"

# --- scan-stale ---
req_s="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Stale scan" --files "src/b.ts")" || fail "stale req"
bash "$DW" claim "$TMP" "$req_s" "agent-S" 2>/dev/null || fail "claim stale-scan"
sqlite3 "$db" "UPDATE claims SET heartbeat='2000-01-01T00:00:00Z'
  WHERE req_id=(SELECT id FROM reqs WHERE slug='$req_s') AND status='active';"
stale_out="$(bash "$DW" scan-stale "$TMP" --stale-max 60 2>/dev/null || true)"
case "$stale_out" in
  *"$req_s"*) : ;;
  *) fail "scan-stale should list $req_s; got '$stale_out'" ;;
esac

rm -f "$err"
rm -rf "$TMP"

if [ "$FAILED" -ne 0 ]; then
  echo "dw-db-claim: $FAILED failure(s)" >&2
  exit 1
fi
echo "PASS dw-db-claim"
exit 0
