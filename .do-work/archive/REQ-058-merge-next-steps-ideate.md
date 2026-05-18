# REQ-058: Merge Next-Step Prompt into Ideate Report

**UR:** UR-015
**Status:** done
**Created:** 2026-03-23

## Task

In `agents/ideate.md`, merge step 5b (Next-step prompt) INTO step 5 (Report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

Remove the separate 5b subsection entirely. Place the conditional AskUserQuestion as the final action within step 5.

## Context

Same structural issue as all other agents — the `Nb` pattern splits report from prompt, making the prompt easy to skip.

## Acceptance Criteria

- [x] `agents/ideate.md` step 5 contains both the text report AND the AskUserQuestion logic in a single step
- [x] The separate "5b" subsection heading no longer exists
- [x] The conditional check (`next_steps.enabled` + standalone detection) remains intact within step 5
- [x] The AskUserQuestion options remain: "Run Capture", "Edit the brief", "Skip"

## Outputs

- agents/ideate.md — Merged step 5b into step 5 "Report and prompt"

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "5b" agents/ideate.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/ideate.md`
   - Expected: At least 1 — the prompt still exists within step 5
