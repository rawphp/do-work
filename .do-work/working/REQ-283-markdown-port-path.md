# REQ-283: Markdown-default tracker port path

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.98424
**Claimed at:** 2026-07-31T04:59:22Z
**Heartbeat:** 2026-07-31T04:59:22Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work phase agents with tracker.backend unset or markdown
**Terminal state:** All work-item ops resolve through agents/tracker/port.md + markdown.md; existing lib tests and conformance pass without Linear
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** M
**Files:** agents/tracker/port.md agents/tracker/markdown.md agents/config.md SKILL.md
**Depends on:** 

## Task

Define the reachable path for markdown-default multi-tracker: config resolves backend to markdown, agents load port + markdown backend, and product behavior matches today.

## Context

Design §2 goals 1 and Done-when #1; §5 load path; clarification: full map in one UR ordered by §16 phasing.

## Acceptance Criteria

- [ ] Path-unit documents entry (default/markdown backend) and terminal (regression green, no Linear required)
- [ ] Child REQs under this path implement config, port catalog, markdown mapping, and agent load-path wiring
- [ ] No dual-write or Linear requirement on this path
- [ ] When tracker.backend is unset or empty, resolution treats backend as markdown (no hard-stop, no Linear tools required)

## Verification Steps

1. **runtime** `test -f agents/tracker/port.md && test -f agents/tracker/markdown.md`
   - Expected: both backend docs exist after children complete
2. **test** `bash lib/tests/*.test.sh 2>/dev/null | tail -5; bash lib/conformance-scan.sh . || true`
   - Expected: markdown regression surface still runnable

## Outputs
