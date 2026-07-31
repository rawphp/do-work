# REQ-284: Add tracker.* config schema and validation


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-283
**Closure proof:** checkpoint:.do-work/runs#REQ-284 commit:8949762 tests:passed
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** M
**Files:** agents/config.md SKILL.md
**Depends on:** REQ-283

## Task

Add tracker.backend and tracker.linear.* schema (design §7) to agents/config.md canonical template and schema reference. Document defaults (backend markdown). When backend is linear, document hard-fail rules: team unresolved, MCP tools undiscoverable, status_map state missing on team.

## Context

Design §7 Config schema; clarification: defaults + hard fail on missing workflow state. Interaction with ledger/parallel remains valid.

## Acceptance Criteria

- [x] config template includes tracker.backend default markdown and tracker.linear keys from design §7
- [x] Schema reference documents validation: backend=linear requires resolvable team and discoverable Linear MCP tools
- [x] status_map defaults match design; missing team workflow state is hard-fail with rename instructions
- [x] Load Config section describes resolving tracker.backend (default markdown if missing/empty)

## Verification Steps

1. **runtime** `grep -n 'tracker:' agents/config.md | head`
   - Expected: tracker section present in canonical template
2. **runtime** `grep -nE 'backend: markdown|status_map|team_id' agents/config.md`
   - Expected: key fields documented

## Integration

**Reachability:** agents/config.md Load Config — every phase agent already loads this first (agents/start.md Step 0, etc.)

**Data dependencies:** .do-work/config.yml project config values

**Service dependencies:** agents/config.md Load Config migration of missing keys

## Outputs
