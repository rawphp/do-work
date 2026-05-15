# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Parallel execution (2026-05-15)

`/do-work run` is now safe to launch from multiple terminals simultaneously. Each orchestrator picks a different REQ from the backlog and they coordinate via the filesystem — no flag, no daemon.

**Added**
- Atomic REQ claim via `git mv` + ownership stamp (`**Claimed by:** <hostname.pid>`) committed to git so sibling terminals can see who owns what.
- Multi-slot `working/` pre-flight: classifies each slot as `mine` / `sibling` / `stale` instead of treating any slot as a hard abort. Stale-slot prompt (Reclaim / Return-to-backlog / Abort) batched into one user interaction.
- Runtime same-branch vs worktree isolation heuristic. Worktree mode triggers on large/structural REQs (migrations, refactors, schema changes, ≥3 service deps, >6 acceptance criteria). Worktrees live at `{project}/.worktrees/req-NNN` on `req/REQ-NNN` branches and merge back on completion.
- Wait-and-retry on commit/merge conflicts: 5 retries with 5s / 15s / 30s / 60s exponential backoff. After 5 failures, worker exits with `status: stopped`, `reason: concurrent-conflict`. No silent auto-resolve.
- Milestone mode constrained to "parallel within active milestone only" — orchestrators claim REQs only from `REQ-M<active>-*.md` while a milestone is active. The first orchestrator to detect milestone-complete owns the deploy gate; siblings idle (logging `Idle — waiting on milestone M<n> deploy gate`) and resume when the gate advances.
- Final cross-REQ test suite runs from whichever orchestrator drains last, gated by a `do-work/state/final-suite-running.md` lockfile (or `final-suite-M<n>-running.md` in milestone mode).
- New state files in `do-work/state/`: `gate-owner.md` (records the agent-id currently handling a milestone gate; deleted on resolve).
- `concurrent-conflict` added to the worker's `reason` enum.
- `retry_count` and `isolation` fields added to the worker's Return Report schema.

**Changed**
- The per-REQ announce line is prefixed with `[<agent-id>]` and now also shows `isolation=<mode>` alongside `type=<subagent_type>` and `model=<model>`.
- Pre-flight check no longer aborts on the mere presence of REQs in `working/`. Siblings' live slots are silently respected.

**Compatibility**
- Running `/do-work run` in a single terminal has the same semantics as before. Parallel mode is implicit and only activates when a second terminal joins.
- Existing REQs without ownership stamps in `working/` are classified as `stale` on first encounter and surface the Reclaim/Return/Abort prompt.

## Gap-aware capture (2026-04-29)

**Added**
- `layers:` config field — declare a project's layers (`[frontend, backend]`, `[commands, core, output]`, etc.). Used by capture and verify to enforce gap-aware coverage.
- `**Layer:**` field on every REQ — names which declared layer the REQ belongs to, or `none` for bug-fix / pure-refactor.
- Required `## Integration` section on feature REQs that add new surface — answers reachability / data deps / service deps with concrete file/symbol references.
- UR `input.md` now has YAML frontmatter (`classification`, `layers_in_scope`, `layer_decisions`, `reqs`, `acknowledged_partials`).
- Capture writes a `## Capture summary` block to UR body for at-a-glance review.
- `--no-layers` flag on `start` and `go` — opts a single UR out of layer-coverage checks.
- Ideate ends with a mandatory interactive gate (Grill / Continue / Stop).

**Changed**
- Capture classifies briefs as `bug-fix` / `feature` / `other` and gates layer-coverage and integration passes accordingly.
- Verify reads UR frontmatter; new checks for layer coverage, Integration block, partial-confidence.
- Verify `--auto-fix` re-runs capture's relevant pass for layer / integration gaps.

**Removed**
- `--grill` flag on start. Users choose Grill at the ideate gate after seeing surfaced gaps.

**Compatibility**
- Existing URs without YAML frontmatter are treated as legacy. Verify skips all new checks for them; they continue to work as before.
- Existing REQs without a `**Layer:**` field are similarly exempt. No migration script.

## [1.0.0] - 2026-03-14

### Added

- `/do-work start [brief]` — records brief, runs ideate, and decomposes into REQ files in one shot
- `/do-work go [UR-NNN]` — verifies REQ coverage and auto-runs if confidence >= 90%
- `/do-work intake [brief]` — records brief verbatim as next UR file
- `/do-work capture [UR-NNN]` — decomposes a UR into discrete REQ task files
- `/do-work ideate [UR-NNN]` — surfaces assumptions, risks, and connections before decomposition
- `/do-work verify [UR-NNN]` — scores REQ coverage against the original brief (0-100%)
- `/do-work run` — executes backlog with TDD loop, one REQ at a time, commit per REQ
- `/do-work install` — creates per-project `do-work/` folder structure
- `--no-ideate` flag for `start` to skip creative review
- `--force` flag for `go` to run regardless of confidence score
- `--auto-fix` flag for `go` and `verify` to auto-create missing REQs
- One-liner install script (`install.sh`)
- MIT license
- Contributing guide
