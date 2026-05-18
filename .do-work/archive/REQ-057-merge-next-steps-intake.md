# REQ-057: Merge Next-Step Prompt into Intake Report

**UR:** UR-015
**Status:** done
**Created:** 2026-03-23

## Task

In `agents/intake.md`, merge step 6b (Next-step prompt) INTO step 6 (Stop and report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

The current structure has step 6 ending with "**Stop here.** Do not run Capture." followed by a separate 6b subsection. The bold stop instruction causes the LLM to halt before reaching 6b. Fix by making the AskUserQuestion the final action WITHIN step 6, after the text report, with the conditional check inline.

Remove the separate 6b subsection entirely.

## Context

The `next_steps.enabled` config is `true` but AskUserQuestion prompts aren't being emitted because the "Stop here" instruction in step 6 is more emphatic than the quiet 6b subsection that follows it. The LLM treats step 6's stop as terminal.

## Acceptance Criteria

- [x] `agents/intake.md` step 6 contains both the text report AND the AskUserQuestion logic in a single step
- [x] The separate "6b" subsection heading no longer exists
- [x] The conditional check (`next_steps.enabled` + standalone detection) remains intact within step 6
- [x] The "Stop here" instruction is repositioned AFTER the AskUserQuestion (or removed, since the AskUserQuestion naturally blocks further action)
- [x] The AskUserQuestion options remain: "Run Capture", "Edit the brief", "Skip"

## Outputs

- agents/intake.md — Merged step 6b into step 6 "Report and prompt"

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "6b" agents/intake.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/intake.md`
   - Expected: At least 1 — the prompt still exists within step 6
3. **test** `grep -c "Stop and report" agents/intake.md || grep -c "Report and prompt" agents/intake.md`
   - Expected: At least 1 — the merged step has a clear heading
