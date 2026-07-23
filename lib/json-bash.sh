#!/usr/bin/env bash
# json-bash.sh — shared JSON string primitives for do-work hot-path scripts.
#
# Source this file (do not exec):
#   . "$(dirname "$0")/json-bash.sh"
#
# Provides:
#   json_escape <string>
#     Escape a controlled value for embedding in a JSON string. Escapes
#     backslash, double-quote, and tab; strips CR/LF so a value can never
#     break the one-line-per-event contract.
#
#   json_string_field <json-text> <field-name>
#     Extract a top-level JSON string field's value via sed. Tolerant of
#     optional whitespace around the colon. Feeds sed a trailing newline so
#     BSD sed never preserves a missing final newline (which would glue
#     successive extracts, e.g. sess-Xsess-Y).
#
# Compatible with macOS bash 3.2 + BSD userland. No jq dependency. No python3.

# Guard against redefining when sourced multiple times in one shell.
if [ -n "${_DO_WORK_JSON_BASH_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
_DO_WORK_JSON_BASH_LOADED=1

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"        # backslash first
  s="${s//\"/\\\"}"        # double quote
  s="${s//$'\t'/\\t}"      # tab
  s="${s//$'\r'/}"         # strip CR
  s="${s//$'\n'/}"         # strip LF
  printf '%s' "$s"
}

json_string_field() {
  # $1 = JSON text (line or payload); $2 = field name
  # NOTE: feed sed a trailing newline. BSD sed preserves a missing final
  # newline, which would glue accumulated tokens together (sess-Xsess-Y).
  printf '%s\n' "$1" \
    | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | head -n1
}
