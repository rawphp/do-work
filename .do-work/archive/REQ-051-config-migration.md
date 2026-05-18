# REQ-051: Auto-migrate config.yml with missing keys on load

**UR:** UR-013
**Status:** done
**Created:** 2026-03-22

## Task

Update the config loader in `agents/config.md` so that when it reads an existing `config.yml` that is missing keys from the default template, it appends the missing top-level sections (with defaults and comments) to the file on disk — then continues with the merged values in context.

## Context

When new config keys are added to the do-work system (e.g. `next_steps.enabled`), existing projects that already have a `config.yml` never receive those keys. The config loader silently falls back to in-memory defaults, but the user can't discover or toggle the new options without manually editing config.yml. This REQ makes the loader self-healing: it detects missing sections and appends them.

## Acceptance Criteria

- [x] Config loader compares existing config.yml against the default template during Load Config
- [x] Missing top-level sections (e.g. entire `next_steps:` block) are appended to config.yml with default values and inline comments
- [x] Existing values are never overwritten — the merge is additive-only
- [x] Missing keys within an existing section (e.g. `log.batch_size` added to an existing `log:` block) are appended to that section
- [x] If no keys are missing, the file is not touched (no unnecessary writes or commits)
- [x] The loader reports what was added (e.g. "Config updated: added next_steps section") when migration occurs

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/config.md` and confirm the Load Config section includes a migration/merge step between reading the file and using values
   - Expected: Step that compares existing keys against defaults and appends missing ones
2. **test** Confirm the instructions specify additive-only behavior — never overwriting existing values
   - Expected: Explicit instruction to preserve existing values and only add missing keys
3. **test** Confirm the instructions specify a no-op when no keys are missing
   - Expected: Instruction to skip file write if config is already complete

## Outputs

- agents/config.md — Updated Load Config with step 4 (migrate missing keys) and step 5 (merged context)
