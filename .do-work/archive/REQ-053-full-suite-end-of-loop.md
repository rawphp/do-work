# REQ-053: Add Full Suite Run at End of Loop

**UR:** UR-014
**Status:** done
**Created:** 2026-03-23

## Task

Add a new section to `agents/run.md` in the "When the Backlog is Empty" section. Before reporting completion, run the project's full test suite once. If any tests fail, identify which REQ likely caused the failure by cross-referencing failing test files with the `git diff` of each REQ's commit, then fix.

Add a `test.suite_command` config key to `agents/config.md` so projects can specify their test runner (e.g. `./vendor/bin/pest`, `npx vitest run`). If not configured, attempt common defaults (`npm test`, `./vendor/bin/pest`) and skip if none found.

## Context

Even with per-REQ affected-tests checks (REQ-052), approximately 10% of failures come from interactions between REQs that individual checks miss. A full suite run at the end catches these.

## Acceptance Criteria

- [x] `agents/run.md` "When the Backlog is Empty" section includes a new step to run the full test suite before reporting completion
- [x] The step references `config.test.suite_command` for the test runner command
- [x] If no suite command is configured, the agent attempts common defaults (`npm test`, `./vendor/bin/pest`, `npx vitest run`) in order
- [x] If no test runner is found, the step is skipped with a log message "No test suite configured or detected — skipping full suite run"
- [x] On failure, the step identifies the likely responsible REQ by comparing failing test file paths against each REQ commit's changed files
- [x] On failure, the agent attempts to fix the issue before reporting completion
- [x] `agents/config.md` schema includes `test.suite_command` with type string, default `""`, and description

## Outputs

- agents/run.md — Added "Final test suite run" section before completion report
- agents/config.md — Added `test.suite_command` config key and schema entry

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "suite_command" agents/run.md`
   - Expected: At least 1 match
2. **test** `grep -c "suite_command" agents/config.md`
   - Expected: At least 1 match in the config schema
3. **test** `grep -c "Backlog is Empty" agents/run.md`
   - Expected: At least 1 match confirming the section still exists with the new content
