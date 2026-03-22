# REQ-038: Command Format Pros/Cons Analysis

**UR:** UR-010
**Status:** backlog
**Created:** 2026-03-22

## Task

Write a structured analysis document comparing three options for do-work command invocation format:
1. Current space-separated: `/do-work start`
2. Colon-joined: `/do-work:start`
3. Support both formats

Document trade-offs for each including ergonomics, maintainability, Claude Code compatibility, and migration impact. Conclude with a recommendation.

## Context

The user is considering whether to change `/do-work start` to `/do-work:start` or support both. The system has 37 shipped REQs using the current format, and Claude Code's Skill tool already uses colons for namespace separation (`ms-office-suite:pdf`), which creates potential semantic collision.

## Acceptance Criteria

- [ ] Analysis document written to `do-work/user-requests/UR-010/analysis.md`
- [ ] All three options evaluated with clear pros/cons
- [ ] Claude Code Skill tool behavior documented (how colons are interpreted)
- [ ] Migration impact assessed (what files/docs reference the current format)
- [ ] Clear recommendation with rationale

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **runtime** Read `do-work/user-requests/UR-010/analysis.md` and confirm it contains sections for all three options, pros/cons for each, and a recommendation section
   - Expected: Document exists with structured analysis covering all three options
