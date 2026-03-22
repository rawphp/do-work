# UR-014: User Request

**Received:** 2026-03-23
**Status:** intake

## Request

do-work Pipeline Changes
1. Add affected-tests check per REQ (fixes the 30-40% failure rate)
After the Run agent passes its own tests (step 4c), before committing: git diff --name-only, map changed files to related test files, run those tests. If any fail, fix before commit. Adds 2-5 minutes per REQ.

2. Add full suite run at end of loop (safety net for the remaining ~10%)
After the backlog is empty and before the pipeline reports "done," run the complete test suite once. If anything fails, surface which REQ likely caused it (based on which files it touched) and fix.

3. Feed previous REQ implementations as context to the current REQ
Before implementing REQ-003, the Run agent reads a summary of what REQ-001 and REQ-002 actually built — not just their archived REQ files, but which files were created/modified and what they do. Prevents the Run agent from contradicting earlier work.

4. Check acceptance criteria quality after Capture
Between Capture and Verify, evaluate each REQ's acceptance criteria for specificity. Flag any that contain "correctly," "properly," "as expected" without a concrete definition. Weak criteria produce weak implementations that pass weak tests.

5. Verify that Capture incorporated relevant Ideate observations
After Capture writes REQs, check whether critical Ideate flags (especially Challenger risks and Connector overlaps) are reflected in the REQ acceptance criteria or context. If Ideate flagged "this assumes a column that doesn't exist" and no REQ addresses it, flag before Verify.

Priority order:

#    Change    Effort    Impact
1    Affected-tests per REQ    Small — one git diff + test command per REQ    Eliminates most of your current rework
2    Full suite at end of loop    Small — one command at the end    Catches what #1 misses
3    Previous REQ context in Run    Medium — need to build a summary of prior outputs    Prevents cross-REQ contradictions
4    Acceptance criteria quality check    Medium — need to define "specific enough" rubric    Prevents weak implementations upstream
5    Ideate → Capture incorporation check    Medium — need to compare two documents for coverage    Prevents ignored risk flags
1 and 2 are changes to run.md. 3 is a change to run.md's step 3. 4 and 5 are new checks between existing agents — the first rhythm section monitors for your own pipeline.
