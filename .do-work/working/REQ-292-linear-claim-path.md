# REQ-292: Linear claim and status path

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:35:09Z
**Heartbeat:** 2026-07-31T05:35:09Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work run|status|unblock|resume with backend linear
**Terminal state:** Optimistic claim comment protocol works; status reports claimers/heartbeats; unblock/resume match markdown semantics; mid-flight failure leaves claimed
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** M
**Files:** agents/tracker/linear.md
**Depends on:** REQ-291

## Task

Ship claim/heartbeat/unblock/resume/status/list_claimable_reqs on Linear per §8 with human assignee preserved.

## Context

Design §8; clarification leave claimed on MCP death.

## Acceptance Criteria

- [ ] Claim uses agent_claim_marker comment + workflow in_progress; assignee not stolen
- [ ] Heartbeat updates; stale uses heartbeat_max_age_seconds or parallel.stale_threshold_seconds
- [ ] Unblock → backlog + claim status released
- [ ] Resume refreshes heartbeat; concurrent-conflict stopper when claim race lost

## Verification Steps

1. **runtime** `grep -nE 'do-work-claim|heartbeat|unblock|list_claimable' agents/tracker/linear.md`
   - Expected: claim protocol sections present

## Outputs
