#!/usr/bin/env bash
# budget-gate.fixture.sh — runtime demonstration of REQ-226's budget gate.
#
# Simulates the run loop's Step 3b.1 enforcement against real ledger entries:
# two REQs complete in sequence; a budget set BELOW the cumulative cost of the
# second REQ must let REQ 1 archive, then trip the gate at the REQ-2 boundary
# (spent >= budget) so the loop stops with a budget-stop report before claiming
# the next REQ. Uses lib/run-ledger.sh --cost-estimate (writer) and --sum-run
# (the gate's arithmetic). This mirrors run.md's prose, which the orchestrator
# executes; the script proves the underlying numeric gate is honest.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LEDGER="$( cd "$SCRIPT_DIR/.." && pwd )/run-ledger.sh"

TMP="$(mktemp -d -t budget-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.do-work/runs"
cat > "$TMP/.do-work/config.yml" <<'EOF'
ledger:
  enabled: true
EOF
REQ1="$TMP/.do-work/archive/REQ-101.md"; REQ2="$TMP/.do-work/archive/REQ-102.md"
mkdir -p "$TMP/.do-work/archive"
printf '# REQ-101\n\n**UR:** UR-035\n' > "$REQ1"
printf '# REQ-102\n\n**UR:** UR-035\n' > "$REQ2"

# Effective budget for this fixture: $4.00. REQ 2's own estimate ($2.50) pushes
# the cumulative total over the budget -> "budget set below the second REQ's
# estimate" relative to remaining headroom after REQ 1.
BUDGET="4.00"

echo "=== Budget gate runtime fixture (budget = \$$BUDGET) ==="

# --- REQ 1 completes: worker attempt writes its ledger entry (est $2.00) ---
bash "$LEDGER" --project "$TMP" --req "$REQ1" --result done --review passed \
  --cost-estimate "2.00" >/dev/null
SPENT_AFTER_1="$(bash "$LEDGER" --sum-run "$TMP/.do-work/runs")"
echo "REQ-101 integrated. Estimated spend: \$$SPENT_AFTER_1 / budget \$$BUDGET"
if awk -v s="$SPENT_AFTER_1" -v b="$BUDGET" 'BEGIN{exit (s+0 < b+0)?0:1}'; then
  echo "  -> under budget: loop CONTINUES, claims REQ-102."
else
  echo "FAIL: gate tripped too early after REQ-101 (spent=$SPENT_AFTER_1)"; exit 1
fi

# --- REQ 2 completes: its ledger entry (est $2.50) crosses the budget ---
bash "$LEDGER" --project "$TMP" --req "$REQ2" --result done --review passed \
  --cost-estimate "2.50" >/dev/null
SPENT_AFTER_2="$(bash "$LEDGER" --sum-run "$TMP/.do-work/runs")"
echo "REQ-102 integrated (in-flight integration always completes first)."
echo "Estimated spend: \$$SPENT_AFTER_2 / budget \$$BUDGET"
if awk -v s="$SPENT_AFTER_2" -v b="$BUDGET" 'BEGIN{exit (s+0 >= b+0)?0:1}'; then
  echo "  -> budget reached at REQ boundary: GATE TRIPS."
else
  echo "FAIL: gate did not trip after REQ-102 (spent=$SPENT_AFTER_2)"; exit 1
fi

if [ "$SPENT_AFTER_2" != "4.50" ]; then
  echo "FAIL: expected cumulative 4.50, got $SPENT_AFTER_2"; exit 1
fi

echo ""
echo "Budget reached — stopping at REQ boundary."
echo "Estimated spend: \$$SPENT_AFTER_2 / budget \$$BUDGET   (tier-weighted estimate)"
echo "REQs completed this run: 2"
echo "REQs remaining in backlog: (loop stops BEFORE claiming the next REQ)"
echo "Last integrated: REQ-102"
echo ""
echo "PASS: REQ-101 archived under budget; gate tripped at REQ-102 boundary; loop stops."
exit 0
