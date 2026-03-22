# REQ-045: Add next-step options to verify agent

**UR:** UR-012
**Status:** backlog
**Created:** 2026-03-22

## Task

Update the verify agent's report output (Step 5) to conditionally present next-step options via `AskUserQuestion` when `config.next_steps.enabled` is `true`. When the feature is off, output remains unchanged.

Options vary based on the confidence score:

**Score >= 90%:**
1. "Run the loop" — proceed to run agent
2. "Review REQs" — inspect backlog before running
3. "Skip" — end the interaction

**Score < 90%:**
1. "Auto-fix gaps" — re-run verify with --auto-fix
2. "Re-run Capture" — go back to capture to fill gaps
3. "Skip" — end the interaction

When invoked as a delegate inside the go agent, suppress the AskUserQuestion prompt.

## Context

The verify agent already outputs a recommendation ("Approved — run the loop" or "Fix gaps first"). This converts the recommendation into actionable options. The score-dependent branching ensures the user sees relevant actions.

## Acceptance Criteria

- [ ] Verify agent reads `config.next_steps.enabled` at report time
- [ ] When enabled and standalone with score >= 90%: presents 3 options for proceeding
- [ ] When enabled and standalone with score < 90%: presents 3 options for fixing
- [ ] When disabled or missing: outputs current plain-text report unchanged
- [ ] When running as delegate inside go agent: suppresses AskUserQuestion

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/verify.md` Step 5 and confirm it checks `config.next_steps.enabled`
   - Expected: Conditional block that branches on the config value
2. **test** Confirm score-dependent option sets are documented
   - Expected: Two distinct option sets based on >= 90% vs < 90%
3. **test** Confirm delegate suppression is documented
   - Expected: Instruction to skip AskUserQuestion when invoked by go agent
