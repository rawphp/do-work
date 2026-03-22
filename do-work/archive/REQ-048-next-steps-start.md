# REQ-048: Add next-step options to start agent

**UR:** UR-012
**Status:** done
**Created:** 2026-03-22

## Task

Update the start agent's final report (Step 4) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged.

Options:
1. "Run Go" — proceed to verify and execute the backlog
2. "Run Verify only" — check coverage without executing
3. "Skip" — end the interaction

The start agent is a top-level orchestrator. Sub-agents (intake, ideate, capture) should suppress their own AskUserQuestion prompts when running inside start.

## Context

After start completes (intake + ideate + capture), the natural next action is to run go. Presenting this as a clickable option reduces friction.

## Acceptance Criteria

- [ ] Start agent reads `config.next_steps.enabled` at report time
- [ ] When enabled: presents AskUserQuestion with 3 options
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] Sub-agent suppression is documented (intake, ideate, capture suppress when inside start)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/start.md` Step 4 and confirm it checks `config.next_steps.enabled`
   - Expected: Conditional block that branches on the config value
2. **test** Confirm option labels match the spec
   - Expected: "Run Go", "Run Verify only", "Skip"
