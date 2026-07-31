# REQ-289: Run Linear MCP spike and draft linear.md skeleton

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:20:59Z
**Heartbeat:** 2026-07-31T05:20:59Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-288
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** L
**Files:** agents/tracker/linear.md
**Depends on:** REQ-288

## Task

Using Linear skill protocol (search_tool → use_tool live), discover tools on sandbox team; write agents/tracker/linear.md skeleton with capability matrix, hard-stop setup instructions, and notes on gaps (GraphQL fallbacks). Do not implement full op sequences yet beyond discovery probes.

## Context

Clarification spike-first; ~/.grok/skills/linear/SKILL.md MCP-first rediscovery.

## Acceptance Criteria

- [ ] agents/tracker/linear.md exists with capability matrix table
- [ ] Documents hard-stop when MCP unauthenticated/missing with Linear skill setup steps
- [ ] Records whether Initiatives, InitiativeToProject, issue relations, Team Docs are available
- [ ] No secrets committed

## Verification Steps

1. **runtime** `test -f agents/tracker/linear.md && grep -n 'capability\|tool' agents/tracker/linear.md | head`
   - Expected: skeleton with matrix present
2. **runtime** `grep -nE 'hard stop|OAuth|mcp.linear' agents/tracker/linear.md`
   - Expected: setup hard-stop copy present

## Manual checks (advisory)

- [ ] Execute discovery against sandbox team in a session with Linear MCP connected — Observable: matrix rows filled from live tools not guesses

## Integration

**Reachability:** Read when tracker.backend=linear after port.md

**Data dependencies:** tracker.linear.team_id / team_key from config

**Service dependencies:** Linear MCP via search_tool/use_tool; linear skill SKILL.md

## Outputs
