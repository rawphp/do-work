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
#   - On protected default + dirty tree → hard-stop non-zero; no branch change,
#     no stash. Message on stderr mentions dirty working tree.
#   - On protected default + clean + UR-NNN arg → create-if-missing and
#     checkout ur/UR-NNN from current HEAD; print final branch; exit 0.
#   - On protected default + clean + no UR arg → create/checkout
#     work/<UTC-timestamp>; print final branch; exit 0.
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

if ! is_protected "$CURRENT"; then
  printf '%s\n' "$CURRENT"
  exit 0
fi

# --- on protected default: dirty tree is a hard-stop ------------------------

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "ensure-integration-base.sh: working tree is dirty on protected branch '$CURRENT' — clean the tree (commit or discard) before creating an integration base; refusing to stash or switch" >&2
  exit 1
fi

# --- leave default: ur/UR-NNN or work/<UTC-timestamp> -----------------------

TARGET=""
UR_ARG="${1:-}"

if [ -n "$UR_ARG" ]; then
  # Accept UR-NNN style (UR- + digits). Reject other shapes.
  case "$UR_ARG" in
    UR-[0-9]*)
      # require full match: UR- then only digits
      if printf '%s' "$UR_ARG" | grep -Eq '^UR-[0-9]+$'; then
        TARGET="ur/$UR_ARG"
      else
        echo "ensure-integration-base.sh: invalid UR slug '$UR_ARG' (expected UR-NNN)" >&2
        exit 1
      fi
      ;;
    *)
      echo "ensure-integration-base.sh: invalid UR slug '$UR_ARG' (expected UR-NNN)" >&2
      exit 1
      ;;
  esac
else
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  TARGET="work/$ts"
fi

if git show-ref --verify --quiet "refs/heads/$TARGET" 2>/dev/null; then
  if ! git checkout -q "$TARGET"; then
    echo "ensure-integration-base.sh: failed to checkout existing branch '$TARGET'" >&2
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
