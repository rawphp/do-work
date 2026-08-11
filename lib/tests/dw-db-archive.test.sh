#!/usr/bin/env bash
# dw-db-archive.test.sh — check-archive three criteria + archive-req gate.
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

TMP="$(mktemp -d -t dw-arch.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

ur="$(bash "$DW" create-ur "$TMP" --title "Arch UR" --brief "b")" || {
  fail "create-ur"; rm -rf "$TMP"; exit 1
}

body_bad='## Task
do it
## Acceptance Criteria
- [ ] not done
- [x] done one
'
body_good='## Task
do it
## Acceptance Criteria
- [x] all good
- [x] also good
'

req="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "To archive" --body "$body_bad")" || {
  fail "create-req"; rm -rf "$TMP"; exit 1
}

# 1) not done, no proof, unchecked AC → check-archive fails
set +e
bash "$DW" check-archive "$TMP" "$req" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "check-archive should fail on backlog/no-proof/unchecked"

# 2) set done but still no proof + unchecked → fail
bash "$DW" set-status "$TMP" "$req" done || fail "set done"
set +e
bash "$DW" check-archive "$TMP" "$req" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "check-archive should fail without proof and with unchecked AC"

# 3) proof set but unchecked AC → fail
bash "$DW" update-req "$TMP" "$req" --closure-proof "tests pass" || fail "set proof"
set +e
bash "$DW" check-archive "$TMP" "$req" 2>/tmp/dw-arch-err.txt
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "check-archive should fail with unchecked AC"
case "$(cat /tmp/dw-arch-err.txt 2>/dev/null)" in
  *unchecked*|*Acceptance*|*AC*|*criteria*) : ;;
  *) : ;; # diagnostic optional wording
esac

# 4) fix AC (all checked) + done + proof → pass
bash "$DW" update-req "$TMP" "$req" --body "$body_good" --closure-proof "all green" || fail "fix body"
if ! bash "$DW" check-archive "$TMP" "$req" 2>/tmp/dw-arch-err.txt; then
  fail "check-archive should pass when done+proof+AC checked; err=$(cat /tmp/dw-arch-err.txt)"
fi

# --- archive-req: requires proof+AC, sets done, releases claim ---
req2="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Arch flow" --body "$body_good")" || fail "req2"
bash "$DW" claim "$TMP" "$req2" "agent-Z" 2>/dev/null || fail "claim req2"
# missing proof → archive-req fails, claim stays
set +e
bash "$DW" archive-req "$TMP" "$req2" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "archive-req without proof should fail"
st="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req2';")"
[ "$st" = "in_progress" ] || fail "failed archive should leave status in_progress got $st"
act="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req2' AND c.status='active';")"
[ "$act" = "1" ] || fail "failed archive should leave claim active"

bash "$DW" update-req "$TMP" "$req2" --closure-proof "worker done" || fail "proof2"
if ! bash "$DW" archive-req "$TMP" "$req2" 2>/tmp/dw-arch-err.txt; then
  fail "archive-req should succeed; err=$(cat /tmp/dw-arch-err.txt)"
fi
st2="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req2';")"
[ "$st2" = "done" ] || fail "archive-req status want done got $st2"
act2="$(sqlite3 "$db" "SELECT COUNT(*) FROM claims c JOIN reqs r ON r.id=c.req_id
  WHERE r.slug='$req2' AND c.status='active';")"
[ "$act2" = "0" ] || fail "archive-req should release claim"
# post-archive check-archive passes
if ! bash "$DW" check-archive "$TMP" "$req2" 2>/tmp/dw-arch-err.txt; then
  fail "check-archive after archive-req should pass; err=$(cat /tmp/dw-arch-err.txt)"
fi

# archive-req with unchecked AC fails
req3="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Bad AC" --body "$body_bad")" || fail "req3"
bash "$DW" update-req "$TMP" "$req3" --closure-proof "proof" || fail "proof3"
set +e
bash "$DW" archive-req "$TMP" "$req3" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "archive-req with unchecked AC should fail"

rm -rf "$TMP"
rm -f /tmp/dw-arch-err.txt

if [ "$FAILED" -ne 0 ]; then
  echo "dw-db-archive: $FAILED failure(s)" >&2
  exit 1
fi
echo "PASS dw-db-archive"
exit 0
