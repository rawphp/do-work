#!/usr/bin/env bash
# drain-classify.sh — classify pick-req.sh stderr into a drain category.
#
# Usage:
#   pick-req.sh ... 2>&1 >/dev/null | drain-classify.sh
#   drain-classify.sh < pick-stderr.log
#
# Reads stdin until EOF. Scans for line-anchored prefixes emitted by
# pick-req.sh's rejection log:
#   dep:<id>      — REQ <id> rejected because a dependency is unsatisfied
#   overlap:<id>  — REQ <id> rejected because of a sibling overlap claim
#   scope:<id>    — REQ <id> rejected because it falls outside the active UR scope
#
# Emits exactly one label on stdout, with precedence:
#   overlap-blocked > deps-blocked > scope-blocked > truly-empty
#
# Rationale: overlap-blocked is the most actionable — a sibling finishing
# unblocks the slot immediately. deps-blocked is next: dependency progress
# unblocks the REQ. scope-blocked indicates a scope/UR change is required.
# truly-empty means there is nothing left in the backlog to consider.
#
# Exit 0 in all cases. Empty stdin → truly-empty.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep).

set -u

HAS_DEP=0
HAS_OVERLAP=0
HAS_SCOPE=0

# Read entire stdin into memory. Inputs are bounded by pick-req.sh's
# stderr volume, so this is safe.
INPUT="$(cat)"

if [ -n "$INPUT" ]; then
  # Line-anchored prefix scan via grep -E. -q for silent, exit status
  # tells us presence.
  if printf '%s\n' "$INPUT" | grep -qE '^overlap:'; then
    HAS_OVERLAP=1
  fi
  if printf '%s\n' "$INPUT" | grep -qE '^dep:'; then
    HAS_DEP=1
  fi
  if printf '%s\n' "$INPUT" | grep -qE '^scope:'; then
    HAS_SCOPE=1
  fi
fi

if [ "$HAS_OVERLAP" -eq 1 ]; then
  echo "overlap-blocked"
elif [ "$HAS_DEP" -eq 1 ]; then
  echo "deps-blocked"
elif [ "$HAS_SCOPE" -eq 1 ]; then
  echo "scope-blocked"
else
  echo "truly-empty"
fi

exit 0
