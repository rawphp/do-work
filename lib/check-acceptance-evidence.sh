#!/usr/bin/env bash
# check-acceptance-evidence.sh — validate per-criterion worker evidence.
#
# Usage:
#   check-acceptance-evidence.sh <req-path> <worker-report-yml>
#
# The report must contain:
# acceptance:
#   AC1:
#     status: passed
#     evidence:
#       - type: test
#         ref: ...
#
# Keys are AC1..ACn, matching acceptance criteria order in the REQ.
#
# For type: ui (or ui: shorthand), ref MUST be a path to an existing image
# under .do-work/user-requests/.../ui-evidence/ (or any path containing
# ui-evidence and ending in a common image extension). Soft ui claims
# without a screenshot path fail the gate (UR-043).

set -u

REQ_PATH="${1:-}"
REPORT_PATH="${2:-}"

if [ -z "$REQ_PATH" ] || [ -z "$REPORT_PATH" ]; then
  echo "Usage: check-acceptance-evidence.sh <req-path> <worker-report-yml>" >&2
  exit 1
fi
if [ ! -e "$REQ_PATH" ]; then
  echo "check-acceptance-evidence.sh: REQ not found: $REQ_PATH" >&2
  exit 1
fi
if [ ! -e "$REPORT_PATH" ]; then
  echo "check-acceptance-evidence.sh: report not found: $REPORT_PATH" >&2
  exit 1
fi

# Resolve project root: walk up from the REQ path until we find .do-work/ sibling or parent.
resolve_project_root() {
  local start dir
  start="$(cd "$(dirname "$REQ_PATH")" && pwd)"
  dir="$start"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.do-work" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    # REQ lives inside .do-work/working or .do-work itself
    if [ "$(basename "$dir")" = ".do-work" ]; then
      printf '%s\n' "$(dirname "$dir")"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fall back: parent of the directory containing the REQ
  printf '%s\n' "$(cd "$(dirname "$REQ_PATH")/../.." && pwd 2>/dev/null || pwd)"
}

PROJECT_ROOT="$(resolve_project_root)"

is_image_path() {
  local p="$1"
  case "$p" in
    *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP|*.gif|*.GIF) return 0 ;;
    *) return 1 ;;
  esac
}

