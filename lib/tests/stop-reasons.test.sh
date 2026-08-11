#!/usr/bin/env bash
# Tests for lib/stop-reasons.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# stop-reasons.sh is the single canonical source of do-work's stop-reason
# vocabulary. It prints the worker set (--worker), the orchestrator set
# (--orchestrator), or the order-preserving deduped union (--all), one reason
# per line, exit 0. A missing or unknown selector must exit non-zero with a
# usage line on stderr — the vocabulary is only consulted via a known selector,
# so an ambiguous invocation is rejected rather than silently printing nothing.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/stop-reasons.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

TMP="$(mktemp -d -t stop-reasons-test.XXXXXX)"
OUT="$TMP/out"
ERR="$TMP/err"
trap 'rm -rf "$TMP"' EXIT

# run_sel "<selector>"  -> invokes the script with that selector.
# run_sel "__NONE__"    -> invokes the script with no argument at all.
run_sel() {
  local sel="$1"
  : > "$OUT"; : > "$ERR"
  if [ "$sel" = "__NONE__" ]; then
    bash "$SCRIPT" >"$OUT" 2>"$ERR"
  else
    bash "$SCRIPT" "$sel" >"$OUT" 2>"$ERR"
  fi
  RC=$?
  STDOUT="$(cat "$OUT")"
  STDERR="$(cat "$ERR")"
}

EXPECTED_WORKER="tests-failing
verification-failing
missing-creds
ambiguous-criteria
scope-creep
dependency-missing
unknown-error
concurrent-conflict"

EXPECTED_ORCH="policy-blocked
review-failed
archive-integrity
path-unit-incomplete
missing-closure-proof"

# ---- --worker ----------------------------------------------------------------
CURRENT_CASE="worker-rc"
CASES=$((CASES + 1))
run_sel "--worker"
assert_eq "0" "$RC" "$CURRENT_CASE rc"

CURRENT_CASE="worker-exact"
CASES=$((CASES + 1))
assert_eq "$EXPECTED_WORKER" "$STDOUT" "$CURRENT_CASE stdout (exact set + order)"

CURRENT_CASE="worker-count"
CASES=$((CASES + 1))
assert_eq "8" "$(wc -l < "$OUT" | tr -d '[:space:]')" "$CURRENT_CASE line count"

CURRENT_CASE="worker-stderr-empty"
CASES=$((CASES + 1))
assert_eq "" "$STDERR" "$CURRENT_CASE stderr empty"

# ---- --orchestrator ----------------------------------------------------------
CURRENT_CASE="orch-rc"
CASES=$((CASES + 1))
run_sel "--orchestrator"
assert_eq "0" "$RC" "$CURRENT_CASE rc"

CURRENT_CASE="orch-exact"
CASES=$((CASES + 1))
assert_eq "$EXPECTED_ORCH" "$STDOUT" "$CURRENT_CASE stdout (exact set + order)"

CURRENT_CASE="orch-count"
CASES=$((CASES + 1))
assert_eq "5" "$(wc -l < "$OUT" | tr -d '[:space:]')" "$CURRENT_CASE line count"

# ---- --all (union, dedup) ----------------------------------------------------
CURRENT_CASE="all-rc"
CASES=$((CASES + 1))
run_sel "--all"
assert_eq "0" "$RC" "$CURRENT_CASE rc"

CURRENT_CASE="all-count"
CASES=$((CASES + 1))
assert_eq "13" "$(wc -l < "$OUT" | tr -d '[:space:]')" "$CURRENT_CASE line count (13 distinct)"

CURRENT_CASE="all-unique"
CASES=$((CASES + 1))
# Dedup proof: sorted-unique line count must equal the raw line count (13).
assert_eq "13" "$(sort -u "$OUT" | wc -l | tr -d '[:space:]')" "$CURRENT_CASE sorted-unique count"

CURRENT_CASE="all-shared-once"
CASES=$((CASES + 1))
# concurrent-conflict is shared (worker claim race + orchestrator merge conflict)
# and must appear exactly once under --all.
assert_eq "1" "$(grep -c '^concurrent-conflict$' "$OUT")" "$CURRENT_CASE concurrent-conflict appears once"

CURRENT_CASE="all-union"
CASES=$((CASES + 1))
# --all must equal the deduped union of worker ∪ orchestrator (order-insensitive).
UNION="$(printf '%s\n%s\n' "$EXPECTED_WORKER" "$EXPECTED_ORCH" | sort -u)"
ALL_SORTED="$(sort -u "$OUT")"
assert_eq "$UNION" "$ALL_SORTED" "$CURRENT_CASE union == worker ∪ orchestrator"

