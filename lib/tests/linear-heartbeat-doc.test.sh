#!/usr/bin/env bash
# Tests for the Linear heartbeat_req doc-shape guard (UR-004 / F5).
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# F5 made heartbeat_req patch-in-place primary with a hard-stop on no active
# claim (parity with sqlite's cmd_heartbeat die-on-0-rows). This test locks
# that shape so the rule cannot silently drift back to "post a new comment"
# primary — the contradiction that caused F5. lib/doc-lint.sh does not scan
# references/ and the regression is structural (which clause leads), so this
# is a dedicated test discovered and run by lib/tests/run-all.sh.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
REPO_ROOT="$( cd "$LIB_DIR/.." && pwd )"
DOC="$REPO_ROOT/references/linear-ops.md"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() { echo "FAIL [$CURRENT_CASE]: $*" >&2; FAILED=$((FAILED + 1)); }

# check_heartbeat_doc <linear-ops.md path>
# Exit 0 iff heartbeat_req is patch-in-place primary + hard-stop + mapping row
# agrees. Exit 1 on any regression. Locale-safe (no em-dash/backtick patterns).
check_heartbeat_doc() {
  local f="$1" body maprow
  body="$(awk '/^### .*heartbeat_req/{s=1} s{print} s&&/^---$/{exit}' "$f")"
  maprow="$(grep -E '^\| \*\*Heartbeat\*\*' "$f")"
  [ -n "$body" ] || { echo "check: heartbeat_req section not found" >&2; return 1; }
  printf '%s\n' "$body" | grep -q 'PATCH IN PLACE' \
    || { echo "check: heartbeat_req step 3 not patch-in-place primary (no PATCH IN PLACE marker)" >&2; return 1; }
  printf '%s\n' "$body" | grep -q 'post a new claim-protocol comment (or update the existing comment' \
    && { echo "check: REGRESSED to new-comment-primary (F5)" >&2; return 1; }
  printf '%s\n' "$body" | grep -q 'HARD-STOP' \
    || { echo "check: no HARD-STOP in heartbeat_req (sqlite die parity missing)" >&2; return 1; }
  printf '%s\n' "$body" | grep -q 'do not create' \
    || { echo "check: missing do-not-create guard on no active claim" >&2; return 1; }
  printf '%s\n' "$maprow" | grep -q 'Patch the existing active claim comment in place' \
    || { echo "check: Concept->Linear mapping Heartbeat row not patch-primary" >&2; return 1; }
  return 0
}

# --- Case 1: the real (fixed) references/linear-ops.md must pass ---
CURRENT_CASE="real-doc-passes"
CASES=$((CASES + 1))
if check_heartbeat_doc "$DOC" >/tmp/lhd1.out 2>&1; then
  echo "ok: $CURRENT_CASE"
else
  fail "real references/linear-ops.md failed the heartbeat shape guard"; cat /tmp/lhd1.out >&2
fi
rm -f /tmp/lhd1.out

# --- Case 2: a regressed (pre-F5) doc shape must FAIL ---
CURRENT_CASE="regressed-doc-fails"
CASES=$((CASES + 1))
TMP="$(mktemp -d -t lhd-test.XXXXXX)"
# Hand-crafted minimal regressed heartbeat_req + mapping row (the pre-F5 wording).
cat > "$TMP/linear-ops-bad.md" <<'BADDOC'
### `heartbeat_req`

**Agent sequence:**

1. **Rediscover** — get issue + list/create comments.
2. **Read active claim** — must be active and agent_id match. If no active claim -> error (nothing to heartbeat).
3. **Write heartbeat** — post a new claim-protocol comment (or update the existing comment if update-comment tools exist and schema allows) with refreshed heartbeat.

| **Heartbeat** | New claim-protocol comment or append/update path that writes updated heartbeat |
BADDOC
if check_heartbeat_doc "$TMP/linear-ops-bad.md" >/tmp/lhd2.out 2>&1; then
  fail "regressed doc passed the guard — the guard does NOT catch the F5 regression"; cat /tmp/lhd2.out >&2
else
  echo "ok: $CURRENT_CASE"
fi
rm -f /tmp/lhd2.out
rm -rf "$TMP"

echo "linear-heartbeat-doc tests: $CASES cases, $FAILED failure(s)"
[ "$FAILED" -eq 0 ]
