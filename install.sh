#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/do-work"
BACKUP_DIR="$HOME/.claude/backups"
REPO_URL="https://github.com/rawphp/do-work.git"

# Move-aside helper: relocates an existing install OUT of ~/.claude/skills/
# (where the harness scans for SKILL.md) into ~/.claude/backups/ so the
# backup is not re-registered as a duplicate skill.
move_aside() {
  local src="$1"
  mkdir -p "$BACKUP_DIR"
  local dest="$BACKUP_DIR/do-work.bak.$(date +%s)"
  mv "$src" "$dest"
  echo "Backed up previous install to $dest"
}

usage() {
  cat <<EOF
Usage: $0 [--from-cwd | --source <path>]

Default behavior: git clone (or update) from $REPO_URL into $SKILL_DIR.

Options:
  --from-cwd        Symlink from the current working directory instead of cloning
  --source <path>   Symlink from the given path instead of cloning
  -h, --help        Show this help
EOF
}

SOURCE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from-cwd)
      SOURCE_DIR="$(pwd)"
      shift
      ;;
    --source)
      if [ $# -lt 2 ]; then
        echo "Error: --source requires a path argument" >&2
        exit 1
      fi
      SOURCE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -n "$SOURCE_DIR" ]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

  if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: source directory does not exist: $SOURCE_DIR" >&2
    exit 1
  fi

  if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
    echo "Warning: $SOURCE_DIR does not contain a SKILL.md — is this the right directory?" >&2
  fi

  if [ -d "$SKILL_DIR" ] && [ ! -L "$SKILL_DIR" ]; then
    echo "Existing do-work directory found at $SKILL_DIR (not a symlink). Backing up..."
    move_aside "$SKILL_DIR"
  fi

  if [ -L "$SKILL_DIR" ]; then
    rm "$SKILL_DIR"
  fi

  mkdir -p "$(dirname "$SKILL_DIR")"
  ln -s "$SOURCE_DIR" "$SKILL_DIR"

  echo "Symlinked $SOURCE_DIR -> $SKILL_DIR"
  echo "Done. The /do-work command is now available in Claude Code."
  exit 0
fi

if [ -d "$SKILL_DIR/.git" ]; then
  echo "do-work already installed. Updating..."
  git -C "$SKILL_DIR" pull --ff-only
  echo "Updated to latest."
elif [ -L "$SKILL_DIR" ]; then
  echo "Existing do-work symlink found at $SKILL_DIR. Removing and reinstalling from $REPO_URL..."
  rm "$SKILL_DIR"
  mkdir -p "$(dirname "$SKILL_DIR")"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR"
elif [ -d "$SKILL_DIR" ]; then
  echo "Existing do-work directory found (not a git clone). Backing up and reinstalling..."
  move_aside "$SKILL_DIR"
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
