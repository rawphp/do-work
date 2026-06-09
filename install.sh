#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rawphp/do-work.git"
ENV_NAME=""

resolve_do_work_install_target() {
  local env_name="${1:-}"
  local home_dir="${2:-$HOME}"

  case "$env_name" in
    claude)
      printf '%s|%s|%s\n' "$home_dir/.claude/skills/do-work" "$home_dir/.claude/backups" "Claude Code"
      ;;
    codex)
      printf '%s|%s|%s\n' "$home_dir/.codex/skills/do-work" "$home_dir/.codex/backups" "Codex"
      ;;
    *)
      echo "Error: invalid --env '$env_name'. Valid values: claude, codex" >&2
      return 1
      ;;
  esac
}

choose_env() {
  if [ -n "$ENV_NAME" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "Error: --env is required when stdin is non-interactive. Use --env claude or --env codex." >&2
    exit 1
  fi

  echo "Install do-work for which environment?"
  echo "  1) Claude Code"
  echo "  2) Codex"
  printf "Choice [1/2]: "
  read -r choice
  case "$choice" in
    1|claude|Claude|CLAUDE) ENV_NAME="claude" ;;
    2|codex|Codex|CODEX) ENV_NAME="codex" ;;
    *) echo "Error: choose 1 for Claude Code or 2 for Codex." >&2; exit 1 ;;
  esac
}

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
Usage: $0 --env <claude|codex> [--from-cwd | --source <path>]

Default behavior: git clone (or update) from $REPO_URL into the selected skill directory.

Options:
  --env claude     Install into ~/.claude/skills/do-work
  --env codex      Install into ~/.codex/skills/do-work
  --from-cwd        Symlink from the current working directory instead of cloning
  --source <path>   Symlink from the given path instead of cloning
  -h, --help        Show this help
EOF
}

SOURCE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      if [ $# -lt 2 ]; then
        echo "Error: --env requires claude or codex" >&2
        exit 1
      fi
      ENV_NAME="$2"
      shift 2
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

choose_env
TARGET_INFO="$(resolve_do_work_install_target "$ENV_NAME")"
IFS='|' read -r SKILL_DIR BACKUP_DIR ENV_LABEL <<EOF
$TARGET_INFO
EOF

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
  echo "Done. The /do-work command is now available in $ENV_LABEL."
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
echo "Done. The /do-work command is now available in $ENV_LABEL."
