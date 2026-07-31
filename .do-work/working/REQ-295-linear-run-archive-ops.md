# REQ-295: Linear run pick deps footprint archive

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T05:52:20Z
**Heartbeat:** 2026-07-31T05:52:20Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-294
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** L
**Files:** agents/tracker/linear.md agents/run.md agents/run-worker.md agents/review.md
**Depends on:** REQ-294

## Task

Implement linear.md sequences for list_claimable_reqs ordering, footprint checks, archive_req, append_run_note; update run.md and run-worker.md to use port ops and Linear id branch naming (req/ENG-123). Review gate still applies before archive.

## Context

Design §15 testing; worktree isolation unchanged. Connector: semantics from parallel coordination design.

## Acceptance Criteria

- [ ] Worktree branch may use req/<linear-id> sanitized for git refs
- [ ] Review gate still required before archive when review.required
- [ ] append_run_note posts YAML-fenced ledger fields as Issue comment
- [ ] No Linear-aware bash required in lib/ for v1
- [ ] Failed review or failed acceptance-evidence gate does not call archive_req; issue stays in_progress/stopped with claim protocol intact
- [ ] Concurrent claim loss surfaces concurrent-conflict stopper with resume allowed (same semantics as markdown multi-agent mode)

## Verification Steps

1. **runtime** `grep -nE 'list_claimable|archive_req|append_run_note' agents/tracker/linear.md`
   - Expected: ops present
2. **runtime** `grep -nE 'tracker|port.md|linear' agents/run.md agents/run-worker.md | head`
   - Expected: run agents load tracker

## Integration

**Reachability:** /do-work run claim loop Step 1

**Data dependencies:** Linear issues + local .worktrees + state locks

**Service dependencies:** port ops; lib only for local runtime (provision-worktree, etc.)

## Outputs
