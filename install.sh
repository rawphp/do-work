#!/usr/bin/env bash
set -euo pipefail

# Install do-work into the active skills hub (~/.agents/skills).
# Default: git clone/update. Use --from-cwd / --source for a live symlink.

REPO_URL="${DO_WORK_REPO_URL:-https://github.com/agent-native/do-work.git}"
HUB="${AGENTS_SKILLS_HUB:-$HOME/.agents/skills}"
SKILL_DIR="$HUB/do-work"
BACKUP_DIR="$HUB/.backups"
SOURCE_DIR=""

usage() {
  cat <<EOF
Usage: $0 [--from-cwd | --source <path>]

Default: git clone (or update) into the skills hub:
  $SKILL_DIR

Options:
  --from-cwd        Symlink from the current working directory
  --source <path>   Symlink from the given path
  -h, --help        Show this help

Note: --env is ignored; all agents share the hub.
EOF
}

move_aside() {
  local src="$1"
  mkdir -p "$BACKUP_DIR"
  local dest="$BACKUP_DIR/do-work.bak.$(date +%s)"
  mv "$src" "$dest"
  echo "Backed up previous install to $dest"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      echo "Note: --env is ignored; skills install into the shared hub only." >&2
      shift
      [ $# -ge 1 ] && shift || true
      continue
      ;;
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

mkdir -p "$HUB"

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
  ln -s "$SOURCE_DIR" "$SKILL_DIR"
  echo "Symlinked $SOURCE_DIR -> $SKILL_DIR (skills hub)"
  echo "Done."
  exit 0
fi

if [ -d "$SKILL_DIR/.git" ]; then
  echo "do-work already installed. Updating..."
  git -C "$SKILL_DIR" pull --ff-only
  echo "Updated to latest."
elif [ -L "$SKILL_DIR" ]; then
  echo "Existing do-work symlink found at $SKILL_DIR. Removing and reinstalling from $REPO_URL..."
  rm "$SKILL_DIR"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR"
elif [ -d "$SKILL_DIR" ]; then
  echo "Existing do-work directory found (not a git clone). Backing up and reinstalling..."
  move_aside "$SKILL_DIR"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR (old version backed up)"
else
  echo "Installing do-work skill..."
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "Installed to $SKILL_DIR"
fi

echo ""
echo "Done. Skill available to any agent wired to the hub ($HUB)."
