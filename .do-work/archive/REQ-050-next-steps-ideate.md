# REQ-050: Add Next-Step Options to Ideate Agent

**UR:** UR-012
**Status:** done
**Created:** 2026-03-22

## Task

Add an AskUserQuestion prompt with next-step options to the ideate agent's terminal output (after writing ideate.md), gated by `next_steps.enabled` config. Suppress when invoked as a delegate inside the start agent.

## Context

UR-012 requests next steps after every phase. The ideate agent writes its review and reports, but does not offer next-step navigation. While ideate is most commonly invoked inside start (where start handles next steps via REQ-048), standalone `/do-work ideate` invocations need their own prompt.

## Acceptance Criteria

- [ ] After ideate writes its review and reports, if `next_steps.enabled` is true, present AskUserQuestion with contextual next-step options
- [ ] Options include relevant next actions (e.g. "Run capture", "Edit the brief", "Start over")
- [ ] When `next_steps.enabled` is false or missing, no AskUserQuestion is shown (current behavior preserved)
- [ ] When ideate is invoked as a delegate inside the start agent, suppress the next-step prompt (start agent handles its own via REQ-048)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/ideate.md` and confirm it contains an AskUserQuestion block gated by `next_steps.enabled` after the report step
   - Expected: Conditional AskUserQuestion section present with 2-4 option labels and delegate suppression note