# ---- error path: no selector -------------------------------------------------
CURRENT_CASE="none-rc-nonzero"
CASES=$((CASES + 1))
run_sel "__NONE__"
if [ "$RC" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero rc for missing selector, got 0"
fi

CURRENT_CASE="none-usage-stderr"
CASES=$((CASES + 1))
case "$STDERR" in
  *[Uu]sage*) : ;;
  *) fail "$CURRENT_CASE: expected a usage line on stderr, got: $STDERR" ;;
esac

# ---- error path: unknown flag ------------------------------------------------
CURRENT_CASE="bogus-rc-nonzero"
CASES=$((CASES + 1))
run_sel "--bogus"
if [ "$RC" -eq 0 ]; then
  fail "$CURRENT_CASE: expected non-zero rc for unknown selector, got 0"
fi

CURRENT_CASE="bogus-usage-stderr"
CASES=$((CASES + 1))
case "$STDERR" in
  *[Uu]sage*) : ;;
  *) fail "$CURRENT_CASE: expected a usage line on stderr, got: $STDERR" ;;
esac

# ---- worker-doc sync with canonical source (anti-drift, REQ-008) -------------
# run-worker.md hand-lists the 8 worker reasons in its "Never invent stopper
# reasons" rule for readability. To prevent that prose drifting from
# lib/stop-reasons.sh (the canonical source from REQ-007), this section locks:
#   1. The rule NAMES lib/stop-reasons.sh and its --worker subset (AC1).
#   2. The rule's enumerated enum set equals `stop-reasons.sh --worker`
#      exactly — same set, no extras, none missing (AC2).
#
# Extraction strategy (deliberate, not free-form prose grep):
# The 8 reasons live in a single clause of the rule:
#     "... MUST be one of the documented enum values: `a`, `b`, ... `concurrent-conflict`. Do not improvise ..."
# We isolate that clause (text between "documented enum values:" and
# "Do not improvise") and extract every backtick-wrapped token matching
# [a-z][a-z-]+ inside it. That clause contains ONLY the enum reasons by
# construction — the rule's non-example tokens (`awaiting-human-verification`,
# `status: deferred`, `deferred_checks:`) sit AFTER "Do not improvise", outside
# the clause — so the extracted sorted set is exactly the worker enum.
# Mutation-proof: dropping/renaming a reason in either the doc or the script,
# or removing the canonical-source reference, makes this fail loudly.
REPO_ROOT="$( cd "$LIB_DIR/.." && pwd )"
RUN_WORKER_MD="$REPO_ROOT/agents/run-worker.md"

CURRENT_CASE="worker-doc-names-canonical-source"
CASES=$((CASES + 1))
RULE_LINE="$(grep 'Never invent stopper reasons' "$RUN_WORKER_MD" || true)"
if [ -z "$RULE_LINE" ]; then
  fail "$CURRENT_CASE: no 'Never invent stopper reasons' rule found in $RUN_WORKER_MD"
fi
case "$RULE_LINE" in
  *lib/stop-reasons.sh*--worker*) : ;;
  *) fail "$CURRENT_CASE: rule must name lib/stop-reasons.sh and its --worker subset" ;;
esac

CURRENT_CASE="worker-doc-sync-set"
CASES=$((CASES + 1))
# Isolate the enum clause, extract backtick reason tokens, compare sorted set.
DOC_CLAUSE="$(printf '%s' "$RULE_LINE" | grep -o 'documented enum values:.*Do not improvise' || true)"
DOC_REASON_SET="$(printf '%s\n' "$DOC_CLAUSE" | grep -oE '`[a-z][a-z-]+`' | tr -d '`' | sort -u)"
run_sel "--worker"
SCRIPT_REASON_SET="$(sort -u "$OUT")"
assert_eq "$SCRIPT_REASON_SET" "$DOC_REASON_SET" "$CURRENT_CASE run-worker.md enum == stop-reasons.sh --worker (sorted)"

CURRENT_CASE="worker-doc-sync-count"
CASES=$((CASES + 1))
# Sanity: exactly 8 distinct reason tokens in the clause (not 7, not 9).
DOC_REASON_COUNT="$(printf '%s\n' "$DOC_CLAUSE" | grep -oE '`[a-z][a-z-]+`' | tr -d '`' | sort -u | wc -l | tr -d '[:space:]')"
assert_eq "8" "$DOC_REASON_COUNT" "$CURRENT_CASE clause enumerates exactly 8 worker reasons"

echo ""
echo "stop-reasons tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
