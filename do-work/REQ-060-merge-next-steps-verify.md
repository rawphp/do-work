# REQ-060: Merge Next-Step Prompt into Verify Report

**UR:** UR-015
**Status:** backlog
**Created:** 2026-03-23

## Task

In `agents/verify.md`, merge step 5b (Next-step prompt) INTO step 5 (Produce the report) so the AskUserQuestion is part of the report output — not a separate step that can be skipped.

Remove the separate 5b subsection entirely. Place the conditional AskUserQuestion as the final action within step 5, after the report output.

## Context

Same structural issue as all other agents — the `Nb` pattern splits report from prompt, making the prompt easy to skip.

## Acceptance Criteria

- [ ] `agents/verify.md` step 5 contains both the text report AND the AskUserQuestion logic in a single step
- [ ] The separate "5b" subsection heading no longer exists
- [ ] The conditional check (`next_steps.enabled` + standalone detection) remains intact within step 5
- [ ] The score-dependent AskUserQuestion options remain (>= 90%: "Run the loop" / "Review REQs" / "Skip"; < 90%: "Auto-fix gaps" / "Re-run Capture" / "Skip")

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "5b" agents/verify.md`
   - Expected: 0 — the separate subsection heading is gone
2. **test** `grep -c "AskUserQuestion" agents/verify.md`
   - Expected: At least 1 — the prompt still exists within step 5
