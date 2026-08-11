#!/usr/bin/env bash
# dw-db-board.test.sh — static HTML board: escape, generated_at, claimer, no claim/archive regen.
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

TMP="$(mktemp -d -t dw-board.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }

evil_title='<script>alert(1)</script>'
ur="$(bash "$DW" create-ur "$TMP" --title "$evil_title" --brief "board brief")" \
  || { fail "create-ur"; rm -rf "$TMP"; exit 1; }
req="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "$evil_title" --body "safe body")" \
  || { fail "create-req"; rm -rf "$TMP"; exit 1; }

# Claim so board shows claimer + heartbeat
bash "$DW" claim "$TMP" "$req" "agent-board-test" --session "sess-board" \
  || fail "claim failed"

# Stale heartbeat so stale banner can fire (age >> 900)
db="$TMP/.do-work/work.db"
sqlite3 "$db" "UPDATE claims SET heartbeat='2000-01-01T00:00:00Z'
  WHERE req_id=(SELECT id FROM reqs WHERE slug='$req') AND status='active';"

# --- board generates HTML ---
out="$(bash "$DW" board "$TMP" 2>&1)" || {
  fail "board exit non-zero: $out"
  rm -rf "$TMP"
  exit 1
}

board_path="$TMP/.do-work/board/index.html"
case "$out" in
  *"$board_path"*) : ;;
  *) fail "board stdout should print path, got: $out" ;;
esac
[ -f "$board_path" ] || fail "board file missing at $board_path"

html="$(cat "$board_path")"

# generated_at present (ISO-ish)
case "$html" in
  *generated_at*|*Generated*) : ;;
  *) fail "expected generated_at marker in HTML" ;;
esac
# Must contain a Z-suffixed timestamp somewhere
echo "$html" | grep -E -q '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
  || fail "expected ISO generated_at timestamp in HTML"

# Titles with <script> must be escaped — no executable raw script tag from title
case "$html" in
  *'<script>alert(1)</script>'*)
    fail "raw <script>alert(1)</script> must not appear unescaped"
    ;;
esac
case "$html" in
  *'&lt;script&gt;alert(1)&lt;/script&gt;'*) : ;;
  *) fail "expected HTML-escaped script title entities" ;;
esac

# UR/REQ tables present
case "$html" in
  *"$ur"*|*"User Requests"*|*"UR"*) : ;;
  *) fail "expected UR content in board" ;;
esac
case "$html" in
  *"$req"*|*"REQs"*|*"Requirements"*) : ;;
  *) fail "expected REQ content in board" ;;
esac

# Claimer + stale indication
case "$html" in
  *agent-board-test*) : ;;
  *) fail "expected claimer agent-board-test in board" ;;
esac
case "$html" in
  *[Ss][Tt][Aa][Ll][Ee]*) : ;;
  *) fail "expected stale banner/marker for old heartbeat" ;;
esac

# Capture mtime after first board
mtime1="$(stat -f %m "$board_path" 2>/dev/null || stat -c %Y "$board_path")"
# Ensure distinct second boundary
sleep 1

# claim must NOT regenerate board
req2="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Second" --body "b2")" \
  || fail "create-req2"
bash "$DW" claim "$TMP" "$req2" "agent-B" || fail "claim2"
mtime2="$(stat -f %m "$board_path" 2>/dev/null || stat -c %Y "$board_path")"
[ "$mtime1" = "$mtime2" ] || fail "claim must not regenerate board (mtime $mtime1 -> $mtime2)"

# archive-req must NOT regenerate board
bash "$DW" update-req "$TMP" "$req2" --closure-proof "tests green" || fail "proof"
bash "$DW" set-status "$TMP" "$req2" done || fail "set done"
# need unchecked AC free body for archive — create-req body "b2" has no open AC
bash "$DW" archive-req "$TMP" "$req2" || fail "archive-req"
mtime3="$(stat -f %m "$board_path" 2>/dev/null || stat -c %Y "$board_path")"
[ "$mtime1" = "$mtime3" ] || fail "archive-req must not regenerate board (mtime $mtime1 -> $mtime3)"

# --path override
custom="$TMP/custom-board/out.html"
out2="$(bash "$DW" board "$TMP" --path "$custom" 2>&1)" || fail "board --path failed: $out2"
[ -f "$custom" ] || fail "custom board path not written"
case "$out2" in
  *"$custom"*) : ;;
  *) fail "stdout should print custom path: $out2" ;;
esac
chtml="$(cat "$custom")"
case "$chtml" in
  *'&lt;script&gt;alert(1)&lt;/script&gt;'*) : ;;
  *) fail "custom path board should still escape titles" ;;
esac

rm -rf "$TMP"

if [ "$FAILED" -ne 0 ]; then
  echo "dw-db-board: $FAILED failure(s)" >&2
  exit 1
fi
echo "PASS dw-db-board"
exit 0
