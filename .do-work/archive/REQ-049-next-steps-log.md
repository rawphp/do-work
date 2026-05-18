# REQ-049: Add Next-Step Options to Log Agent

**UR:** UR-012
**Status:** done
**Created:** 2026-03-22

## Task

Add an AskUserQuestion prompt with next-step options to the log agent's terminal output (after draft selection/skip is recorded), gated by `next_steps.enabled` config.

## Context

UR-012 requests next steps after every phase. The log agent already uses AskUserQuestion for draft selection, but its terminal output (after recording the selection) does not offer next-step navigation. This REQ fills that gap.

## Acceptance Criteria

- [ ] After log records selection or skip, if `next_steps.enabled` is true, present AskUserQuestion with contextual next-step options
- [ ] Options include relevant next actions (e.g. "Start new work", "View archive", "Run log again")
- [ ] When `next_steps.enabled` is false or missing, no AskUserQuestion is shown (current behavior preserved)
- [ ] When log is invoked as a delegate inside the go agent, suppress the next-step prompt (go agent handles its own)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/log.md` and confirm it contains an AskUserQuestion block gated by `next_steps.enabled` after the draft recording step
   - Expected: Conditional AskUserQuestion section present with 2-4 option labels and delegate suppression note
