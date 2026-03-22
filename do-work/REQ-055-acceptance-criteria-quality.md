# REQ-055: Add Acceptance Criteria Quality Check to Capture

**UR:** UR-014
**Status:** backlog
**Created:** 2026-03-23

## Task

Add a self-check step to `agents/capture.md` after Step 4 (Write REQ files) and before Step 5 (Commit). After writing all REQ files, the Capture agent reviews each REQ's acceptance criteria for specificity.

Flag any criterion that:
- Uses vague qualifiers ("correctly", "properly", "as expected", "works", "handles") without a concrete, measurable definition in the same criterion
- Has no verifiable outcome (can't be answered with yes/no by reading code or running a test)
- Refers to behavior without specifying the expected input/output

When flagged, the agent must rewrite the criterion to be specific before proceeding to commit. This is a self-correction step, not a pipeline blocker — the agent fixes its own output immediately.

Note: The Verify agent (verify.md Step 4) already checks for "vague acceptance criteria" at the coverage level. This new check operates at the individual criterion level during authoring, catching vagueness earlier and with more precision.

## Context

Weak acceptance criteria produce weak implementations that pass weak tests. "User can log in correctly" tells the Run agent nothing; "User submits valid email+password and receives a 200 response with a JWT token" tells it exactly what to build and test.

## Acceptance Criteria

- [ ] `agents/capture.md` contains a new step (between current Steps 4 and 5) titled "Check acceptance criteria quality" or similar
- [ ] The step lists specific vague-qualifier keywords to scan for: "correctly", "properly", "as expected", "works", "handles"
- [ ] The step requires checking context — a criterion containing "correctly" paired with a concrete definition (e.g. "correctly returns HTTP 200") is NOT flagged
- [ ] The step instructs the agent to rewrite any flagged criteria inline before proceeding
- [ ] The step does not block the pipeline or require user intervention — it is a self-correction

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "acceptance criteria quality\|criteria quality\|quality check" agents/capture.md`
   - Expected: At least 1 match
2. **test** `grep -c "correctly\|properly\|as expected" agents/capture.md`
   - Expected: At least 1 match confirming the vague keywords are listed
3. **test** `grep -c "rewrite" agents/capture.md`
   - Expected: At least 1 match confirming the self-correction instruction exists
