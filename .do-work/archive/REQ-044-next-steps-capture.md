# REQ-044: Add next-step options to capture agent

**UR:** UR-012
**Status:** done
**Created:** 2026-03-22

## Task

Update the capture agent's report step (Step 6) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged.

Options to present:
1. "Run Verify" — check coverage of the decomposed REQs
2. "Run Go" — skip to verify + run in one shot
3. "Skip" — end the interaction

When invoked as a delegate inside the start agent, suppress the AskUserQuestion prompt.

## Context

After capture completes, the natural next steps are to verify coverage or jump straight to execution. This makes those actions one click away instead of requiring the user to remember command syntax.

## Acceptance Criteria

- [ ] Capture agent reads `config.next_steps.enabled` at report time
- [ ] When enabled and running standalone: presents AskUserQuestion with 3 options
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] When running as delegate inside start agent: suppresses AskUserQuestion

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/capture.md` Step 6 and confirm it checks `config.next_steps.enabled`
   - Expected: Conditional block that branches on the config value
2. **test** Read `agents/capture.md` Step 6 and confirm AskUserQuestion options match the spec
   - Expected: "Run Verify", "Run Go", "Skip" as option labels
