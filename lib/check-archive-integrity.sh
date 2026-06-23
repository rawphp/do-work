#!/usr/bin/env bash
# check-archive-integrity.sh — deterministic gate run immediately before a REQ
# is archived as `done`. It rejects the write when the REQ is internally
# inconsistent, so a malformed `done` REQ can never reach `archive/`.
#
# Usage:
#   check-archive-integrity.sh <req-path>
#
# Asserts, for a REQ the orchestrator intends to archive:
#   1. **Status:** is `done`.
#   2. **Closure proof:** exists and is non-empty (the done oracle).
#   3. No acceptance criterion inside the `## Acceptance Criteria` section is
#      left unchecked (`- [ ]`).
#
# Exit 0 when all hold; exit 1 with a diagnostic on the first/each violation.
#
# This is the guardrail behind run.md Step 4b / 4-pr.4 and approve.md: the
# worker is *instructed* (run-worker.md) to set status, write closure proof, and
# tick each `- [x]`, but that is prose an LLM follows unreliably. This check is
# the persistence-boundary enforcement that makes the bad write impossible.

set -u

REQ_PATH="${1:-}"

if [ -z "$REQ_PATH" ]; then
  echo "Usage: check-archive-integrity.sh <req-path>" >&2
  exit 1
fi
if [ ! -e "$REQ_PATH" ]; then
  echo "check-archive-integrity.sh: REQ not found: $REQ_PATH" >&2
  exit 1
fi

extract_field() {
  grep -m1 -E "^\*\*$1:\*\*[[:space:]]*" "$REQ_PATH" 2>/dev/null \
    | sed -E "s/^\*\*$1:\*\*[[:space:]]*//"
}

FAILED=0
REQ_ID="$(basename "$REQ_PATH" | grep -oE '^REQ-(M[0-9]+-)?[0-9]+' || echo 'REQ-UNKNOWN')"

# 1. Status must be done.
STATUS="$(extract_field "Status")"
if [ "$STATUS" != "done" ]; then
  echo "check-archive-integrity.sh: $REQ_ID status not done (got '$STATUS')" >&2
  FAILED=1
fi

# 2. Closure proof must be present and non-empty.
PROOF="$(extract_field "Closure proof")"
if [ -z "$PROOF" ]; then
  echo "check-archive-integrity.sh: $REQ_ID missing closure proof" >&2
  FAILED=1
fi

# 3. No unchecked acceptance criteria inside the Acceptance Criteria section.
UNCHECKED="$(awk '
  /^## *Acceptance Criteria/ { in_ac=1; next }
  /^## / && in_ac { in_ac=0 }
  in_ac && /^[[:space:]]*-[[:space:]]*\[[[:space:]]\]/ { count++ }
  END { print count+0 }
' "$REQ_PATH")"
if [ "$UNCHECKED" -gt 0 ]; then
  echo "check-archive-integrity.sh: $REQ_ID unchecked acceptance criteria: $UNCHECKED" >&2
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
