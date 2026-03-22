# REQ-040: Add Contextual State-Aware Suggestions to Bare /do-work Output

**UR:** UR-011
**Status:** backlog
**Created:** 2026-03-22

## Task

Enhance the "No subcommand" behavior in SKILL.md to detect the current project state and tailor suggestions accordingly. Instead of only static examples, the output should check for conditions like pending REQs in the backlog, URs without captures, or an empty backlog, and suggest the most relevant next command.

## Context

Static suggestions (REQ-039) give a baseline, but the real value is contextual hints. If the user has REQs waiting, suggest `/do-work run`. If they have a UR but no REQs, suggest `/do-work capture UR-NNN`. If nothing exists, suggest `/do-work start`. This makes the bare command a smart entry point.

## Acceptance Criteria

- [ ] SKILL.md "No subcommand" section includes logic to detect project state before printing suggestions
- [ ] At minimum, three states are handled: (1) no do-work folder — suggest `/do-work install`, (2) backlog has REQs — suggest `/do-work run`, (3) backlog empty but URs exist — suggest `/do-work capture` or `/do-work go`
- [ ] Contextual suggestions replace or augment the static suggestions from REQ-039
- [ ] If state detection fails for any reason, fall back to the static suggestions gracefully

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **runtime** Invoke `/do-work` in a project with REQ files in the backlog
   - Expected: Output suggests `/do-work run` as a next step
2. **runtime** Invoke `/do-work` in a project with URs but no REQs in the backlog
   - Expected: Output suggests capturing or going with a specific UR number
3. **runtime** Invoke `/do-work` in a project with no do-work folder
   - Expected: Output suggests `/do-work install`

## Assets

- SKILL.md "No subcommand" section — target for enhancement
- agents/run.md pre-flight checks — reusable pattern for detecting backlog state
