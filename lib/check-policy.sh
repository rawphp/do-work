#!/usr/bin/env bash
# check-policy.sh — deterministic risk and security policy checks.
#
# Usage:
#   check-policy.sh --project <root> [--files <path>] [--commands <path>] [--req <path>]
#
# Exit codes:
#   0 clear
#   1 blocked security policy violation
#   2 review required by risk policy

set -u

PROJECT=""
FILES_PATH=""
COMMANDS_PATH=""
REQ_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --files) FILES_PATH="${2:-}"; shift 2 ;;
    --commands) COMMANDS_PATH="${2:-}"; shift 2 ;;
    --req) REQ_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,14p' "$0"
      exit 0
      ;;
    *)
      echo "check-policy.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "check-policy.sh: --project is required" >&2
  exit 1
fi

CONFIG="$PROJECT/.do-work/config.yml"

section_list() {
  local section="$1"
  local key="$2"
  local fallback="$3"
  if [ -f "$CONFIG" ]; then
    awk -v section="$section" -v key="$key" '
      $0 ~ "^" section ":" { in_section=1; next }
      in_section && /^[^[:space:]#][^:]*:/ { in_section=0 }
      in_section && $0 ~ "^[[:space:]]+" key ":" { in_key=1; next }
      in_key && /^[[:space:]]+[a-zA-Z0-9_.-]+:/ { in_key=0 }
      in_key && /^[[:space:]]*-[[:space:]]*/ {
        line=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        gsub(/^"|"$/, "", line)
        if (line != "") print line
      }
    ' "$CONFIG"
  else
    printf '%s\n' "$fallback"
  fi
}

with_default() {
  local value="$1"
  local fallback="$2"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

BLOCKED_PATHS="$(with_default "$(section_list security blocked_paths $'.env\n.env.*')" $'.env\n.env.*')"
BLOCKED_COMMANDS_DEFAULT=$'rm -rf\ngit push --force\ngit push -f\ngit reset --hard\ngit checkout --'
BLOCKED_COMMANDS="$(with_default "$(section_list security blocked_commands "$BLOCKED_COMMANDS_DEFAULT")" "$BLOCKED_COMMANDS_DEFAULT")"
RISK_RULES="$(with_default "$(section_list risk require_review $'migrations\nauth\nbilling\npayments\nfiles_changed_over: 8\nacceptance_criteria_over: 6')" $'migrations\nauth\nbilling\npayments\nfiles_changed_over: 8\nacceptance_criteria_over: 6')"

BLOCKED=0
REVIEW=0

path_matches() {
  local path="$1"
  local pattern="$2"
  case "$pattern" in
    *'*'*|*'?'*)
      case "$path" in $pattern) return 0 ;; */$pattern) return 0 ;; *) return 1 ;; esac
      ;;
    *)
      [ "$path" = "$pattern" ] || [ "$path" = "./$pattern" ] || [ "${path##*/}" = "$pattern" ]
      ;;
  esac
}

# Escape every ERE metacharacter in $1 so it matches literally under grep -E.
regex_escape() {
  printf '%s' "$1" | sed 's/[][(){}.^$*+?|\\\/]/\\&/g'
}

# Render the permutations of a short-flag cluster (e.g. "rf") as an ERE that
# matches the flags combined in any order (-rf, -fr) or split into separate
# args (-r -f, -f -r). Clusters longer than 3 flags fall back to a literal
# match of the cluster as written to avoid combinatorial blow-up.
flag_cluster_regex() {
  local letters="$1"
  local n="${#letters}"
  case "$n" in
    2)
      local a="${letters:0:1}" b="${letters:1:1}"
      printf -- '-(%s%s|%s%s)|-%s[[:space:]]+-%s|-%s[[:space:]]+-%s' \
        "$a" "$b" "$b" "$a" "$a" "$b" "$b" "$a"
      ;;
    3)
      local a="${letters:0:1}" b="${letters:1:1}" c="${letters:2:1}"
      printf -- '-(%s%s%s|%s%s%s|%s%s%s|%s%s%s|%s%s%s|%s%s%s)' \
        "$a" "$b" "$c" "$a" "$c" "$b" "$b" "$a" "$c" \
        "$b" "$c" "$a" "$c" "$a" "$b" "$c" "$b" "$a"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$a" "$b" "$c"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$a" "$c" "$b"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$b" "$a" "$c"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$b" "$c" "$a"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$c" "$a" "$b"
      printf '|-%s[[:space:]]+-%s[[:space:]]+-%s' "$c" "$b" "$a"
      ;;
    *)
      regex_escape "-$letters"
      ;;
  esac
}

