# REQ-056: Verify Ideate Observations in Capture Output

**UR:** UR-014
**Status:** backlog
**Created:** 2026-03-23

## Task

Add a step to `agents/verify.md` (before the coverage analysis in Step 3) that checks whether critical Ideate observations were incorporated into the REQ acceptance criteria or context.

When `ideate.md` exists for the UR being verified:
1. Read `ideate.md` and extract all Challenger risks and Connector overlaps
2. For each critical observation, check whether at least one REQ addresses it (in its Task, Context, or Acceptance Criteria sections)
3. Report unaddressed observations in the Issues section of the verify report under a new "Unaddressed Ideate Flags" subsection

This is advisory — unaddressed flags reduce the confidence score by 5 points each (capped at -20 total) but do not block the pipeline.

## Context

Ideate flags risks like "this assumes a database column that doesn't exist" or "this overlaps with an existing feature." If Capture ignores these, the Run agent hits the same problems during implementation. Surfacing the gap in Verify — before execution — lets the user decide whether to address it.

## Acceptance Criteria

- [ ] `agents/verify.md` contains a new step (before or within Step 3) that reads `ideate.md` if it exists for the UR
- [ ] The step extracts Challenger risks and Connector overlaps specifically
- [ ] The step checks each observation against REQ files for coverage (mentioned in Task, Context, or Acceptance Criteria)
- [ ] Unaddressed observations appear in the verify report under "Unaddressed Ideate Flags" in the Issues section
- [ ] Each unaddressed flag reduces the confidence score by 5 points, capped at -20 total deduction
- [ ] If `ideate.md` does not exist, the step is skipped silently
- [ ] The step does not modify any REQ files or `ideate.md`

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "ideate" agents/verify.md`
   - Expected: At least 2 matches (the new step + the flag reporting)
2. **test** `grep -c "Challenger\|Connector" agents/verify.md`
   - Expected: At least 1 match confirming specific ideate sections are referenced
3. **test** `grep -c "Unaddressed Ideate\|ideate flag" agents/verify.md`
   - Expected: At least 1 match confirming the reporting subsection is defined
4. **test** `grep -c "5 points\|-5\|penalty" agents/verify.md`
   - Expected: At least 1 match confirming the score impact is documented
