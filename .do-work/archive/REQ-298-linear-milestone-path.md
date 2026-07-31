# REQ-298: Linear milestone mode path


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** none
**Entry point:** Milestone-shaped UR (saas-thesis handoff + ### Milestones) with backend linear
**Terminal state:** Active milestone cursor on Project description; list_milestone_reqs filters; deploy gate via local gate-owner.md with human y/n
**Parent:** 
**Closure proof:** checkpoint:.do-work/runs#REQ-298 commit:70f18a9 tests:passed
**Criteria approved:** agent-drafted
**Priority:** 1
**Size:** M
**Files:** agents/tracker/linear.md agents/capture.md agents/run.md
**Depends on:** REQ-295 REQ-297

## Task

Support milestone mode under Linear without changing trigger shape or local deploy-gate ownership.

## Context

Design §11; runtime gate locks stay local.

## Acceptance Criteria

- [x] Trigger unchanged (source + ### Milestones)
- [x] Cursor in Project description <!-- do-work-milestone -->
- [x] Deploy gate first orchestrator owns local state/gate-owner.md
- [x] list_milestone_reqs / set_active_milestone / read_active_milestone ops work

## Verification Steps

1. **runtime** `grep -nE 'do-work-milestone|list_milestone|gate-owner' agents/tracker/linear.md agents/run.md | head`
   - Expected: milestone markers present

## Outputs
