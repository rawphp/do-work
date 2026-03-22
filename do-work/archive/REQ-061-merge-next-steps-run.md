# REQ-061: Merge Next-Step Prompts into Run Report Sections

**UR:** UR-015
**Status:** done
**Created:** 2026-03-23

## Task

In `agents/run.md`, merge the two conditional next-step prompt sections into their parent report sections:

1. The "Next-step prompt (conditional — backlog empty)" section → merge into "Completion report" (which replaced "When the Backlog is Empty")
2. The "Next-step prompt (conditional — stopper hit)" section → merge into the Stopping Rules section

Remove both separate subsection headings. Place each conditional AskUserQuestion as the final action within its parent section.

## Context

Same structural issue as all other agents — separate subsections for next-step prompts get skipped.

## Acceptance Criteria

- [x] `agents/run.md` "Completion report" section contains the AskUserQuestion for backlog-empty as its final action
- [x] `agents/run.md` Stopping Rules section contains the AskUserQuestion for stopper-hit as its final action
- [x] Neither "Next-step prompt (conditional" heading exists as a separate subsection
- [x] The conditional checks (`next_steps.enabled` + standalone detection) remain intact
- [x] AskUserQuestion options remain unchanged for both cases

## Outputs

- agents/run.md — Merged both next-step prompts into their parent sections

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "Next-step prompt" agents/run.md`
   - Expected: 0 — separate subsection headings are gone
2. **test** `grep -c "AskUserQuestion" agents/run.md`
   - Expected: At least 2 — both prompts still exist within their parent sections
