# REQ-047: Add next-step options to go agent

**UR:** UR-012
**Status:** backlog
**Created:** 2026-03-22

## Task

Update the go agent's final report (Step 5) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged.

Options:
1. "Start new work" — run intake for a new UR
2. "Review archive" — list completed REQs and outputs
3. "Skip" — end the interaction

The go agent is a top-level orchestrator, so it is never a delegate — no suppression logic needed. Sub-agents (verify, run, log) should suppress their own AskUserQuestion prompts when running inside go.

## Context

The go agent is the most common entry point for users. After a full verify-run-log cycle completes, presenting next steps gives the user a seamless transition to their next action.

## Acceptance Criteria

- [ ] Go agent reads `config.next_steps.enabled` at report time
- [ ] When enabled: presents AskUserQuestion with 3 options
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] Sub-agent suppression is documented (verify, run, log suppress when inside go)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/go.md` Step 5 and confirm it checks `config.next_steps.enabled`
   - Expected: Conditional block that branches on the config value
2. **test** Confirm option labels match the spec
   - Expected: "Start new work", "Review archive", "Skip"
3. **test** Confirm go.md documents that sub-agents suppress their AskUserQuestion when delegated
   - Expected: Note in Steps 1/3/4 about suppression
