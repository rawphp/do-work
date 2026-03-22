# REQ-046: Add next-step options to run agent at loop termination

**UR:** UR-012
**Status:** backlog
**Created:** 2026-03-22

## Task

Update the run agent's terminal output (when backlog is empty or a stopper is hit) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged.

**Backlog empty (success):**
1. "Review outputs" — list archived REQs and their output paths
2. "Start new work" — run intake for a new UR
3. "Skip" — end the interaction

**Stopper hit (blocked):**
1. "Show blocker details" — display the full failure context
2. "Retry current REQ" — resume from where it stopped
3. "Skip" — end the interaction

Do NOT present AskUserQuestion after each individual REQ completion — only at loop termination. The autonomous loop must remain uninterrupted.

When invoked as a delegate inside the go agent, suppress the AskUserQuestion prompt.

## Context

The run agent's autonomous loop should not be interrupted by interactive prompts. Next steps only make sense when the loop ends — either because all work is done or because a blocker was hit.

## Acceptance Criteria

- [ ] Run agent reads `config.next_steps.enabled` at loop termination
- [ ] When enabled and backlog empty: presents 3 success-path options
- [ ] When enabled and stopper hit: presents 3 blocked-path options
- [ ] AskUserQuestion is NOT presented after individual REQ completions (mid-loop)
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] When running as delegate inside go agent: suppresses AskUserQuestion

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/run.md` "When the Backlog is Empty" section and confirm AskUserQuestion is conditional on config
   - Expected: Conditional block with 3 options for success path
2. **test** Read `agents/run.md` "Stopping Rules" section and confirm AskUserQuestion is conditional on config
   - Expected: Conditional block with 3 options for blocked path
3. **test** Confirm no AskUserQuestion appears in Step 7 (per-REQ report)
   - Expected: Step 7 remains plain text with no AskUserQuestion
