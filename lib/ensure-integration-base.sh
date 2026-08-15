#!/usr/bin/env bash
# ensure-integration-base.sh — leave protected default branches before workers run.
#
# Usage: ensure-integration-base.sh [UR-NNN]
#
# Operates on the git repository at CWD (same contract as other lib scripts).
# Ensures the orchestrator checkout is not on a protected default branch
# (main, master, and the remote HEAD short name when resolvable) before
# workers are provisioned.
#
# Behaviour:
#   - Detached HEAD → hard-stop non-zero (no branch create).
#   - Current branch not protected → print branch name, exit 0 (skip).
#   - On protected default → leave for fixed branch `new-work`:
#       * create from current tip if missing
#       * if present: checkout and merge the protected tip just left into new-work
#       * dirty tree is allowed; uncommitted changes carry onto new-work
#     UR-NNN arg is accepted for CLI compatibility but does not change the name.
#   - Print final branch name on stdout; exit 0.
#
# Compatible with macOS bash 3.2. set -u. Pure bash + git.

set -u

# --- must be inside a git work tree -----------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ensure-integration-base.sh: not a git repository (cwd: $(pwd))" >&2
  exit 1
fi

# --- current branch / detached ----------------------------------------------

CURRENT="$(git branch --show-current 2>/dev/null || true)"
if [ -z "$CURRENT" ]; then
  echo "ensure-integration-base.sh: detached HEAD — checkout a branch before continuing" >&2
  exit 1
fi

# --- protected defaults: main, master, + remote HEAD short name -------------

# Space-separated list of protected short branch names.
PROTECTED="main master"

remote_head=""
# Prefer symbolic-ref (exact); fall back to rev-parse --abbrev-ref.
if remote_sym="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)"; then
  # refs/remotes/origin/main → main
  remote_head="${remote_sym#refs/remotes/origin/}"
elif remote_abr="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null)"; then
  # origin/main → main
  remote_head="${remote_abr#origin/}"
fi

# Only add a real short name; never invent when missing/empty/HEAD.
if [ -n "$remote_head" ] && [ "$remote_head" != "HEAD" ] && [ "$remote_head" != "origin" ]; then
  case " $PROTECTED " in
    *" $remote_head "*) : ;;
    *) PROTECTED="$PROTECTED $remote_head" ;;
  esac
fi

is_protected() {
  local b="$1"
  case " $PROTECTED " in
    *" $b "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- skip when already off a protected default ------------------------------
# Binding skip: callers must NOT invent new-work checkouts when we skip.
# Printing the current branch name is the only success signal for this path.

if ! is_protected "$CURRENT"; then
  printf '%s\n' "$CURRENT"
  exit 0
fi

# --- leave default: always fixed integration branch new-work ----------------
# Remember the protected tip we are leaving so we can merge it into new-work.

PROTECTED_TIP="$CURRENT"
TARGET="new-work"

# Optional UR-NNN arg: accept for CLI compatibility; ignore for naming.
UR_ARG="${1:-}"
if [ -n "$UR_ARG" ]; then
  case "$UR_ARG" in
    UR-[0-9]*)
      if ! printf '%s' "$UR_ARG" | grep -Eq '^UR-[0-9]+$'; then
        echo "ensure-integration-base.sh: invalid Issue slug '$UR_ARG' (expected UR-NNN)" >&2
        exit 1
      fi
      ;;
    *)
      echo "ensure-integration-base.sh: invalid Issue slug '$UR_ARG' (expected UR-NNN)" >&2
      exit 1
      ;;
  esac
fi

if git show-ref --verify --quiet "refs/heads/$TARGET" 2>/dev/null; then
  if ! git checkout -q "$TARGET"; then
    echo "ensure-integration-base.sh: failed to checkout existing branch '$TARGET'" >&2
    exit 1
  fi
  # Update from the protected tip we left (merge main/master/… into new-work).
  if ! git merge -q --no-edit "$PROTECTED_TIP"; then
    echo "ensure-integration-base.sh: failed to merge '$PROTECTED_TIP' into '$TARGET'" >&2
    exit 1
  fi
else
  if ! git checkout -q -b "$TARGET"; then
    echo "ensure-integration-base.sh: failed to create branch '$TARGET'" >&2
    exit 1
  fi
fi

printf '%s\n' "$TARGET"
exit 0
