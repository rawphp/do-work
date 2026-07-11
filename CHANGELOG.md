# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

**Session telemetry emitter + hooks (REQ-037)**

**Added**
- `lib/emit-event.sh <project> <type> <session> [data-json]`: appends one well-formed JSON line (`{ts, session, type, data?}`) to `{project}/.do-work/state/events.jsonl`, creating `state/` defensively with a single atomic append. Matches the consumer extension's event-stream parser contract.
- `lib/session-hook.sh <start|end>`: Claude Code `SessionStart` / `Stop` hook entry point. Reads `session_id` (and `cwd`) from the hook stdin JSON, emits `session.start` (with `data.marker` from `$DO_WORK_UI_MARKER` when set) or `session.end`. A silent no-op (exit 0, no writes) in any project without `.do-work/`; always exits 0 so a hook never breaks the session.
- `lib/install-hooks.sh [--check] <project>`: idempotently merges the two hooks into `{project}/.claude/settings.json` (python3-backed, dedups by command string, preserves unrelated settings). Degrades gracefully to `skipped` when python3 is absent.
- `/do-work install` now wires the session hooks; `/do-work upgrade` gains a `session-hooks` conformance row that adds them idempotently to existing projects.

**Advisory manual-checks model replaces approve/reject**

**Removed**
- `/do-work approve` and `/do-work reject` commands.
- The `pending-validation` REQ status and the `.do-work/pending/` directory.
- The `notifications.on_pending_validation` config key.

**Added**
- `/do-work upgrade`: explicit conformance command for project maintenance. `lib/conformance-scan.sh` is a state-probing conformance manifest — it runs a read-only scan at startup; destructive fixes (e.g. removing a retired config key) run only inside `upgrade`, after confirmation.
- `**Suite:** not-run` header marker: written on an archived REQ when its own test/build suite could not be provisioned in the worker's worktree. `lib/derive-status.sh` derives such a REQ `unproven`.

**Changed**
- `## Post-merge validation` renamed to `## Manual checks (advisory)`. Human/device checks are advisory only, never block archive, and are not surfaced by any command automatically.
- `proven` semantics: a REQ whose own test/build suite could not be provisioned now derives `unproven` (via the `**Suite:** not-run` marker) even though it still archives as `done`. Human/device advisory items still never affect proven-ness.

**Migration**
- Nothing replaces `approve`/`reject`: REQs archive as `done` once automated gates (tests, verification, review, policy) pass; human follow-up now lives in the archived REQ's `## Manual checks (advisory)` checklist instead of a blocking pending state.
- Nothing replaces the `notifications.on_pending_validation` hook. Remove the key from `.do-work/config.yml` — `/do-work upgrade` detects and removes retired keys automatically.
- Scripted consumers of `pending-validation` status or `.do-work/pending/` must drop those code paths; both are gone.

**Added**
- Archive-integrity guardrail: `lib/check-archive-integrity.sh` runs at the persistence boundary (`agents/run.md` Step 4b / 4-pr.4) and rejects archiving a `done` REQ unless its on-disk state is internally consistent — `**Status:** done`, a non-empty `**Closure proof:**`, and zero unchecked `- [ ]` items inside `## Acceptance Criteria`. Replaces trust in worker/orchestrator prose (the worker is *instructed* to tick each `- [x]` and set status, but that is an LLM step it can silently skip). A failure stops the REQ with `**Reason:** archive-integrity` instead of archiving. Covered by `lib/tests/check-archive-integrity.test.sh`. Root-caused from a data-quality audit that found 37 archived REQs with stale (non-`done`) status and 50 archived `done` REQs with unchecked acceptance criteria.

**Changed**
- `**Criteria approved:** agent-drafted` no longer stops dispatch. Criteria provenance remains visible, but existing backlog REQs run unless dependencies, footprint, policy, tests, verification, review, or genuinely ambiguous criteria stop them.

## Feature completeness model (2026-06-09)

**Added**
- Path-unit capture model: feature work is organized around reachable paths with `**Entry point:**`, `**Terminal state:**`, and child `**Parent:**` REQs.
- Closure proof field: `**Closure proof:**` records evidence from passed verification/checkpoint logs while writable `**Status:**` remains coordination state.
- Derived proof view: `lib/derive-status.sh` computes `proven` / `unproven`; `lib/coverage-rollup.sh` summarizes intended vs proven REQs by UR.
- Criteria provenance: `**Criteria approved:** agent-drafted` marks agent-written acceptance criteria; it is provenance rather than a run-blocking requirement.
- Checkpointed closure: verification steps are ordered checkpoints that report the last good step and failing handoff.
- Dual install target: `install.sh --env claude` installs into `~/.claude/skills/do-work`; `install.sh --env codex` installs into `~/.codex/skills/do-work`.
- Governance gates: `/do-work run` validates per-criterion acceptance evidence, deterministic policy checks, post-build review, and run ledger records before archive completion.
- Policy and ledger helpers: `lib/check-policy.sh` enforces `security.blocked_paths`, `security.blocked_commands`, and `risk.require_review`; `lib/run-ledger.sh` writes `.do-work/runs/RUN-NNN.yml`.

