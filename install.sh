#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/do-work"
REPO_URL="https://github.com/rawphp/do-work.git"

if [ -d "$SKILL_DIR/.git" ]; then
  echo "do-work already installed. Updating..."
  git -C "$SKILL_DIR" pull --ff-only
  echo "Updated to latest."
elif [ -d "$SKILL_DIR" ]; then
  echo "Existing do-work directory found (not a git clone). Backing up and reinstalling..."
  mv "$SKILL_DIR" "$SKILL_DIR.bak.$(date +%s)"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR (old version backed up)"
else
  echo "Installing do-work skill..."
  mkdir -p "$(dirname "$SKILL_DIR")"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR"
fi

echo ""
echo "Done. The /do-work command is now available in Claude Code."
