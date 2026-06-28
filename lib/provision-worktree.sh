#!/usr/bin/env bash
# lib/provision-worktree.sh
# Provisions a git worktree's gitignored dependency directories.
#
# Symlinks dependency dirs (vendor, node_modules, .venv) from the main
# checkout into the worktree so test tooling can boot without a fresh
# install.  Falls back to a configured setup command if no main copy
# exists.
#
# Usage: provision-worktree.sh <main-checkout-root> <worktree-root>
#
# Always exits 0 — failure to provision a path is a reported outcome
# (unprovisionable: <path>), not a fatal error.  The script exits
# non-zero ONLY on usage or argument errors.
#
# Compatible with macOS bash 3.2.  No external runtime dependencies.

set -u

# -----------------------------------------------------------------------
# Usage guard
# -----------------------------------------------------------------------
if [ $# -ne 2 ]; then
  echo "Usage: $( basename "$0" ) <main-checkout-root> <worktree-root>" >&2
  exit 1
fi

MAIN_ROOT="$1"
WT_ROOT="$2"

if [ ! -d "$MAIN_ROOT" ]; then
  echo "Error: main checkout root not a directory: $MAIN_ROOT" >&2
  exit 1
fi

if [ ! -d "$WT_ROOT" ]; then
  echo "Error: worktree root not a directory: $WT_ROOT" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# Config: parse worktree.link_paths and worktree.setup_command from
# {main}/.do-work/config.yml.  Missing file or missing keys → empty.
# Minimal line-by-line state-machine reader; no yq/python required.
# -----------------------------------------------------------------------
CONFIG_FILE="$MAIN_ROOT/.do-work/config.yml"
LINK_PATHS=""   # newline-terminated entries, e.g. "vendor\nserver/vendor\n"
SETUP_CMD=""

_parse_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  local in_wt=0 in_lp=0

  while IFS= read -r line; do
    case "$line" in
      # ---- top-level worktree: key -----------------------------------
      "worktree:"*)
        in_wt=1; in_lp=0
        ;;
      # ---- 4-space list items: must precede the "  "* catch-all -----
      "    - "*)
        if [ "$in_wt" -eq 1 ] && [ "$in_lp" -eq 1 ]; then
          local item="${line#    - }"
          # strip trailing whitespace and optional surrounding quotes
          item="$(printf '%s' "$item" | sed 's/[[:space:]]*$//')"
          item="${item#\"}"
          item="${item%\"}"
          item="${item#\'}"
          item="${item%\'}"
          [ -n "$item" ] && LINK_PATHS="${LINK_PATHS}${item}
"
        fi
        ;;
      # ---- 2-space keys ----------------------------------------------
      "  link_paths:"*)
        [ "$in_wt" -eq 1 ] && in_lp=1
        ;;
      "  setup_command:"*)
        in_lp=0
        if [ "$in_wt" -eq 1 ]; then
          local raw="${line#*setup_command:}"
          # trim leading whitespace
          raw="${raw# }"
          # strip surrounding quotes
          raw="${raw#\"}"
          raw="${raw%\"}"
          raw="${raw#\'}"
          raw="${raw%\'}"
          SETUP_CMD="$raw"
        fi
        ;;
      # ---- any other 2-space-indented line resets link_paths mode ----
      "  "*)
        [ "$in_wt" -eq 1 ] && in_lp=0
        ;;
      # ---- new top-level key: leave worktree block -------------------
      [A-Za-z_-]*)
        in_wt=0; in_lp=0
        ;;
    esac
  done < "$CONFIG_FILE"
}

# -----------------------------------------------------------------------
# Target collection with deduplication
# -----------------------------------------------------------------------
TARGETS=""   # newline-terminated; each entry is one relative path

_add_target() {
  local path="$1"
  [ -n "$path" ] || return 0
  # Wrap with newlines so we can do an exact-line match.
  case "
${TARGETS}" in
    *"
${path}
"*) return 0 ;;   # already present
  esac
  TARGETS="${TARGETS}${path}
"
}

_manifest_to_dep() {
  case "$1" in
    "composer.json")    echo "vendor" ;;
    "package.json")     echo "node_modules" ;;
    "pyproject.toml")   echo ".venv" ;;
    "requirements.txt") echo ".venv" ;;
    *)                  ;;
  esac
}

# Auto-detect at worktree root (depth 0 → satisfies depth ≤ 2 overall)
for _m in composer.json package.json pyproject.toml requirements.txt; do
  if [ -f "$WT_ROOT/$_m" ]; then
    _d="$(_manifest_to_dep "$_m")"
    [ -n "$_d" ] && _add_target "$_d"
  fi
done

# Auto-detect in immediate subdirectories (depth 1 → total depth ≤ 2)
for _subdir in "$WT_ROOT"/*/; do
  [ -d "$_subdir" ] || continue
  _sname="$(basename "$_subdir")"
  for _m in composer.json package.json pyproject.toml requirements.txt; do
    if [ -f "${_subdir}${_m}" ]; then
      _d="$(_manifest_to_dep "$_m")"
      [ -n "$_d" ] && _add_target "${_sname}/${_d}"
    fi
  done
done

# Config-listed paths (additive, deduplicated)
_parse_config
_save_IFS="$IFS"
IFS='
'
for _p in $LINK_PATHS; do
  [ -n "$_p" ] && _add_target "$_p"
done
IFS="$_save_IFS"

# -----------------------------------------------------------------------
# Provision each target
# -----------------------------------------------------------------------
_setup_done=0

_provision() {
  local rel="$1"
  local wt_path="$WT_ROOT/$rel"
  local main_path="$MAIN_ROOT/$rel"

  # Already present in the worktree (real dir/file or an existing symlink) → skip
  if [ -e "$wt_path" ] || [ -L "$wt_path" ]; then
    return 0
  fi

  # Main checkout has it as a directory → symlink
  if [ -d "$main_path" ]; then
    mkdir -p "$(dirname "$wt_path")"
    ln -s "$main_path" "$wt_path"
    echo "linked: $rel"
    return 0
  fi

  # Setup command fallback — run at most once, then re-check
  if [ -n "$SETUP_CMD" ]; then
    if [ "$_setup_done" -eq 0 ]; then
      ( cd "$WT_ROOT" && eval "$SETUP_CMD" ) 2>/dev/null || true
      _setup_done=1
    fi
    if [ -e "$wt_path" ] || [ -L "$wt_path" ]; then
      echo "ran-setup: $rel"
      return 0
    fi
  fi

  echo "unprovisionable: $rel"
}

_save_IFS="$IFS"
IFS='
'
for _target in $TARGETS; do
  [ -n "$_target" ] && _provision "$_target"
done
IFS="$_save_IFS"

exit 0
