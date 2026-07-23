#!/usr/bin/env bash
# install-target.sh — resolve the shared skills-hub install directory for do-work.
# Aligns with install.sh: single target under AGENTS_SKILLS_HUB / ~/.agents/skills.

set -u

resolve_do_work_install_target() {
  local home_dir="${1:-$HOME}"
  local hub

  if [ -n "${AGENTS_SKILLS_HUB:-}" ]; then
    hub="$AGENTS_SKILLS_HUB"
  else
    hub="$home_dir/.agents/skills"
  fi

  printf '%s|%s|%s\n' "$hub/do-work" "$hub/.backups" "skills hub"
}

if [ "${1:-}" = "--resolve" ]; then
  resolve_do_work_install_target "${2:-$HOME}"
fi
