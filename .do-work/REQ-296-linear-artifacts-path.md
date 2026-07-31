# REQ-296: Linear non-ticket artifacts and close path

**UR:** UR-045
**Status:** backlog
**Created:** 2026-07-31
**Layer:** none
**Entry point:** capture append_decision; verify/close write reports; retro calibration; run notes
**Terminal state:** Artifacts live only in fixed Linear homes (§10); agents never invent ad-hoc locations
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** M
**Files:** agents/tracker/linear.md agents/close.md agents/verify.md agents/retro.md agents/capture.md
**Depends on:** REQ-291

## Task

Map decisions, calibration, verify, close, run notes to Linear homes and implement write/read ops.

## Context

Design §10; Done-when non-ticket homes fixed.

## Acceptance Criteria

- [ ] Decisions + calibration = Team Docs create-if-missing with configured titles
- [ ] Verify/close = Initiative sections + comments
- [ ] Run notes = Issue comments (+ optional Project update)
- [ ] Gate locks remain local state/*

## Verification Steps

1. **runtime** `grep -nE 'decisions_doc|calibration|write_verify|write_close|append_decision' agents/tracker/linear.md`
   - Expected: artifact ops present

## Outputs
