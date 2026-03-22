# REQ-062: Merge Next-Step Prompt into Start Report

**UR:** UR-015
**Status:** backlog
**Created:** 2026-03-23

## Task

In `agents/start.md`, merge step 4b (Next-step prompt) INTO step 4 (Report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

Remove the separate 4b subsection entirely. Place the conditional AskUserQuestion as the final action within step 4, after the combined summary output.

Also update the static "Next step:" line in the report template to remove it — the AskUserQuestion replaces it when next_steps is enabled, and the static line is misleading when it IS enabled (it suggests a command to run manually rather than presenting an interactive choice).

## Context

Start is a top-level orchestrator so it never suppresses — the AskUserQuestion should always fire when `next_steps.enabled` is `true`. The current step 4 outputs a static "Next step:" text line and then 4b (the interactive prompt) is a separate section that gets skipped.

## Acceptance Criteria

- [ ] `agents/start.md` step 4 contains both the text report AND the AskUserQuestion logic in a single step
- [ ] The separate "4b" subsection heading no longer exists
- [ ] The static "Next step:" line in the report template is removed (replaced by the interactive AskUserQuestion)
- [ ] When `next_steps.enabled` is `false`, the report still shows a static "Next step:" suggestion as fallback
- [ ] The AskUserQuestion options remain: "Run Go", "Run Verify only", "Skip"

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "4b" agents/start.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/start.md`
   - Expected: At least 1 — the prompt still exists within step 4
