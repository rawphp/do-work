# REQ-054: Feed Previous REQ Context to Current REQ

**UR:** UR-014
**Status:** done
**Created:** 2026-03-23

## Task

Modify `agents/run.md` Step 3 to expand the context the Run agent reads before implementing a REQ. In addition to reading the original brief (`input.md`), the agent must also read all archived REQ files from the same UR that were completed earlier in this loop.

For each prior archived REQ, extract:
- The task title
- Which files were created/modified (from the `## Outputs` section)
- A one-line summary of what was built

This context prevents later REQs from contradicting or duplicating work done by earlier REQs in the same UR.

## Context

Without context on prior REQ implementations, REQ-003 might overwrite a file REQ-001 just created, or re-implement logic REQ-002 already built. The `## Outputs` section in archived REQs already captures the needed information — this change just ensures the Run agent reads it.

## Acceptance Criteria

- [x] `agents/run.md` Step 3 instructs the agent to read all archived REQ files from the same UR (matching the `**UR:** UR-NNN` field)
- [x] The step specifies extracting: task title, files from `## Outputs`, and a one-line summary
- [x] The step instructs the agent to keep this context available during Step 4 (implementation) to avoid contradictions
- [x] The step handles the first REQ in a UR gracefully (no prior REQs to read — just skip)
- [x] The step does not instruct the agent to modify archived REQs

## Outputs

- agents/run.md — Expanded Step 3 to read prior archived REQs from the same UR for context

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** `grep -c "archive" agents/run.md`
   - Expected: At least 2 matches (the existing archive step + the new context-reading instruction)
2. **test** `grep -c "Step 3" agents/run.md || grep -c "Read the original brief" agents/run.md`
   - Expected: At least 1 match confirming Step 3 still exists with expanded content
3. **test** `grep -c "Outputs" agents/run.md`
   - Expected: At least 2 matches (the existing Outputs section instruction + the new context-reading reference)
