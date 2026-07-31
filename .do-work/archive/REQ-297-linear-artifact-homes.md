# REQ-297: Implement Linear artifact home ops


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-296
**Closure proof:** checkpoint:.do-work/runs#REQ-297 commit:2fbecbc tests:passed
**Criteria approved:** agent-drafted
**Priority:** 2
**Size:** L
**Files:** agents/tracker/linear.md agents/close.md agents/verify.md agents/retro.md agents/capture.md agents/ideate.md agents/question.md agents/run-worker.md
**Depends on:** REQ-296

## Task

Implement append_decision, write_verify_report, write_close_report, calibration doc read/write, append_run_note consumers in linear.md; point capture/ideate/question/verify/close/retro at port ops.

## Context

Design §10 table; decisions one-line format preserved.

## Acceptance Criteria

- [x] Doc titles from config decisions_doc_title / calibration_doc_title
- [x] Same one-line decisions grammar as .do-work/decisions.md
- [x] Close agent walks path-units using Linear issue ids
- [x] Retro prefers Linear run notes when backend=linear
- [x] If Team Doc create/update or Initiative description append fails (permission or size), hard-stop — agents must not invent ad-hoc issue comments or alternate doc titles outside §10 homes

## Verification Steps

1. **runtime** `grep -nE 'append_decision|write_close_report|do-work/decisions' agents/tracker/linear.md`
   - Expected: homes implemented in doc
2. **runtime** `grep -n tracker agents/close.md agents/verify.md agents/retro.md | head`
   - Expected: agents reference tracker

## Integration

**Reachability:** capture decision write; verify/close/retro phases

**Data dependencies:** Team Docs; Initiative description sections

**Service dependencies:** Linear Docs MCP; port artifact ops

## Outputs
