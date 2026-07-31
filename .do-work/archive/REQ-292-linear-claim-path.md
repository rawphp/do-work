# REQ-292: Linear claim and status path


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work run|status|unblock|resume with backend linear
**Terminal state:** Optimistic claim comment protocol works; status reports claimers/heartbeats; unblock/resume match markdown semantics; mid-flight failure leaves claimed
**Parent:** 
**Closure proof:** checkpoint:.do-work/runs#REQ-292 commit:a911cb5 tests:passed
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

- [x] Claim uses agent_claim_marker comment + workflow in_progress; assignee not stolen
- [x] Heartbeat updates; stale uses heartbeat_max_age_seconds or parallel.stale_threshold_seconds
- [x] Unblock → backlog + claim status released
- [x] Resume refreshes heartbeat; concurrent-conflict stopper when claim race lost

## Verification Steps

1. **runtime** `grep -nE 'do-work-claim|heartbeat|unblock|list_claimable' agents/tracker/linear.md`
   - Expected: claim protocol sections present

## Outputs
