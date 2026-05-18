# REQ-039: Add Static Command Suggestions to Bare /do-work Output

**UR:** UR-011
**Status:** done
**Created:** 2026-03-22

## Task

Add a "Suggested next steps" section to the SKILL.md "No subcommand" behavior. When `/do-work` is invoked with no arguments, the output should show concrete, copy-pasteable example commands before or after the Quick Reference table, giving the user an immediate sense of what to try next.

## Context

The user reported that typing `/do-work` with no arguments gives no suggestions — just the Quick Reference table. Other tools offer placeholder-style hints that guide the user toward their next action. The goal is to add a static suggestion block with common starting-point commands.

## Acceptance Criteria

- [x] SKILL.md "No subcommand" section updated to include a "Suggested next steps" block
- [x] The block contains 3-4 concrete example commands (e.g., `/do-work start "your brief here"`, `/do-work run`, `/do-work go UR-001`)
- [x] Each suggestion includes a one-line description of when to use it
- [x] The suggestions appear as part of the bare `/do-work` output, visually distinct from the Quick Reference table
- [x] Existing Quick Reference table remains unchanged

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **runtime** Invoke `/do-work` with no arguments in a test conversation
   - Expected: Output includes both the Quick Reference table AND a "Suggested next steps" section with 3-4 copy-pasteable example commands
2. **runtime** Read the updated SKILL.md and confirm the "No subcommand" section contains the new suggestion block
   - Expected: The section has clear formatting that separates suggestions from the reference table

## Assets

- SKILL.md lines 87-89 — current "No subcommand" section

## Outputs

- agents/help.md — New help agent with static fallback suggestions and contextual state-aware logic
- SKILL.md — Minimal update: "No subcommand" section delegates to agents/help.md
