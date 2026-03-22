# Ideate — UR-014

**Reviewed:** 2026-03-23

## Explorer — Assumptions & Perspectives

- The brief assumes agent files live in `{project}/agents/` and are directly editable by the Run agent. Currently these files ARE in the project repo (do-work is editing its own agents), but when other projects use do-work as a skill, the agent files are read-only at `~/.claude/skills/do-work/agents/`. The REQs need to target the correct paths — `{project}/agents/run.md` etc., not the skill clone.
- Change #3 (previous REQ context) assumes the Run agent can build a useful summary from archived REQs alone. In practice, the `## Outputs` section already lists which files were created/modified — this may be sufficient without building a separate summary mechanism.
- The brief doesn't specify what "affected tests" means for non-code REQs (docs, config files, markdown). The affected-tests check needs a graceful fallback when `git diff` produces files with no test mapping.

## Challenger — Risks & Edge Cases

- Change #1 (affected-tests per REQ) has a mapping problem: how does the agent determine which test files relate to which changed files? There's no test discovery convention defined. For this project specifically (markdown agent files), there are no automated tests at all — the "tests" in TDD step 4a are written ad-hoc per REQ. The mapping logic needs to handle projects with different test conventions (Pest, Vitest, Jest, none).
- Change #2 (full suite at end) could fail silently if the project has no test runner configured. The run agent currently has no concept of "project test suite command" — it only runs tests written during step 4a. A config key (e.g. `test.suite_command`) may be needed.
- Change #4 (acceptance criteria quality check) risks false positives. Words like "correctly" and "properly" are sometimes legitimate when paired with a concrete definition in the same sentence (e.g. "correctly returns HTTP 200 with the user's email"). The rubric needs to check for vagueness in context, not just keyword presence.
- Changes #4 and #5 introduce new checks between Capture and Verify, but there's no current agent or step for that slot. They either need to be folded into Capture itself (post-write self-check) or into Verify (pre-coverage check), or a new "quality gate" agent needs to be created. Adding a new agent increases pipeline complexity.

## Connector — Links & Reuse

- The Verify agent (verify.md step 4) already checks for "vague acceptance criteria." Change #4 partially overlaps with this — the new quality check should extend Verify's existing check rather than creating a duplicate mechanism.
- The Run agent's Step 3 already reads the original brief for context. Change #3 extends this to also read prior REQ outputs — this is a natural extension of the same step, not a new step.
- REQ-051 (config migration) just shipped. If changes #1 or #2 need new config keys (e.g. `test.suite_command`, `test.affected_test_pattern`), they should follow the same migration pattern so existing installs get defaults automatically.

## Summary

The highest-risk items are the test mapping logic in change #1 (no convention exists for mapping source files to test files across project types) and the placement of changes #4/#5 in the pipeline (they need a home — either extending existing agents or creating new ones). The brief's priority ordering is sound, but each change needs to degrade gracefully for projects without test suites.
