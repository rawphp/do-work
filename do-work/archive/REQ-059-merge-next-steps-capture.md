# REQ-059: Merge Next-Step Prompt into Capture Report

**UR:** UR-015
**Status:** done
**Created:** 2026-03-23

## Task

In `agents/capture.md`, merge step 6b (Next-step prompt) INTO step 6 (Report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

Remove the separate 6b subsection entirely. Place the conditional AskUserQuestion as the final action within step 6.

## Context

Same structural issue as all other agents — the `Nb` pattern splits report from prompt, making the prompt easy to skip.

## Acceptance Criteria

- [x] `agents/capture.md` step 6 contains both the text report AND the AskUserQuestion logic in a single step
- [x] The separate "6b" subsection heading no longer exists
- [x] The conditional check (`next_steps.enabled` + standalone detection) remains intact within step 6
- [x] The AskUserQuestion options remain: "Run Verify", "Run Go", "Skip"

## Outputs

- agents/capture.md — Merged step 6b into step 6 "Report and prompt"

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "6b" agents/capture.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/capture.md`
   - Expected: At least 1 — the prompt still exists within step 6
