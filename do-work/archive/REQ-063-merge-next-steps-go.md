# REQ-063: Merge Next-Step Prompt into Go Report

**UR:** UR-015
**Status:** done
**Created:** 2026-03-23

## Task

In `agents/go.md`, merge step 5b (Next-step prompt) INTO step 5 (Report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

Remove the separate 5b subsection entirely. Place the conditional AskUserQuestion as the final action within step 5.

## Context

Go is a top-level orchestrator so it never suppresses — the AskUserQuestion should always fire when `next_steps.enabled` is `true`. Same structural pattern fix as all other agents.

## Acceptance Criteria

- [x] `agents/go.md` step 5 contains both the text report AND the AskUserQuestion logic in a single step
- [x] The separate "5b" subsection heading no longer exists
- [x] The conditional check (`next_steps.enabled`) remains intact within step 5
- [x] The AskUserQuestion options remain: "Start new work", "Review archive", "Skip"

## Outputs

- agents/go.md — Merged step 5b into step 5 "Report and prompt"

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "5b" agents/go.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/go.md`
   - Expected: At least 1 — the prompt still exists within step 5
