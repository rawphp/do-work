#!/usr/bin/env bash
# install-hooks.sh — idempotently wire do-work's SessionStart / Stop telemetry
# hooks into a consumer project's .claude/settings.json.
#
# Usage:
#   install-hooks.sh <project>          # install/merge hooks; report result
#   install-hooks.sh --check <project>  # report presence only (no writes)
#
# The hook commands point at this repo's lib/session-hook.sh (absolute path):
#   SessionStart → "<lib>/session-hook.sh start"
#   Stop         → "<lib>/session-hook.sh end"
#
# Idempotent: repeated runs yield exactly one entry per hook (dedup by exact
# command string). Existing, unrelated hooks and settings are preserved. The
# hooks themselves are safe no-ops in projects without .do-work/ (see
# session-hook.sh), so adding them to a shared settings.json is harmless.
#
# Output (stdout, one word):
#   installed          — hooks were added this run.
#   already-conformant — both hooks already present; nothing changed.
#   present | absent   — for --check mode.
#   skipped            — python3 unavailable; hooks not installed (non-fatal).
#
# Requires python3 for a safe structural JSON merge (matches the precedent in
# provision-worktree.sh). If python3 is missing, prints a warning to stderr and
# exits 0 — telemetry degrades gracefully and never blocks install/upgrade.
#
# Exit codes:
#   0  Success (installed, already-conformant, present/absent, or skipped).
#   1  Usage error, or settings.json exists but is not valid JSON.
#
# Compatible with macOS bash 3.2 + BSD userland.

set -u

MODE="install"
if [ "${1:-}" = "--check" ]; then
  MODE="check"
  shift
fi

PROJECT="${1:-}"
if [ -z "$PROJECT" ]; then
  echo "install-hooks.sh: usage: install-hooks.sh [--check] <project>" >&2
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOOK_SCRIPT="$SCRIPT_DIR/session-hook.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "install-hooks.sh: python3 not found — skipping hook install (telemetry degrades gracefully)" >&2
  echo "skipped"
  exit 0
fi

python3 - "$PROJECT" "$HOOK_SCRIPT" "$MODE" <<'PY'
import json, os, sys

project, hook_script, mode = sys.argv[1], sys.argv[2], sys.argv[3]

settings_dir = os.path.join(project, ".claude")
settings_path = os.path.join(settings_dir, "settings.json")

# Desired (event -> command) mapping.
wanted = {
    "SessionStart": hook_script + " start",
    "Stop":         hook_script + " end",
}

# Load existing settings (or start fresh).
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except (ValueError, OSError) as e:
        sys.stderr.write("install-hooks.sh: %s is not valid JSON: %s\n" % (settings_path, e))
        sys.exit(1)
    if not isinstance(settings, dict):
        sys.stderr.write("install-hooks.sh: %s is not a JSON object\n" % settings_path)
        sys.exit(1)
else:
    settings = {}

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

def command_present(event, command):
    groups = hooks.get(event)
    if not isinstance(groups, list):
        return False
    for group in groups:
        if not isinstance(group, dict):
            continue
        entries = group.get("hooks")
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and entry.get("command") == command:
                return True
    return False

# --check: report presence without touching anything.
if mode == "check":
    both = all(command_present(ev, cmd) for ev, cmd in wanted.items())
    print("present" if both else "absent")
    sys.exit(0)

changed = False
for event, command in wanted.items():
    if command_present(event, command):
        continue
    groups = hooks.get(event)
    if not isinstance(groups, list):
        groups = []
    groups.append({"hooks": [{"type": "command", "command": command}]})
    hooks[event] = groups
    changed = True

if not changed:
    print("already-conformant")
    sys.exit(0)

settings["hooks"] = hooks
os.makedirs(settings_dir, exist_ok=True)
tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)
print("installed")
PY
