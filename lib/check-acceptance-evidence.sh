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

  i=$((i + 1))
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0

