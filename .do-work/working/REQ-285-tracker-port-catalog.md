# REQ-285: Write agents/tracker/port.md op catalog

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:12:09Z
**Heartbeat:** 2026-07-31T05:12:09Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-283
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** M
**Files:** agents/tracker/port.md
**Depends on:** REQ-283 REQ-284

## Task

Create agents/tracker/port.md defining the shared op catalog (~create_ur, read_ur, list_urs, append_ideate, create_req, claim_req, list_claimable_reqs, archive_req, etc. per design §5.4), preconditions, claim/deps/footprint semantic rules, mid-flight MCP failure rule (leave claimed; resume/unblock repairs), and deps authority (Linear relations authoritative; body is mirror).

## Context

Design §5.4 Operation catalog; §8 claim; clarifications on mid-flight failure and relations-authoritative deps. Shared rules only — no backend-specific tool calls.

## Acceptance Criteria

- [ ] Every op name from design §5.4 appears with intent and preconditions
- [ ] Documents: Linear unusable ⇒ hard stop never silent markdown fallback
- [ ] Documents: mid-flight MCP failure leaves claim active; resume/unblock repair
- [ ] Documents: deps eligibility uses native blocks relations as authority; body **Depends on:** is mirror
- [ ] Documents work-item vs runtime split (design §5.5)

## Verification Steps

1. **runtime** `test -f agents/tracker/port.md && grep -cE '^[|] `?[a-z_]+`?' agents/tracker/port.md || grep -c create_ur agents/tracker/port.md`
   - Expected: op catalog present with create_ur and peers
2. **runtime** `grep -nE 'hard stop|relations authoritative|leave claimed' agents/tracker/port.md`
   - Expected: clarification rules present

## Integration

**Reachability:** Phase agents read agents/tracker/port.md after config load (design §5.2)

**Data dependencies:** Op names are the only work-item storage API for phase agents

**Service dependencies:** agents/config.md tracker.backend resolution

## Outputs
