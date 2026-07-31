# REQ-299: Implement Linear milestone cursor ops


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-298
**Closure proof:** checkpoint_log:passed commit:9e1638a
**Criteria approved:** agent-drafted
**Priority:** 1
**Size:** M
**Files:** agents/tracker/linear.md agents/capture.md agents/run.md
**Depends on:** REQ-298

## Task

Implement read/set active milestone and list_milestone_reqs in linear.md; ensure capture/run milestone branches call port ops under Linear backend.

## Context

Design §11; label M1 or Project milestone entity when MCP supports it.

## Acceptance Criteria

- [x] Project description marker format documented and parsed
- [x] Siblings idle on deploy gate same as markdown mode
- [x] write_gate_state remains local-allowed
- [x] When Project description has no milestone marker, `read_active_milestone` returns empty/not-in-milestone (does not invent a milestone id)
- [x] Concurrent gate ownership still serializes via local `state/gate-owner.md` even when milestone content is remote

## Verification Steps

1. **runtime** `grep -nE 'read_active_milestone|set_active_milestone|list_milestone_reqs' agents/tracker/linear.md`
   - Expected: ops present

## Integration

**Reachability:** capture milestone decompose; run milestone drain/gate

**Data dependencies:** Project description milestone marker; local gate-owner.md

**Service dependencies:** port milestone ops; run.md gate flow

## Outputs

- agents/tracker/linear.md — REQ-299 path unit + complete read/set/list milestone ops, parse algorithm, empty→null, concurrent local write_gate_state
- agents/capture.md — Linear milestone branches call port ops; null cursor does not invent id on read
- agents/run.md — Linear filter/idle-wait/gate drain call port ops; local gate-owner concurrent serialize