# Validate every type: ui evidence item in a YAML acceptance block.
# Emits diagnostics to stderr; returns non-zero if any ui item is invalid.
validate_ui_evidence_in_block() {
  local key="$1"
  local block="$2"
  local failed=0
  local line type_line ref_line ref candidate

  # Walk the block: when we see type: ui (or - ui:), require a following ref with screenshot path.
  type_line=""
  ref_line=""
  while IFS= read -r line; do
    if echo "$line" | grep -Eq '^[[:space:]]*-[[:space:]]*type:[[:space:]]*ui[[:space:]]*$' \
      || echo "$line" | grep -Eq '^[[:space:]]*type:[[:space:]]*ui[[:space:]]*$' \
      || echo "$line" | grep -Eq '^[[:space:]]*-[[:space:]]*ui:'; then
      type_line="$line"
      ref_line=""
      # For shorthand "- ui: path" the path may be on the same line
      if echo "$line" | grep -Eq '^[[:space:]]*-[[:space:]]*ui:'; then
        ref="$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*ui:[[:space:]]*//')"
        ref="$(echo "$ref" | sed -E 's/^["'\'']//; s/["'\'']$//')"
        if [ -z "$ref" ]; then
          echo "acceptance evidence ui missing screenshot ref: $key" >&2
          failed=1
        else
          if ! is_image_path "$ref"; then
            echo "acceptance evidence ui ref is not an image path: $key ($ref)" >&2
            failed=1
          elif ! echo "$ref" | grep -Eq 'ui-evidence'; then
            echo "acceptance evidence ui ref must be under ui-evidence/: $key ($ref)" >&2
            failed=1
          else
            candidate="$ref"
            if [ "${ref#/}" = "$ref" ]; then
              # relative — try project root
              candidate="$PROJECT_ROOT/$ref"
            fi
            if [ ! -f "$candidate" ] && [ ! -f "$ref" ]; then
              echo "acceptance evidence ui screenshot file missing: $key ($ref)" >&2
              failed=1
            fi
          fi
        fi
        type_line=""
      fi
      continue
    fi

    if [ -n "$type_line" ]; then
      if echo "$line" | grep -Eq '^[[:space:]]*ref:'; then
        ref="$(echo "$line" | sed -E 's/^[[:space:]]*ref:[[:space:]]*//')"
        ref="$(echo "$ref" | sed -E 's/^["'\'']//; s/["'\'']$//')"
        if [ -z "$ref" ]; then
          echo "acceptance evidence ui missing screenshot ref: $key" >&2
          failed=1
        elif ! is_image_path "$ref"; then
          echo "acceptance evidence ui ref is not an image path: $key ($ref)" >&2
          failed=1
        elif ! echo "$ref" | grep -Eq 'ui-evidence'; then
          echo "acceptance evidence ui ref must be under ui-evidence/: $key ($ref)" >&2
          failed=1
        else
          candidate="$ref"
          if [ "${ref#/}" = "$ref" ]; then
            candidate="$PROJECT_ROOT/$ref"
          fi
          if [ ! -f "$candidate" ] && [ ! -f "$ref" ]; then
            echo "acceptance evidence ui screenshot file missing: $key ($ref)" >&2
            failed=1
          fi
        fi
        type_line=""
      elif echo "$line" | grep -Eq '^[[:space:]]*-[[:space:]]*(type:|test:|command:|file:|runtime_check:|ui:)'; then
        # Next evidence item without a ref on the previous ui item
        echo "acceptance evidence ui missing screenshot ref: $key" >&2
        failed=1
        type_line=""
      fi
    fi
  done <<EOF
$block
EOF

  # Trailing type: ui without ref at end of block
  if [ -n "$type_line" ]; then
    echo "acceptance evidence ui missing screenshot ref: $key" >&2
    failed=1
  fi

  return "$failed"
}

AC_COUNT="$(awk '
  /^## Acceptance Criteria/ { in_ac=1; next }
  /^## / && in_ac { in_ac=0 }
  in_ac && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ { count++ }
  END { print count+0 }
' "$REQ_PATH")"

if [ "$AC_COUNT" -eq 0 ]; then
  echo "check-acceptance-evidence.sh: no acceptance criteria found" >&2
  exit 1
fi

FAILED=0
i=1
while [ "$i" -le "$AC_COUNT" ]; do
  key="AC$i"
  block="$(awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":" { in_key=1; print; next }
    in_key && /^[[:space:]]*AC[0-9]+:/ { in_key=0 }
    in_key { print }
  ' "$REPORT_PATH")"

  if [ -z "$block" ]; then
    echo "missing acceptance evidence: $key" >&2
    FAILED=1
    i=$((i + 1))
    continue
  fi

  echo "$block" | grep -Eq '^[[:space:]]*status:[[:space:]]*passed[[:space:]]*$'
  if [ "$?" -ne 0 ]; then
    echo "acceptance evidence not passed: $key" >&2
    FAILED=1
  fi

  echo "$block" | grep -Eq '^[[:space:]]*-[[:space:]]*(type:|test:|command:|file:|runtime_check:|ui:)'
  if [ "$?" -ne 0 ]; then
    echo "acceptance evidence missing evidence item: $key" >&2
    FAILED=1
  fi

  # UI screenshot hard gate (UR-043): only when block contains a ui evidence item
  if echo "$block" | grep -Eq 'type:[[:space:]]*ui|^[[:space:]]*-[[:space:]]*ui:'; then
    if ! validate_ui_evidence_in_block "$key" "$block"; then
      FAILED=1
    fi
  fi

  i=$((i + 1))
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
