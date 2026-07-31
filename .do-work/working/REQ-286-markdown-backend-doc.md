# REQ-286: Write agents/tracker/markdown.md mapping

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:16:14Z
**Heartbeat:** 2026-07-31T05:16:14Z
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
**Files:** agents/tracker/markdown.md lib/claim-req.sh lib/pick-req.sh lib/check-deps.sh lib/check-footprint.sh lib/heartbeat.sh
**Depends on:** REQ-285

## Task

Document how each port op maps to existing file paths and lib/*.sh (claim-req.sh, pick-req.sh, check-deps.sh, check-footprint.sh, heartbeat.sh, etc.). Markdown remains the default backend implementation — no behavior change required beyond documentation that freezes the mapping.

## Context

Design §5.1–5.3; Connector: reuse parallel coordination semantics, not reimplement. lib/*.sh stay markdown-backend only.

## Acceptance Criteria

- [ ] Every op in port.md has a markdown implementation note (script path and/or file glob)
- [ ] Explicitly states no Linear-aware bash required for markdown backend
- [ ] Claim atomicity documented as mv/git mv race (exit 2) matching claim-req.sh
- [ ] Mapping never invents a lib/*.sh path that does not exist in the repo; missing scripts are called out as gaps, not invented

## Verification Steps

1. **runtime** `grep -n claim_req agents/tracker/markdown.md && grep -n claim-req.sh agents/tracker/markdown.md`
   - Expected: claim_req maps to claim-req.sh
2. **runtime** `grep -nE 'pick-req|check-deps|check-footprint|heartbeat' agents/tracker/markdown.md`
   - Expected: coordination libs mapped

## Integration

**Reachability:** Loaded when tracker.backend is markdown or unset

**Data dependencies:** .do-work/REQ-*.md, working/, archive/, user-requests/

**Service dependencies:** lib/claim-req.sh lib/pick-req.sh lib/check-deps.sh lib/check-footprint.sh lib/heartbeat.sh

## Outputs
