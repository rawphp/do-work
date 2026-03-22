# REQ-043: Add next-step options to intake agent

**UR:** UR-012
**Status:** backlog
**Created:** 2026-03-22

## Task

Update the intake agent's report step (Step 6) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged (plain text "Next steps:" block).

Options to present:
1. "Run Capture" — proceed to capture for the recorded UR
2. "Edit the brief" — open input.md for review before capturing
3. "Skip" — end the interaction

When invoked as a delegate inside the start agent, suppress the AskUserQuestion prompt (the orchestrator handles flow).

## Context

The intake agent already outputs plain-text next steps. This converts them to interactive AskUserQuestion options when the config toggle is on, giving the user clickable actions instead of copy-paste instructions.

## Acceptance Criteria

- [ ] Intake agent reads `config.next_steps.enabled` at report time
- [ ] When enabled and running standalone: presents AskUserQuestion with 3 options
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] When running as delegate inside start agent: suppresses AskUserQuestion

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/intake.md` Step 6 and confirm it checks `config.next_steps.enabled`
   - Expected: Conditional block that branches on the config value
2. **test** Read `agents/intake.md` Step 6 and confirm AskUserQuestion options match the spec (3 options)
   - Expected: "Run Capture", "Edit the brief", "Skip" as option labels
3. **test** Confirm delegate suppression is documented
   - Expected: Instruction to skip AskUserQuestion when invoked by start agent
