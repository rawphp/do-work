# REQ-291: Linear templates and CRUD op sequences

**UR:** UR-045
**Status:** backlog
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-290
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** L
**Files:** agents/tracker/linear.md
**Depends on:** REQ-290

## Task

Flesh linear.md with Initiative/Issue templates (§9) and full MCP sequences for create_ur, read_ur, list_urs, append_ideate, append_clarifications, create_req, update_req, read_req, list_reqs_for_ur, set_files, set_blocked_by (relations + body mirror).

## Context

Design §9 templates; clarification relations authoritative with body mirror on write.

## Acceptance Criteria

- [ ] Templates match design §9.1 and §9.2 including machine markers <!-- do-work-ur --> and <!-- do-work-req -->
- [ ] set_blocked_by creates blocks relations and mirrors **Depends on:**
- [ ] Labels Layer/*, Size/*, path-unit documented
- [ ] status_map used for workflow states; validation hard-fails missing states

## Verification Steps

1. **runtime** `grep -n 'do-work-ur\|do-work-req' agents/tracker/linear.md`
   - Expected: template markers present
2. **runtime** `grep -nE 'blocks|Depends on|set_blocked_by' agents/tracker/linear.md`
   - Expected: deps dual-write documented

## Integration

**Reachability:** intake/capture/ideate/question call these ops when backend=linear

**Data dependencies:** Linear Initiative/Project/Issue; tracker.linear config

**Service dependencies:** port.md op names; Linear MCP

## Outputs
