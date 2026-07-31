# REQ-300: Idle markdown→Linear migration path

**UR:** UR-045
**Status:** backlog
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work upgrade migrate (or conformance migrate step) when working/ empty
**Terminal state:** All URs/REQs in Linear; tracker.backend linear; local user-requests/archive historical read-only; no dual-write
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 1
**Size:** M
**Files:** agents/upgrade.md agents/tracker/linear.md agents/tracker/port.md
**Depends on:** REQ-297 REQ-291

## Task

One-shot idle migration per design §12, surfaced via upgrade/conformance (clarification + UR-039).

## Context

Design §12; clarification migration under upgrade.

## Acceptance Criteria

- [ ] Preflight: working empty, no active claims, operator confirms
- [ ] Creates Initiatives/Projects/Issues for backlog+archive; maps status/relations/parents
- [ ] Sets tracker.backend linear + team ids in config
- [ ] Leaves markdown trees read-only historical; ops stop reading them
- [ ] Supports dry-run reporting planned creates without write

## Verification Steps

1. **runtime** `grep -nE 'migrat|backend: linear|working/' agents/upgrade.md agents/tracker/linear.md | head`
   - Expected: migration UX documented

## Outputs
