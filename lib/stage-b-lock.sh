#!/usr/bin/env bash
# stage-b-lock.sh — Stage B serialization lock for do-work parallel mode.
#
# Usage: stage-b-lock.sh with-lock <command> [args...]
#
# Runs <command> with arguments while holding the Stage B serialization lock.
# The lock is acquired before the command starts and released automatically
# when the command (or this wrapper) exits — no manual release needed.
#
# Environment:
#   STATE_DIR  Runtime state directory (default: .do-work/state/). The lock file
#              lives at $STATE_DIR/stage-b.lock.
#
# What it does:
#   Provides a process-scoped, self-healing lock for Stage B merge serialization.
#   Uses python3's fcntl.flock(LOCK_EX) which:
#   - Is portable across macOS and Linux
#   - Auto-releases when the holding process exits (kernel guarantee)
#   - No stale lock failure mode
#
# Exit codes:
#   Same exit code as <command> (or 1 if wrapper fails).
#
# Example:
#   stage-b-lock.sh with-lock bash lib/integrate-req.sh "$REQ_PATH"
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# --- defaults -----------------------------------------------------------------

STATE_DIR="${STATE_DIR:-.do-work/state}"
if [ "${STATE_DIR#/}" = "$STATE_DIR" ]; then
  # Relative path — resolve from cwd
  STATE_DIR="$(cd "$(pwd)/$STATE_DIR" 2>/dev/null && pwd)" || {
    echo "stage-b-lock: cannot resolve state directory: $STATE_DIR" >&2
    exit 1
  }
fi

LOCK_FILE="$STATE_DIR/stage-b.lock"

# --- helpers -----------------------------------------------------------------

check_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "stage-b-lock: python3 is required but not found in PATH" >&2
    echo "stage-b-lock: python3 is used for portable flock-based locking" >&2
    exit 1
  fi
}

ensure_state_dir() {
  if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR" || {
      echo "stage-b-lock: cannot create state directory: $STATE_DIR" >&2
      exit 1
    }
  fi
}

# --- subcommand: with-lock ----------------------------------------------------

# Run a command while holding the lock.
# Usage: with-lock <command> [args...]
with_lock() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: stage-b-lock.sh with-lock <command> [args...]" >&2
    exit 1
  fi

  check_python3
  ensure_state_dir

  local cmd="$1"
  shift

  # Use python to hold the lock and execute the command.
  # The lock fd stays open for the duration of the command.
  python3 - "$LOCK_FILE" "$cmd" "$@" <<'PY_END'
import sys
import os
import fcntl
import subprocess

lock_path = sys.argv[1]
cmd = sys.argv[2]
args = sys.argv[3:]

try:
  # Open/create lock file and acquire exclusive lock
  fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o666)
  fcntl.flock(fd, fcntl.LOCK_EX)

  # Lock acquired — execute the command
  result = subprocess.run([cmd] + args)

  # Lock auto-releases when this python process exits (fd closes)
  sys.exit(result.returncode)

except OSError as e:
  sys.stderr.write(f"stage-b-lock: error: {e}\n")
  sys.exit(1)
PY_END
}

# --- main ---------------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  echo "Usage: stage-b-lock.sh with-lock <command> [args...]" >&2
  exit 1
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  with-lock)
    with_lock "$@"
    ;;
  *)
    echo "stage-b-lock: unknown subcommand: $SUBCOMMAND" >&2
    echo "Usage: stage-b-lock.sh with-lock <command> [args...]" >&2
    exit 1
    ;;
esac
