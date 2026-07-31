# REQ-301: Wire migration into upgrade/conformance


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-300
**Closure proof:** checkpoint_log:passed commit:abe6087
**Criteria approved:** agent-drafted
**Priority:** 1
**Size:** L
**Files:** agents/upgrade.md agents/tracker/linear.md lib/conformance-scan.sh lib/tests/conformance-scan.test.sh
**Depends on:** REQ-300

## Task

Add upgrade/conformance path for idle migration with dry-run flag; implement migration sequences in linear.md; never migrate when working/ non-empty.

## Context

UR-039 upgrade centralization; design §12 step 7 no dual-write after cutover.

## Acceptance Criteria

- [x] Destructive/confirm gate for migration (operator confirmation)
- [x] Dry-run lists planned Linear creates without writing
- [x] Post-cutover work-item ops ignore historical markdown trees
- [x] Idempotent enough to re-run safely or clearly refuse if already linear
- [x] When `tracker.backend` is already `linear`, upgrade migrate refuses or reports already-migrated without rewriting Issues

## Verification Steps

1. **runtime** `grep -nE 'migrat|dry-run|tracker.backend' agents/upgrade.md`
   - Expected: upgrade mentions migration
2. **runtime** `grep -nE 'preflight|working/' agents/tracker/linear.md agents/upgrade.md | head`
   - Expected: idle preflight present

## Integration

**Reachability:** /do-work upgrade migrate step

**Data dependencies:** .do-work/user-requests archive backlog; Linear team

**Service dependencies:** conformance-scan/upgrade agent; linear create_* ops

## Outputs

- agents/upgrade.md — Step 9 destructive confirm, dry-run, already-linear refuse
- agents/tracker/linear.md — REQ-301 hard rules, M1/M7, failure matrix
- lib/conformance-scan.sh — migrate-linear not a scanner drift row
- lib/tests/conformance-scan.test.sh — regression coverage