# Build an ERE for a default-mode blocked_commands entry. Whitespace-separated
# tokens are joined by [[:space:]]+; short-flag clusters (-rf) become flag-order
# -insensitive alternations; everything else is matched literally (regex-escaped).
entry_to_regex() {
  local entry="$1"
  local out="" tok first=1
  for tok in $entry; do
    local piece
    case "$tok" in
      -[A-Za-z][A-Za-z]|-[A-Za-z][A-Za-z][A-Za-z])
        piece="($(flag_cluster_regex "${tok#-}"))"
        ;;
      *)
        piece="$(regex_escape "$tok")"
        ;;
    esac
    if [ "$first" -eq 1 ]; then
      out="$piece"
      first=0
    else
      out="$out[[:space:]]+$piece"
    fi
  done
  printf '%s' "$out"
}

# Return 0 if $command_line matches $blocked_command under REQ-205 semantics.
#   substr:<text>  -> literal substring match (legacy behaviour)
#   <text>         -> ERE match anchored on word boundaries, with rm-style
#                     flag-order normalisation
command_matches() {
  local command_line="$1"
  local entry="$2"
  case "$entry" in
    substr:*)
      local literal="${entry#substr:}"
      case "$command_line" in
        *"$literal"*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      local core
      core="$(entry_to_regex "$entry")"
      [ -z "$core" ] && return 1
      # Word boundaries are shell-token boundaries: the entry must appear bounded
      # by whitespace or line start/end. This is why `production` matches the
      # standalone token but not the `production-notes` path fragment.
      printf '%s\n' "$command_line" \
        | grep -Eq "(^|[[:space:]])($core)([[:space:]]|$)"
      ;;
  esac
}

if [ -n "$FILES_PATH" ] && [ -f "$FILES_PATH" ]; then
  while IFS= read -r changed_path; do
    [ -z "$changed_path" ] && continue
    while IFS= read -r blocked_path; do
      [ -z "$blocked_path" ] && continue
      if path_matches "$changed_path" "$blocked_path"; then
        echo "blocked_path: $changed_path matches $blocked_path"
        BLOCKED=1
      fi
    done <<EOF
$BLOCKED_PATHS
EOF
  done < "$FILES_PATH"
fi

if [ -n "$COMMANDS_PATH" ] && [ -f "$COMMANDS_PATH" ]; then
  while IFS= read -r command_line; do
    [ -z "$command_line" ] && continue
    while IFS= read -r blocked_command; do
      [ -z "$blocked_command" ] && continue
      if command_matches "$command_line" "$blocked_command"; then
        echo "blocked_command: $blocked_command"
        BLOCKED=1
      fi
    done <<EOF
$BLOCKED_COMMANDS
EOF
  done < "$COMMANDS_PATH"
fi

FILES_CHANGED=0
if [ -n "$FILES_PATH" ] && [ -f "$FILES_PATH" ]; then
  FILES_CHANGED="$(awk 'NF { count++ } END { print count+0 }' "$FILES_PATH")"
fi

AC_COUNT=0
if [ -n "$REQ_PATH" ] && [ -f "$REQ_PATH" ]; then
  AC_COUNT="$(awk '
    /^## Acceptance Criteria/ { in_ac=1; next }
    /^## / && in_ac { in_ac=0 }
    in_ac && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ { count++ }
    END { print count+0 }
  ' "$REQ_PATH")"
fi

while IFS= read -r rule; do
  [ -z "$rule" ] && continue
  key="$rule"
  value=""
  case "$rule" in
    *:*)
      key="$(printf '%s' "$rule" | sed 's/:.*//;s/[[:space:]]//g')"
      value="$(printf '%s' "$rule" | sed 's/^[^:]*:[[:space:]]*//')"
      ;;
  esac

  case "$key" in
    files_changed_over)
      if [ "$FILES_CHANGED" -gt "${value:-999999}" ] 2>/dev/null; then
        echo "review_required: files_changed_over ($FILES_CHANGED > $value)"
        REVIEW=1
      fi
      ;;
    acceptance_criteria_over)
      if [ "$AC_COUNT" -gt "${value:-999999}" ] 2>/dev/null; then
        echo "review_required: acceptance_criteria_over ($AC_COUNT > $value)"
        REVIEW=1
      fi
      ;;
    *)
      if [ -n "$FILES_PATH" ] && [ -f "$FILES_PATH" ] && grep -Eiq "(^|/|[-_])$key(/|[-_.]|$)" "$FILES_PATH"; then
        echo "review_required: $key"
        REVIEW=1
      fi
      ;;
  esac
done <<EOF
$RISK_RULES
EOF

if [ "$BLOCKED" -ne 0 ]; then
  exit 1
fi
if [ "$REVIEW" -ne 0 ]; then
  exit 2
fi
exit 0
