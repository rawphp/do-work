# REQ-290: Linear UR/REQ CRUD path

**UR:** UR-045
**Status:** backlog
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work intake or start with tracker.backend: linear and valid team config
**Terminal state:** Initiative + Project do-work/{UR-id} + Issues/sub-issues exist with §9 templates; create/read/list/update ops work
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** M
**Files:** agents/tracker/linear.md
**Depends on:** REQ-289

## Task

Implement Linear work-item create/read/update/list for URs and REQs per hierarchy §6 and templates §9, without claim/run coordination yet.

## Context

Design §6, §9; phasing step 2 after spike.

## Acceptance Criteria

- [ ] create_ur: Initiative + Project do-work/{UR-id} + link
- [ ] create_req/update_req/read_req/list_reqs_for_ur against Project
- [ ] Issue body uses §9.2 template; path-units use parentId sub-issues
- [ ] Linear issue ids only (e.g. ENG-123) — no parallel REQ-NNN allocation in Linear mode
- [ ] If Linear MCP tools are undiscoverable or team_id unresolved at create_ur/create_req time, hard-stop with setup instructions — no partial Initiative without Project, no markdown dual-write

## Verification Steps

1. **runtime** `grep -nE 'create_ur|create_req|do-work/\{ur' agents/tracker/linear.md`
   - Expected: CRUD sequences documented

## Outputs
