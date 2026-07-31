# REQ-299: Implement Linear milestone cursor ops

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.32234
**Claimed at:** 2026-07-31T06:28:55Z
**Heartbeat:** 2026-07-31T06:28:55Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-298
**Closure proof:**
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

- [ ] Project description marker format documented and parsed
- [ ] Siblings idle on deploy gate same as markdown mode
- [ ] write_gate_state remains local-allowed
- [ ] When Project description has no milestone marker, `read_active_milestone` returns empty/not-in-milestone (does not invent a milestone id)
- [ ] Concurrent gate ownership still serializes via local `state/gate-owner.md` even when milestone content is remote

## Verification Steps

1. **runtime** `grep -nE 'read_active_milestone|set_active_milestone|list_milestone_reqs' agents/tracker/linear.md`
   - Expected: ops present

## Integration

**Reachability:** capture milestone decompose; run milestone drain/gate

**Data dependencies:** Project description milestone marker; local gate-owner.md

**Service dependencies:** port milestone ops; run.md gate flow

## Outputs
