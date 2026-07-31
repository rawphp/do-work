# REQ-300: Idle markdown→Linear migration path


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** none
**Entry point:** /do-work upgrade migrate (or conformance migrate step) when working/ empty
**Terminal state:** All URs/REQs in Linear; tracker.backend linear; local user-requests/archive historical read-only; no dual-write
**Parent:** 
**Closure proof:** checkpoint_log:passed commit:1c0de08
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

- [x] Preflight: working empty, no active claims, operator confirms
- [x] Creates Initiatives/Projects/Issues for backlog+archive; maps status/relations/parents
- [x] Sets tracker.backend linear + team ids in config
- [x] Leaves markdown trees read-only historical; ops stop reading them
- [x] Supports dry-run reporting planned creates without write
- [x] If working/ is non-empty or active claims exist, migration refuses entirely (no partial cutover, config backend left unchanged)
- [x] If Linear MCP is unusable during migration, hard-stops with setup instructions and leaves markdown trees + config unchanged (no partial cutover)

## Verification Steps

1. **runtime** `grep -nE 'migrat|backend: linear|working/' agents/upgrade.md agents/tracker/linear.md | head`
   - Expected: migration UX documented

## Outputs

- agents/tracker/linear.md — migrate_markdown_to_linear M0–M7 sequence
- agents/tracker/port.md — catalog + contract for migrate_markdown_to_linear
- agents/upgrade.md — Step 9 /do-work upgrade migrate UX

