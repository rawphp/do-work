# REQ-288: Linear MCP capability spike path

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:16:15Z
**Heartbeat:** 2026-07-31T05:16:15Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** none
**Entry point:** Operator sets sandbox Linear team; agent runs spike against live MCP tools
**Terminal state:** Capability matrix committed (which tools exist for Initiatives, Projects, InitiativeToProject, issue relations, Team Docs) and hard-stop copy validated; CRUD REQs unblocked
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** M
**Files:** agents/tracker/linear.md docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md
**Depends on:** REQ-285

## Task

Prove on a sandbox Linear team that the hierarchy and non-ticket homes are implementable via live MCP tools before wiring full Linear CRUD into the loop.

## Context

Clarification: Spike first, then implement. Design §17 risk #1 MCP thin tools. Linear skill requires search_tool rediscovery.

## Acceptance Criteria

- [ ] Spike produces a written matrix of available tools vs required ops (Initiatives, Projects, link, relations/blocks, Docs, comments, workflow states)
- [ ] Hard-stop message when MCP missing is verified (setup instructions, no invented data)
- [ ] status_map validation against real team states documented (defaults + hard fail if missing)
- [ ] No production work-item migration in this path

## Verification Steps

1. **runtime** `grep -nE 'Initiative|blocks|Doc|hard.stop|capability' agents/tracker/linear.md | head`
   - Expected: spike findings land in linear.md

## Manual checks (advisory)

- [ ] Connect Linear MCP (OAuth) to a sandbox team and confirm tools via search_tool — Observable: linear tools listed, not handshake failure

## Outputs
