# REQ-294: Linear run coordination path

**UR:** UR-045
**Status:** backlog
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work run with backend linear
**Terminal state:** Worker can pick claim deps footprint archive a REQ using Linear as sole work-item store; worktrees/git remain local; commit messages use Linear issue ids
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** M
**Files:** agents/tracker/linear.md agents/run.md agents/run-worker.md
**Depends on:** REQ-293

## Task

Close the run loop on Linear: pick/claim/deps/footprint/archive_req + append_run_note; local runtime unchanged.

## Context

Design §5.5 runtime stays local; §6.5 commit convention; phasing step 5.

## Acceptance Criteria

- [ ] archive_req sets done + closure proof + outputs on Issue
- [ ] Footprint overlap uses **Files:** from issue bodies of in-progress claims
- [ ] Deps satisfaction uses blocks relations (authoritative)
- [ ] Commit/PR message format uses Linear issue id per §6.5
- [ ] Optional local ledger telemetry when ledger.enabled without becoming second work-item store
- [ ] Mid-flight Linear MCP failure after claim leaves the issue claimed (active claim comment + in_progress); worker stops for resume/unblock — never silent-releases and never falls back to markdown store

## Verification Steps

1. **runtime** `grep -nE 'archive_req|append_run_note|feat\(ENG' agents/tracker/linear.md agents/run.md agents/run-worker.md | head`
   - Expected: archive and commit convention present

## Outputs
