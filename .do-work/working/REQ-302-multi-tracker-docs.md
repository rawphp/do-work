# REQ-302: Document multi-tracker in SKILL and guides

<!-- claimed-start -->
**Claimed by:** Toms-MacBook-Pro.local.32234
**Claimed at:** 2026-07-31T06:49:41Z
**Heartbeat:** 2026-07-31T06:49:41Z
<!-- claimed-end -->

**UR:** UR-045
**Status:** in-progress
**Created:** 2026-07-31
**Layer:** none
**Entry point:** Operator reads SKILL.md / getting-started / troubleshooting for Linear backend
**Terminal state:** Docs describe tracker.backend, load path, hard-stops, commit convention, migration, and human-assignee warning
**Parent:** 
**Closure proof:**
**Criteria approved:** agent-drafted
**Priority:** 1
**Size:** M
**Files:** SKILL.md docs/getting-started.md docs/HOW-IT-WORKS.md
**Depends on:** REQ-287 REQ-301

## Task

Update operator-facing docs for multi-tracker: config, Linear setup, hard-stop behavior, claim protocol warning (do not clear claim comments while run live), migration, markdown default.

## Context

Design §16 step 9; open risk #5 human UI.

## Acceptance Criteria

- [ ] SKILL.md documents tracker.* and load path
- [ ] getting-started or troubleshooting covers Linear MCP connect + team_id
- [ ] Documents no dual-write and hard-stop rules
- [ ] Documents Linear commit message convention
- [ ] Documents human-assignee warning: do not clear agent claim comments while a run is live
- [ ] If a listed guide file is missing, create it or document the pointer in an existing guide (do not leave broken cross-links)

## Verification Steps

1. **runtime** `grep -nE 'tracker.backend|agents/tracker' SKILL.md | head`
   - Expected: SKILL mentions tracker
2. **runtime** `grep -rnE 'tracker.backend|Linear' docs/getting-started.md docs/HOW-IT-WORKS.md 2>/dev/null | head`
   - Expected: guides mention tracker/Linear

## Outputs
