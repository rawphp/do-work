# Ideate — UR-011

**Reviewed:** 2026-03-22

## Explorer — Assumptions & Perspectives

- The brief assumes "placeholder" means a visible hint shown when the user types `/do-work` with no arguments. Currently the bare command prints the Quick Reference table, which is a wall of text — not a guided suggestion. The user wants something more like an inline prompt or example usage, not just a reference dump.
- Two distinct user populations exist: first-time users who don't know the commands at all, and returning users who forgot the exact syntax. A good solution should serve both — quick recognition for returners, gentle guidance for newcomers.
- The current Quick Reference table is functional but dense. Adding placeholder-style suggestions does not necessarily mean replacing the table — it could mean augmenting the output with a "Try one of these" section that gives concrete, copy-pasteable next-step examples.

## Challenger — Risks & Edge Cases

- Claude Code skills do not have a traditional CLI arg parser — the "placeholder" concept from tools like `gh` or `npm` (showing greyed-out hint text in the terminal) is not directly possible. The skill is invoked via natural language, so "placeholder" here realistically means printing suggested next commands in the output, not an interactive shell feature.
- If the suggestions are too generic (e.g., "try /do-work start"), they add little value over the existing table. The suggestions should be contextual — e.g., if there are pending REQs in the backlog, suggest `/do-work run`; if there are URs without REQs, suggest `/do-work capture UR-NNN`.
- Over-engineering this with dynamic context detection could make the "no subcommand" path slow or fragile. A static suggestion block is simpler and still delivers the requested improvement.

## Connector — Links & Reuse

- The SKILL.md "No subcommand" section (line 88-89) is the single point that controls bare `/do-work` behavior. Any change lands there and in no other agent file.
- The Quick Reference table already exists and is well-structured. The suggestion block should complement it, not duplicate it — placed either before or after the table as a "Getting started" or "Next steps" section.
- Other do-work agents (start, go, run) already have logic for detecting project state (backlog empty, working dir occupied, etc.). If we go the contextual route, those patterns can be reused.

## Summary

The core ask is simple: when `/do-work` is invoked bare, show actionable suggestions alongside (or instead of) the raw reference table. The main design decision is whether suggestions are static (always the same examples) or contextual (based on current project state like pending REQs or empty backlog). A two-tier approach — static suggestion examples first, with a follow-up REQ for contextual awareness — keeps scope tight while leaving room for the richer experience.
