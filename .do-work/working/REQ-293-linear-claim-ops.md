# REQ-293: Implement Linear claim heartbeat status ops

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:40:07Z
**Heartbeat:** 2026-07-31T05:40:07Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-292
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** L
**Files:** agents/tracker/linear.md agents/status.md agents/unblock.md agents/resume.md agents/run.md
**Depends on:** REQ-292

## Task

Document and wire claim_req, heartbeat_req, set_req_status, unblock_req, list_claimable_reqs, and status reporting for Linear backend. Update status/unblock/resume/run agent text to use port ops (Linear sequences in linear.md).

## Context

Design §8 example claim comment; multi-agent safety without FS rename.

## Acceptance Criteria

- [ ] Example claim comment block matches design §8
- [ ] list_claimable_reqs: project filter + backlog state + deps via relations + footprint from Files + unclaimed
- [ ] status agent can render Linear claimers/heartbeats for a UR Project
- [ ] Mid-flight failure policy stated: leave claimed; resume/unblock

## Verification Steps

1. **runtime** `grep -n 'agent_claim_marker\|do-work-claim' agents/tracker/linear.md`
   - Expected: marker documented
2. **runtime** `grep -n tracker agents/status.md agents/unblock.md agents/resume.md`
   - Expected: agents reference tracker/port

## Integration

**Reachability:** run orchestrator claim step; /do-work status|unblock|resume

**Data dependencies:** Issue comments + workflow state; human assignee

**Service dependencies:** port claim_req/heartbeat_req; Linear MCP comments API

## Outputs
