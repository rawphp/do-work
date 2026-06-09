#!/usr/bin/env bash
# install-target.sh — resolve do-work skill install directories.

set -u

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

if [ "${1:-}" = "--resolve" ]; then
  resolve_do_work_install_target "${2:-}" "${3:-$HOME}"
fi

