# REQ-052: Add Affected-Tests Check Per REQ

**UR:** UR-014
**Status:** backlog
**Created:** 2026-03-23

## Task

Add a new step to `agents/run.md` between Step 4c (verify green) and Step 4d (check acceptance criteria). After the REQ's own TDD tests pass, run `git diff --name-only` to identify all changed files, map them to related test files in the project, and run those tests. If any fail, fix the implementation before proceeding.

The mapping logic must handle:
- Projects with no test suite (skip gracefully)
- Common conventions: `tests/`, `__tests__/`, `*.test.*`, `*.spec.*`, `Test.php` suffix
- Non-code REQs (markdown, config) where no test mapping exists (skip gracefully)

## Context

The do-work pipeline has a 30-40% failure rate where REQ implementations pass their own TDD tests but break existing functionality. This check catches regressions before commit by running tests related to changed files.

## Acceptance Criteria

- [ ] `agents/run.md` contains a new step 4c-ii (or renumbered equivalent) titled "Run affected tests" between current 4c and 4d
- [ ] The step describes running `git diff --name-only` to get changed files
- [ ] The step describes mapping changed files to test files using common naming conventions (e.g. `src/Foo.php` → `tests/FooTest.php`, `src/foo.ts` → `src/foo.test.ts` or `tests/foo.spec.ts`)
- [ ] The step instructs the agent to run discovered test files and fix failures before proceeding
- [ ] The step degrades gracefully: if no test files are found for changed files, log "No affected tests found" and continue
- [ ] The step does not re-run tests already executed in step 4c (the REQ's own TDD tests)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "affected test" agents/run.md`
   - Expected: At least 1 match confirming the new step exists
2. **test** `grep -c "git diff --name-only" agents/run.md`
   - Expected: At least 1 match confirming the diff command is referenced
3. **test** `grep -c "graceful" agents/run.md || grep -c "skip" agents/run.md`
   - Expected: At least 1 match confirming graceful degradation is documented
