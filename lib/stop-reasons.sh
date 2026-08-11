#!/usr/bin/env bash
# Canonical stop-reason vocabulary for do-work.
#
# Single source of truth for the reasons a worker may stop (worker set) and
# the reasons an orchestrator may stop (orchestrator set). The stranded-REQ
# triage and the run-worker / run-orchestrator enums all consult this list so
# the two hand-listed copies cannot drift.
#
# Usage:
#   bash lib/stop-reasons.sh --worker        # 8 worker-written reasons
#   bash lib/stop-reasons.sh --orchestrator  # 5 orchestrator-assigned reasons
#   bash lib/stop-reasons.sh --all           # deduped union (13 distinct)
#
# Prints one reason per line to stdout, exit 0. A missing or unknown selector
# exits non-zero with a usage line on stderr — the vocabulary is only ever
# consulted via a known selector, so an ambiguous invocation is rejected
# rather than silently printing nothing.
#
# `concurrent-conflict` is shared: written by the worker on a claim race and
# by the orchestrator on a merge conflict, so it appears exactly once under
# --all (order-preserving dedup).
#
# Plain bash, macOS 3.2-compatible (indexed arrays + case; no namerefs).

set -u

WORKER_REASONS=(
  tests-failing
  verification-failing
  missing-creds
  ambiguous-criteria
  scope-creep
  dependency-missing
  unknown-error
  concurrent-conflict
)

ORCHESTRATOR_REASONS=(
  policy-blocked
  review-failed
  archive-integrity
  path-unit-incomplete
  missing-closure-proof
)

usage() {
  echo "Usage: $(basename "$0") [--worker|--orchestrator|--all]" >&2
  echo "Print the canonical stop-reason vocabulary, one reason per line." >&2
}

emit_worker() {
  local r
  for r in "${WORKER_REASONS[@]}"; do
    printf '%s\n' "$r"
  done
}

emit_orchestrator() {
  local r
  for r in "${ORCHESTRATOR_REASONS[@]}"; do
    printf '%s\n' "$r"
  done
}

emit_all() {
  # Union of worker ∪ orchestrator with order-preserving dedup. Iterates the
  # worker list first, then the orchestrator list, skipping any token already
  # emitted. concurrent-conflict sits in the worker list, so the orchestrator
  # copy is skipped -> exactly one occurrence in --all.
  local seen=" "
  local r
  for r in "${WORKER_REASONS[@]}" "${ORCHESTRATOR_REASONS[@]}"; do
    case "$seen" in
      *" $r "*) : ;;              # already emitted — skip
      *) seen="$seen$r "; printf '%s\n' "$r" ;;
    esac
  done
}

selector="${1:-}"
case "$selector" in
  --worker)       emit_worker ;;
  --orchestrator) emit_orchestrator ;;
  --all)          emit_all ;;
  "")             usage; exit 2 ;;
  *)              usage; echo "error: unknown selector: $selector" >&2; exit 2 ;;
esac