**Why**
- The goal is to prevent feature-completeness drift: built-but-unwired work, unproven closure, and vague completion reports should surface as explicit unproven state rather than relying on a human to notice.
- Worker output is treated as evidence for the orchestrator and review gate; archive/proof state is assigned only after acceptance evidence, review, policy, and closure-proof checks pass.

## REQ-scoped commits (2026-05-18)

Workers and orchestrators no longer use broad git-add sweeps. Every commit stages only paths keyed to its own REQ (or, for orchestrator-owned commits, the single state file the orchestrator is changing). Under parallel execution this prevents a worker from accidentally including a sibling's claim file, in-flight working/ slot, or unrelated state edits in its REQ commit.

**Changed**
- `agents/run-worker.md` Step 8 (Commit) — replaced the `git add -A {project}/do-work/` sweep with an explicit four-category staging list (REQ lifecycle, UR directory, logs/state, implementation files), plus a forbidden-paths list and a pre-stage `git status` check. The same explicit-paths rule now applies in both `same-branch` and `worktree` modes.
- `agents/run.md` Step 1 (Claim) — added an explicit "stage only this REQ's path" note to the claim commit. Behaviour unchanged; intent clarified.
- `agents/run.md` Pre-flight "Return to backlog" — added a concrete example showing only the single REQ's path being staged when returning a stale claim.

**Why**
- Under parallel `/do-work run`, a `git add -A do-work/` sweep can capture sibling agents' files that happen to be dirty in the working tree (their claim stamps mid-commit, their working/ slot edits, orchestrator-owned state files). The resulting REQ commit becomes a tangle of "this REQ + whatever else was in flight", which corrupts git blame, breaks REQ-to-commit attribution, and can cause the final-suite failure-attribution map (`git diff-tree -r <hash>`) to point at the wrong REQ.
- The rule is now: a commit stages exactly the paths owned by the agent making the commit, for the REQ (or state-file role) it is currently performing.

## Parallel execution (2026-05-15)

`/do-work run` is now safe to launch from multiple terminals simultaneously. Each orchestrator picks a different REQ from the backlog and they coordinate via the filesystem — no flag, no daemon.

**Added**
- Atomic REQ claim via `git mv` + ownership stamp (`**Claimed by:** <hostname.pid>`) committed to git so sibling terminals can see who owns what.
- Multi-slot `working/` pre-flight: classifies each slot as `mine` / `sibling` / `stale` instead of treating any slot as a hard abort. Stale-slot prompt (Reclaim / Return-to-backlog / Abort) batched into one user interaction.
- Runtime same-branch vs worktree isolation heuristic. Worktree mode triggers on large/structural REQs (migrations, refactors, schema changes, ≥3 service deps, >6 acceptance criteria). Worktrees live at `{project}/.worktrees/req-NNN` on `req/REQ-NNN` branches and merge back on completion.
- Wait-and-retry on commit/merge conflicts: 5 retries with 5s / 15s / 30s / 60s exponential backoff. After 5 failures, worker exits with `status: stopped`, `reason: concurrent-conflict`. No silent auto-resolve.
- Milestone mode constrained to "parallel within active milestone only" — orchestrators claim REQs only from `REQ-M<active>-*.md` while a milestone is active. The first orchestrator to detect milestone-complete owns the deploy gate; siblings idle (logging `Idle — waiting on milestone M<n> deploy gate`) and resume when the gate advances.
- Final cross-REQ test suite runs from whichever orchestrator drains last, gated by a `.do-work/state/final-suite-running.md` lockfile (or `final-suite-M<n>-running.md` in milestone mode).
- New state files in `.do-work/state/`: `gate-owner.md` (records the agent-id currently handling a milestone gate; deleted on resolve).
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
- `/do-work install` — creates per-project `.do-work/` folder structure
- `--no-ideate` flag for `start` to skip creative review
- `--force` flag for `go` to run regardless of confidence score
- `--auto-fix` flag for `go` and `verify` to auto-create missing REQs
- One-liner install script (`install.sh`)
- MIT license
- Contributing guide
