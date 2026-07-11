#!/usr/bin/env bash
# Tests for lib/install-hooks.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
# Requires python3; skips (passes) gracefully if it is unavailable.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/install-hooks.sh"
HOOK_SCRIPT="$LIB_DIR/session-hook.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "install-hooks.test.sh: python3 unavailable — skipping"
  exit 0
fi

FAILED=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

setup() { TMP="$(mktemp -d -t install-hooks-test.XXXXXX)"; }
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

SETTINGS() { echo "$TMP/.claude/settings.json"; }

# count occurrences of the hook command across the settings.json
count_cmd() {
  grep -c "session-hook.sh $1" "$(SETTINGS)" 2>/dev/null || echo 0
}

# --- fresh project: installs both hooks ------------------------------------
CURRENT_CASE="fresh install"
setup
out="$(bash "$SCRIPT" "$TMP")"
assert_eq "installed" "$out" "output"
[ -f "$(SETTINGS)" ] || fail "settings.json not created"
assert_eq 1 "$(count_cmd start | tr -d ' ')" "one SessionStart command"
assert_eq 1 "$(count_cmd end | tr -d ' ')" "one Stop command"
# valid JSON with expected structure
python3 - "$(SETTINGS)" "$HOOK_SCRIPT" <<'PY' || fail "structure check failed"
import json, sys
s = json.load(open(sys.argv[1]))
hook = sys.argv[2]
h = s["hooks"]
def has(ev, cmd):
    return any(
        e.get("command") == cmd
        for g in h.get(ev, []) for e in g.get("hooks", [])
    )
assert has("SessionStart", hook + " start"), "SessionStart missing"
assert has("Stop", hook + " end"), "Stop missing"
PY
teardown

# --- idempotence: second run makes no change (REQ acceptance criterion 5) ---
CURRENT_CASE="idempotent second run"
setup
bash "$SCRIPT" "$TMP" >/dev/null
out2="$(bash "$SCRIPT" "$TMP")"
assert_eq "already-conformant" "$out2" "second run output"
assert_eq 1 "$(count_cmd start | tr -d ' ')" "still one SessionStart after 2 runs"
assert_eq 1 "$(count_cmd end | tr -d ' ')" "still one Stop after 2 runs"
teardown

# --- preserves unrelated existing settings ---------------------------------
CURRENT_CASE="preserves existing settings"
setup
mkdir -p "$TMP/.claude"
cat > "$(SETTINGS)" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "echo hi" } ] }
    ]
  }
}
JSON
bash "$SCRIPT" "$TMP" >/dev/null
python3 - "$(SETTINGS)" <<'PY' || fail "existing settings not preserved"
import json, sys
s = json.load(open(sys.argv[1]))
assert s.get("model") == "opus", "model key lost"
assert any(
    e.get("command") == "echo hi"
    for g in s["hooks"].get("PreToolUse", []) for e in g.get("hooks", [])
), "pre-existing PreToolUse hook lost"
assert "SessionStart" in s["hooks"], "SessionStart not added"
PY
teardown

# --- --check reports absent then present -----------------------------------
CURRENT_CASE="--check present/absent"
setup
assert_eq "absent" "$(bash "$SCRIPT" --check "$TMP")" "absent before install"
bash "$SCRIPT" "$TMP" >/dev/null
assert_eq "present" "$(bash "$SCRIPT" --check "$TMP")" "present after install"
teardown

# --- invalid JSON settings -> exit 1, no clobber ---------------------------
CURRENT_CASE="invalid settings.json rejected"
setup
mkdir -p "$TMP/.claude"
printf '{ not json ' > "$(SETTINGS)"
bash "$SCRIPT" "$TMP" >/dev/null 2>&1
assert_eq 1 "$?" "exit 1 on invalid JSON"
assert_eq '{ not json ' "$(cat "$(SETTINGS)")" "file left untouched"
teardown

# --- summary ---------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  echo "install-hooks.test.sh: all cases passed"
  exit 0
else
  echo "install-hooks.test.sh: $FAILED assertion(s) failed" >&2
  exit 1
fi
