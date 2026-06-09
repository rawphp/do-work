# do-work governance and dual-install enhancement plan

## Goal

Enhance the `do-work` skill so it closes the remaining governance gaps and can be installed into either a Claude Code environment or a Codex environment, with the user choosing the target environment.

## Plan

1. Map current state

   Read the existing `SKILL.md`, `agents/*.md`, `install.sh`, config loader, and test style. Identify where `do-work` already covers intake, verify, audit, run, parallel coordination, and where the governance gaps should attach.

2. Define the target gaps

   Add explicit requirements for:

   - independent post-build review gate
   - per-acceptance-criterion evidence
   - decision/ADR log
   - risk/security policy
   - structured run ledger
   - model/cost governance
   - environment-aware installation for Claude Code vs Codex

3. Design the runtime flow

   Update the skill workflow so `/do-work go` becomes:

   ```text
   verify -> audit -> run -> review -> evidence validation -> archive/ledger -> log
   ```

   The key behavior is: `worker says done` is not final. A reviewer or review step must validate scope, tests, evidence, changed files, and risk policy before the REQ is considered complete.

4. Design install behavior

   Update `install.sh` to support explicit environment selection:

   - `--env claude` installs to `~/.claude/skills/do-work`
   - `--env codex` installs to `~/.codex/skills/do-work`
   - no `--env` asks the user to choose
   - keep `--from-cwd` and `--source <path>` working for both
   - preserve backup/update behavior per target environment

5. Add config schema

   Extend `.do-work/config.yml` defaults with sections like:

   - `review.required`
   - `acceptance.evidence_required`
   - `risk.require_review`
   - `security.blocked_paths`
   - `security.blocked_commands`
   - `model.default`, `model.escalation`
   - `cost.budget`
   - `ledger.enabled`

6. Add deterministic helpers

   Add small shell helpers where rule enforcement should be testable:

   - installer target resolution
   - risk/security policy checks
   - acceptance evidence validation
   - run ledger append/validation if useful

7. Add tests

   Follow the repo's current plain-bash test style under `lib/tests`.

   Cover:

   - Claude/Codex install target resolution
   - invalid environment rejected
   - policy blocks sensitive paths/commands
   - acceptance evidence requires one evidence item per acceptance criterion
   - ledger records required fields
   - existing tests still pass

8. Patch docs and agent instructions

   Update:

   - `SKILL.md` quick reference and config template
   - `agents/go.md` for review/evidence gate sequencing
   - `agents/run.md` or a new `agents/review.md` for post-build review
   - `agents/run-worker.md` return schema to include acceptance evidence
   - `agents/config.md` schema/default migration
   - `README.md` installation docs for Claude Code/Codex

9. Run verification

   Execute all shell tests in `lib/tests/*.test.sh` and any bats tests if available. Fix regressions.

10. Report outcome

    Summarize changed files, new behavior, and test results. Call out any gaps intentionally left for a later implementation pass.

