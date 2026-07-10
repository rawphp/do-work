---
name: do-work
description: >
  Project management skill for the do-work system — a file-based autonomous loop
  that turns natural-language briefs into discrete, traceable tasks (REQ files)
  and executes them one at a time with TDD and a git commit per task.
  Triggers on: "do-work", "intake", "capture", "verify", "run the loop",
  "backlog", "user request", "REQ-", "UR-", "question", "audit".
---

# do-work

File-based project management: Start → Go. (Or granular: Intake → Capture → Verify → Run.)

## Quick Reference

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Records brief + decomposes into REQs in one shot. Includes ideate by default. Auto-installs if needed. |
| `/do-work start [brief] --no-ideate` | Same as start, but skips the creativity review before decomposition. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks for this UR (records `layers_in_scope: []`). |
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of confidence score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs if >= 90%. |
| `/do-work go [UR-NNN] --no-layers` | Verify + run, skipping layer-coverage checks for this UR. |
| `/do-work install` | Creates `.do-work/` structure in current project. |
| `/do-work upgrade` | Brings the project's .do-work/ state into conformance with the current skill — runs the manifest's detectors and applies fixes (interactive confirmation on destructive rows). Idempotent. |
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR brief into REQ files in the backlog. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections in a brief. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage against brief (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run [UR-NNN]` | Executes backlog: TDD loop, evidence validation, post-build review gate, archive/ledger. Optional UR-NNN scopes the run to that UR's REQs only. |
| `/do-work run [UR-NNN] --parallel N` | Single-session parallel mode: one terminal dispatches up to N concurrent workers (default 1 = serial, capped at 10), serializing merge/archive through a queue. Defaults from `parallel.max_workers`. |
| `/do-work run [UR-NNN] --budget <amount>` | Caps cumulative estimated model spend for the run; overrides `cost.budget` for this invocation. When estimated spend reaches the budget, the loop finishes the in-flight REQ's integration then stops at the next REQ boundary with a budget-stop report. Empty budget = unlimited (default). |
| `/do-work review` | Internal post-build gate used by run after worker evidence validation and before archive completion; not directly invocable — see agents/review.md. |
| `/do-work status [UR-NNN]` | Renders live situation room: REQs, claimers, heartbeats, deadlock warnings, and coverage rollup. Optional UR-NNN scopes the report. |
| `/do-work close UR-NNN` | Validates the integrated result of a UR against its verbatim brief — walks every path-unit's entry point to its terminal state in the merged app and writes a closure report. |
| `/do-work retro` | Mines the run ledger and feedback fingerprints to produce a human report and regenerate `.do-work/state/calibration.md` — advisory capture guidance derived from historical patterns. |
| `/do-work unblock REQ-NNN` | Forces a stuck REQ out of working/ back to the backlog — strips claim stamp, resets status. |
| `/do-work resume REQ-NNN` | Re-dispatches a fresh worker for a stopped REQ — preserves claim, refreshes heartbeat. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show this help. |

---

## Agent files

Detailed instructions for each phase live in separate files. Read the referenced file and follow it exactly.

- [agents/start.md](agents/start.md) — Orchestrator: intake + ideate + capture
- [agents/go.md](agents/go.md) — Orchestrator: verify + conditional run
- [agents/intake.md](agents/intake.md) — Records brief verbatim as next UR file
- [agents/upgrade.md](agents/upgrade.md) — Brings project state into conformance with the current skill
- [agents/question.md](agents/question.md) — Interactive brief questioning
- [agents/audit.md](agents/audit.md) — Autonomous REQ quality audit
- [agents/ideate.md](agents/ideate.md) — Surfaces assumptions, risks, and connections
- [agents/capture.md](agents/capture.md) — Decomposes brief into REQ files
- [agents/verify.md](agents/verify.md) — Scores REQ coverage against brief
- [agents/run.md](agents/run.md) — Orchestrator: dispatches a worker subagent per REQ
- [agents/run-worker.md](agents/run-worker.md) — Worker: TDD-and-commits a single REQ in a fresh subagent session
- [agents/review.md](agents/review.md) — Post-build gate: reviews scope, acceptance evidence, tests, secrets, docs, and regression risk before archive
- [agents/status.md](agents/status.md) — Read-only situation room: REQs, claimers, heartbeats, deadlock warnings, coverage rollup
- [agents/close.md](agents/close.md) — Validates the integrated result of a UR against its verbatim brief; walks path-unit entry points in the merged app; writes `UR-NNN/closure.md`
- [agents/unblock.md](agents/unblock.md) — Force a stuck in-flight REQ back to the backlog
- [agents/resume.md](agents/resume.md) — Re-dispatch a fresh worker for a stopped REQ
- [agents/log.md](agents/log.md) — Generates build-in-public draft posts
- [agents/retro.md](agents/retro.md) — Mines the run ledger to produce a learning report and regenerate `calibration.md`
- [agents/config.md](agents/config.md) — Reusable config loading instructions

Run ledger: when `ledger.enabled: true`, `/do-work run` writes append-only `.do-work/runs/RUN-NNN.yml` records with model, cost, commands, tests, changed files, review outcome, result, and proof status. Set `ledger.enabled: false` to disable ledger writes.

---

## Project Root Detection

At the start of every subcommand:

```bash
git rev-parse --show-toplevel
```

If this fails (not a git repo), use the current working directory.
All references below use `{project}` to mean this resolved root.

### Conformance check

Immediately after resolving `{project}` and before executing any subcommand-specific instructions, run the conformance detectors:

```bash
bash lib/conformance-scan.sh {project}
```

The scanner is read-only and may exit `1` when drift is detected. Interpret each output line as `<row-id> <class> <detail>`:

- `legacy-dir safe-blocking ...` — auto-apply the `legacy-dir` fix from [agents/upgrade.md](agents/upgrade.md)'s conformance manifest inline, preserving the existing legacy `do-work/` → `.do-work/` behaviour and advisory consumer-ref scan. Output `Migrated do-work/ → .do-work/` and continue.
- `dir-conflict blocking ...` — halt with the existing verbatim conflict message:

```
Migration conflict: both do-work/ and .do-work/ exist at {project}. Resolve manually before re-running.
```

- `pending-dir destructive ...` — print `pending/ detected — run /do-work upgrade to archive & remove it` and continue.
- `stale-config-key destructive ...` — print `stale config key(s) detected — run /do-work upgrade to remove retired config keys` and continue.
- Unknown row ids — print the scanner line verbatim and continue for forward compatibility.

Startup never applies destructive fixes and never prompts. Destructive rows are handled only by explicit `/do-work upgrade`.

**No mid-flight protection.** The `legacy-dir` safe-blocking fix does not inspect `working/` for in-flight REQs before migrating. Migration is rare in practice; the assumption is that the user runs it on an idle project. A migration that runs while a parallel `/do-work run` is mid-REQ will cause that worker to fail on the next file-system access — accept that risk rather than introducing a coordination layer for a once-per-project event.

**Critical: skill directory is read-only at runtime.** The skill is loaded from `~/.claude/skills/do-work/` — this is a separate git clone. NEVER edit files, stage changes, or commit inside the skills directory. All edits and commits MUST happen in `{project}`. If a REQ targets agent files (e.g. `agents/log.md`), edit them at `{project}/agents/log.md`, not at the skill clone path.

---

## File Naming

- User requests: `UR-001`, `UR-002`, ... (zero-padded to 3 digits)
- Feature requests: `REQ-001-short-slug.md`, `REQ-002-short-slug.md`, ...
- Slugs are lowercase kebab-case, max 5 words

## Milestone Mode

When a UR file contains both:

1. The marker `source: /saas-thesis handoff` (in frontmatter or body)
2. A `### Milestones` heading with `#### M1` (or higher) subheadings

`/do-work` enters **milestone mode**. The differences from normal flow:

- Capture decomposes ONE milestone at a time, not the whole UR.
- REQ files are prefixed: `REQ-M1-001-<slug>.md`, `REQ-M2-001-<slug>.md`.
- Run loop halts at the end of each milestone's REQs and prompts for the deploy gate.
- Deploy-gate sign-off is non-delegable human confirmation.
- State files in `{project}/.do-work/state/`:
  - `active-milestone.md` — single line, current milestone identifier (e.g. `M1`).
  - `milestones.md` — checklist of all milestones with status: `pending` / `captured` / `running` / `deployed`.

Milestone mode is **implicit** — triggered by UR shape, not a flag. URs that do not match the trigger continue to behave as before. The `/saas-thesis` skill produces UR files with the correct shape for handoff.

## Parallel Execution

do-work offers parallelism two complementary ways. **Multi-terminal mode** (below) needs no flag — launch `/do-work run` from several terminals and the coordination layer keeps them from colliding. **Single-session parallel mode** (`--parallel N`) lets one terminal fan out N concurrent workers itself. The two compose: one `--parallel 3` orchestrator and two plain `/do-work run` terminals are just three agent-ids in the same claim arbitration.

`/do-work run [UR-NNN]` is safe to launch from multiple terminals simultaneously. Up to 10 orchestrators can run in parallel — each claims a different REQ from the backlog. Coordination is handled by a dedicated library layer; no flag, no daemon, no in-memory state is required for multi-terminal mode.

### Single-session parallel mode (`--parallel N`)

`/do-work run [UR-NNN] --parallel N` makes **one** orchestrator dispatch up to `N` concurrent workers from a single terminal, integrating their results through a serialized merge queue. It does not replace multi-terminal mode — it adds one-terminal parallelism on top of the same coordination primitives.

- **Window width `N`.** The maximum number of concurrently dispatched workers. Effective `N = min(flag-or-config, 10)`.
- **Default `N = 1`** (absent flag, `--parallel 1`, or `parallel.max_workers: 1`) ⇒ the serial loop runs byte-for-byte unchanged; the parallel code path is entered only when `N > 1`.
- **Config default.** `parallel.max_workers` in `.do-work/config.yml` (default `1`, under the existing `parallel:` section alongside `parallel.stale_threshold_seconds`) sets the project default. The `--parallel` flag overrides it per-run.
- **Cap `10`.** A request above 10 is clamped to 10 with a one-line notice, matching the 10-orchestrator design bound and protecting the shared main working tree, git object store, and the single `feedback.lock`.

**How it works** (full spec: `agents/run.md` `## Parallel Run Mode`; design: `docs/design/single-session-parallel.md`):

- **Fan-out** is N concurrent `Agent`-tool dispatches in one turn — the same dispatch surface serial mode uses, not a separate scheduler.
- **Claim-as-slot-frees.** The orchestrator claims one REQ immediately before each dispatch (never a batch up front) so `pick-req.sh`'s footprint exclusion sees each claim before the next pick. The window refills one REQ each time a slot frees.
- **Serialized merge queue.** Workers return on `req/REQ-NNN` branches in any order. Integration runs in two stages: **Stage A** (acceptance-evidence → policy → independent review) is read-only and may run N-wide; **Stage B** (ledger → merge → archive → teardown → metadata commit) is serial, single-writer — at most one merge/archive touches the main working tree and `.do-work/` at any instant, exactly as serial mode.
- **Failure isolation.** One stopped worker (or a failed gate / a 5-retry merge exhaustion → `concurrent-conflict`) frees its slot and surfaces per-REQ in arrival order; the other workers and queued reports proceed. No new stopper reasons.
- **Deploy gates stay single-flow.** Milestone deploy gates are not parallelised — the existing first-to-detect drain check and single y/n prompt are unchanged; fan-out pauses new claims while a gate is open.
- **Coordination lib untouched.** `pick-req.sh`, `claim-req.sh`, `check-footprint.sh`, `scan-stale.sh` and the rest keep their contracts; this mode is a run-loop shape change, not a primitive change.

### Coordination Layer

**Footprint-aware claiming.** Before claiming a REQ, each orchestrator calls `lib/pick-req.sh` to identify the next safe candidate. `lib/pick-req.sh` uses `lib/check-footprint.sh` to detect file-level overlap between the candidate and every REQ currently in `working/`. If overlap exists, the candidate is skipped and the next backlog entry is evaluated. This eliminates the primary source of cross-agent file conflicts.

**Dependency-aware ordering.** `lib/pick-req.sh` also calls `lib/check-deps.sh` to verify that all `Depends on:` REQs listed in the candidate's header have been archived (status: done) before the candidate is eligible. Circular dependency chains are gated at capture time by `lib/cycle-check.sh` — a dependency graph with a cycle will be rejected during capture, not at run time.

**Atomic claim.** Once a safe, dep-satisfied candidate is selected, `lib/claim-req.sh` writes the ownership stamp atomically:

```markdown
<!-- claimed-start -->
**Claimed by:** hostname.pid
**Claimed at:** 2026-05-21T11:42:08Z
**Heartbeat:** 2026-05-21T11:42:08Z
<!-- claimed-end -->
```

**Checkpoint-based liveness.** Each worker stamps the `**Heartbeat:**` timestamp in its REQ file via `lib/heartbeat.sh` at natural progress checkpoints — after reading the REQ, after each TDD cycle, after each verification step, and before commit — rather than from a background timer (a backgrounded loop cannot survive a fresh-shell-per-call harness). `lib/scan-stale.sh` (called during pre-flight and by `/do-work status`) flags REQs whose heartbeat is older than `parallel.stale_threshold_seconds` (default 900 s / 15 minutes — sized to span the gap between checkpoints) as potentially dead. Stale REQs surface in the status report for human triage — they are not automatically unblocked.

**Deadlock detection.** `lib/deadlock-check.sh` checks for circular wait chains across the `working/` set: does REQ-A depend on REQ-B which depends on REQ-A (both in-flight)? Any cycle found is reported immediately by `/do-work status` under a `DEADLOCK DETECTED` banner. Recovery is manual: use `/do-work unblock REQ-NNN` to break the cycle.

**Visible differences from single-agent mode:**

- The per-REQ announce line is prefixed with `[<agent-id>]` (where `agent-id` is `hostname.pid`) so you can attribute output across terminals.
- Multiple REQs appear in `working/` simultaneously, each carrying the ownership stamp above.
- The final cross-REQ test suite runs once, from whichever orchestrator drains last (gated by `.do-work/state/final-suite-running.md` lockfile).
- On a commit or merge conflict, the losing worker waits up to ~110 seconds (5 retries: 5s / 15s / 30s / 60s backoff) before exiting with `status: stopped`, `reason: concurrent-conflict`. Use `/do-work resume REQ-NNN` to re-dispatch.

### Isolation per REQ

Workers always run in isolated git worktrees at `{project}/.worktrees/req-NNN` on a `req/REQ-NNN` branch. The orchestrator merges the branch back into the base branch and tears down the worktree after integration. See [agents/run-worker.md](agents/run-worker.md) `## Isolation Mode` and `## Worktree Workflow` for the canonical procedure.

### Recovery Commands

| Situation | Command |
|---|---|
| REQ is stuck / worker died / heartbeat stale | `/do-work unblock REQ-NNN` — strips claim, returns REQ to backlog |
| REQ stopped (concurrent-conflict / transient error) | `/do-work resume REQ-NNN` — refreshes heartbeat, re-dispatches worker |
| Deadlock or unclear state | `/do-work status [UR-NNN]` — renders live situation room, deadlock banner |

See `agents/status.md`, `agents/unblock.md`, `agents/resume.md` for agent-level instructions.

### Constraints That Stay Single-Agent

- Milestone deploy gates remain non-delegable — the first orchestrator to detect milestone-complete owns the gate; siblings idle (logging `Idle — waiting on milestone M<n> deploy gate`) and resume when `.do-work/state/active-milestone.md` advances. `.do-work/state/gate-owner.md` records the gate owner.
- The stale-slot prompt in pre-flight runs in whichever orchestrator finds the stale slot first.

### State Files

All coordination state lives under `.do-work/state/`:

- `gate-owner.md` — agent-id currently handling a milestone deploy gate (deleted on resolve).
- `final-suite-running.md` (or `final-suite-M<n>-running.md` in milestone mode) — lockfile for the final cross-REQ test suite.

### Implementation Reference

- Claim: `lib/pick-req.sh`, `lib/check-footprint.sh`, `lib/claim-req.sh`
- Dependencies: `lib/check-deps.sh`, `lib/cycle-check.sh`
- Liveness: `lib/heartbeat.sh`, `lib/scan-stale.sh`
- Deadlock: `lib/deadlock-check.sh`
- Archive integrity: `lib/check-archive-integrity.sh` — pre-archive gate enforcing Status `done` + non-empty Closure proof + zero unchecked acceptance criteria (`agents/run.md` Step 4b/4-pr.4)
- Orchestrator: `agents/run.md` §§ Agent Identity, Pre-flight Check, Step 1: Claim the next REQ, When the Backlog is Empty, Step 7b
- Worker: `agents/run-worker.md` §§ Isolation Mode, Worktree Workflow, Concurrent-Conflict Retry

## Layers

do-work uses project-declared layers to gap-check feature briefs. Declare your project's layers once in `.do-work/config.yml`:

```yaml
layers: [frontend, backend]   # web app
# layers: [commands, core, output]            # CLI tool
# layers: [public_api, internal]              # library / SDK
# layers: [agents, commands, templates]       # do-work itself
```

Capture and verify use this list to enforce that REQs cover every declared layer for `feature`-class briefs (or surface explicit "no" decisions). Empty `layers:` opts out — feature briefs will halt until layers are declared or `--no-layers` is passed.

Every REQ written by capture carries a `**Layer:**` field naming one of the declared layers, or `none` for bug-fix / pure-refactor / test-only REQs.

Feature REQs that add new surface (anything callable or visible from outside their own code) include an `## Integration` section answering three sub-questions:

- **Reachability** — How does the user (or caller) reach this?
- **Data dependencies** — What existing data does this read or write?
- **Service dependencies** — What existing services or modules does this extend?

Capture inspects the codebase to draft answers and verifies each cited file/symbol exists before claiming high confidence. Verify enforces the Integration block on every non-`none` feature REQ.

## Path Units

For feature-class briefs, capture decomposes by reachable path first. A path-unit is a top-level REQ that names:

- `**Entry point:**` — how a user, caller, command, or system reaches the path.
- `**Terminal state:**` — the observable end state that proves the path closed.

Layer-specific work is captured as child REQs underneath the path-unit. Child REQs carry the normal `**Layer:**` value and point back to the path-unit with `**Parent:** REQ-NNN`. Layers therefore operate inside path-units: they still prevent frontend/backend/command/template gaps, but the closure unit is the reachable path.

Migration is additive. Legacy REQs without `**Entry point:**`, `**Terminal state:**`, or `**Parent:**` remain valid. New path-units must have both entry point and terminal state before they can verify or archive as complete.

## Decisions Memory

`.do-work/decisions.md` is an append-only, cross-UR record of standing decisions (ADR-lite). It gives capture, ideate, and workers a shared institutional memory so a call made in one UR ("validation lives server-side") is not re-litigated or contradicted in the next.

**Format** — one line per decision, no paragraphs (this is a memory, not documentation; anything needing prose belongs in a design doc):

```
YYYY-MM-DD | UR/REQ ref | decision | rationale
```

- `YYYY-MM-DD` — the date the decision was recorded.
- `UR/REQ ref` — the UR or REQ the decision was made under (e.g. `UR-035` or `REQ-224`).
- `decision` — the standing choice, stated as a constraint.
- `rationale` — one phrase explaining why.

**Discipline:**

- **Append-only.** Never rewrite or delete an existing line.
- **Supersede with a new line.** To reverse or change a decision, append a fresh line that references the superseded one (e.g. `... | supersedes 2026-06-01 entry | ...`). The old line stays as history.
- **The file is optional.** No agent creates it; it comes into being when the first decision is appended. An absent file is silently fine everywhere it is read.

**Writers:** capture appends a line at judgment points where a choice shapes the decomposition (a layer opt-out, a split-vs-merge call, a layer-coverage user answer). **Readers:** capture (Step 1), ideate (Step 2 project context), run-worker (Step 2 — treats standing decisions as constraints), and question all read it when present.

## REQ Header Schema

Every REQ file carries a structured header immediately below the title. The canonical field list is:

| Field | Required | Description |
|---|---|---|
| `**UR:**` | yes | Parent UR identifier (e.g. `UR-030`) |
| `**Status:**` | yes | `backlog` / `in-progress` / `stopped` / `done` |
| `**Created:**` | yes | ISO date (YYYY-MM-DD) |
| `**Layer:**` | yes | Declared project layer, or `none` for bug-fix/refactor/test-only REQs |
| `**Entry point:**` | optional | How a user, caller, command, or system reaches this path-unit. Required to be non-empty for top-level path-unit REQs. |
| `**Terminal state:**` | optional | The observable end state that proves this path-unit is complete. Required to be non-empty for top-level path-unit REQs. |
| `**Parent:**` | optional | Parent path-unit REQ id for child layer-tasks. Empty or absent on top-level path-units and legacy REQs. |
| `**Closure proof:**` | optional | Evidence reference proving verification passed, such as `checkpoint:.do-work/runs/RUN-001.yml#REQ-123` or `commit:abc123 tests:passed`; empty until proven. |
| `**Suite:**` | optional | Written by the run orchestrator during advisory-check consolidation when the worker's own test/build suite could not be provisioned; the only value is `not-run`. Consumed by `lib/derive-status.sh`, which derives such a REQ `unproven` regardless of an otherwise-passing closure proof. Absent on normal REQs. |
| `**Criteria approved:**` | optional | Acceptance-criteria provenance: `agent-drafted` when capture generated it, or `human <approver> <YYYY-MM-DD>` when a human previously reviewed it. This field does not block run. |
| `**Priority:**` | optional | Backlog urgency `1`–`3` (3 = most urgent), derived by capture from dependency-graph depth. Read by `lib/pick-req.sh` to order claimable candidates (Priority desc, then REQ number asc). Absent or out-of-range sorts as `2`, so legacy REQs are unaffected. |
| `**Size:**` | optional | Effort estimate `S` / `M` / `L`, derived by capture from file count, layer span, and criteria count. `Size: L` is a primary opus-escalation signal in `agents/run.md` Model Selection. Absent falls back to the lexical heuristics. |
| `**Files:**` | yes | Space-separated list of primary output files — used by `lib/check-footprint.sh` for overlap detection |
| `**Depends on:**` | optional | Space-separated REQ ids this REQ must not start before (e.g. `REQ-144 REQ-145`) — checked by `lib/check-deps.sh` |

A **path-unit** is a REQ whose `**Entry point:**` and `**Terminal state:**` are both non-empty. Path-units describe a vertical, reachable slice of intent. Child layer-tasks point back to a path-unit with `**Parent:**`; legacy REQs without these fields remain valid because the migration is additive.

`**Status:**` remains writable and authoritative for coordination (`backlog`, `working/`, dependency gating, stale checks, and archive flow). `**Closure proof:**` is a separate evidence signal used to derive whether a done REQ is proven; it does not replace the coordination status field.

### `## Manual checks (advisory)` section

An optional REQ body section that holds human, device, or environment checks that cannot be executed by a worker in an isolated worktree.

**Written by:** `agents/capture.md` on path-unit REQs (or the single REQ for legacy-style decompositions) when the brief includes checks that require a human, a physical device, or an environment the worker cannot provision. Capture writes this section — and its executability self-correction scan (Step 4b) moves any mis-classified `## Verification Steps` entries here automatically before committing REQ files.

**Advisory only:** Workers never execute `## Manual checks (advisory)` items. The section is explicitly outside the checkpoint loop, never blocks archive, and is not part of the worker's checkpoint log.

**Archived by run:** `/do-work run` consolidates worker-reported `deferred_checks:` and any existing `## Manual checks (advisory)` items into the archived REQ, then completes the normal `done` archive path once automated gates pass.

**Advisory record only:** `## Manual checks (advisory)` items are preserved in the archived REQ as an advisory record for humans. They sit outside the system's validation gate and are not surfaced by any command automatically.

**One exception — the un-run suite:** human and device advisory items never affect proven-ness. An un-run test/build suite is different: alongside its advisory bullet, the run orchestrator also stamps `**Suite:** not-run` on the archived REQ, which `lib/derive-status.sh` reads to derive the REQ `unproven`.

**Format (each item):** a checklist line stating what a person should do and what observable outcome confirms it:

```markdown
## Manual checks (advisory)

- [ ] [Action: what a person should do] — Observable outcome: [what they should see or confirm]
```

`**Criteria approved:** agent-drafted` means capture generated the acceptance criteria. It is informational provenance, not a run gate. Existing backlog REQs should run unless dependencies, footprint, policy, tests, verification, review, or genuinely ambiguous criteria stop them.

When a REQ is claimed by a worker, a claim block is inserted between the title and the first header field:

```markdown
<!-- claimed-start -->
**Claimed by:** hostname.pid
**Claimed at:** 2026-05-21T11:42:08Z
**Heartbeat:** 2026-05-21T11:42:08Z
<!-- claimed-end -->
```

The heartbeat timestamp is refreshed in-place by `lib/heartbeat.sh` — this is a filesystem-only operation, never a git commit. Canonical documentation: `.do-work/archive/REQ-144-extend-req-template-schema.md`.

## Commit Convention

```
feat(REQ-NNN): short title

REQ: .do-work/archive/REQ-NNN-slug.md
UR: .do-work/user-requests/UR-NNN/input.md
Output: path/to/primary/output
```

Commits are created per-REQ on completion. The claim/heartbeat update path (`lib/heartbeat.sh`) is filesystem-only — it writes directly to the REQ file and does **not** produce a git commit. Unblock operations use `chore(REQ-NNN): unblock — return to backlog` as the commit message.

## Checkpointed Verification

REQ `## Verification Steps` are ordered checkpoints. Workers execute them in sequence and record a checkpoint log that localizes both success and failure:

```yaml
req: REQ-NNN
status: passed | failed
checkpoints:
  - step: 1
    total: 3
    type: test
    command: "npm test -- --filter settings"
    status: passed
  - step: 2
    total: 3
    type: runtime
    command: "curl http://localhost:3000/settings"
    status: failed
    handoff: "route -> render"
last_good_step: 1
failed_step: 2
```

On failure, the log must answer: which step failed, at which handoff, and what the last good step was. On success, the full passed checkpoint log becomes the natural target for `**Closure proof:**`.

---

## Subcommand Instructions

### No subcommand

Print the Quick Reference table, then read and follow [agents/help.md](agents/help.md) to display contextual suggestions.

---

### install

Create the do-work folder structure. Idempotent — safe to run multiple times.

1. Detect `{project}`.
2. Create directories if they do not already exist:
   - `{project}/.do-work/user-requests/`
   - `{project}/.do-work/working/`
   - `{project}/.do-work/archive/`
   - `{project}/.do-work/logs/`
   - `{project}/.do-work/state/`
3. Create `{project}/.do-work/config.yml` if it does not already exist, using the bootstrap template below. This template contains the keys most commonly customised at install time. The full default template — including all sections, defaults, and inline documentation — is the canonical template in `agents/config.md`. On first agent run, the config loader in `agents/config.md` migrates any missing sections and keys from that canonical template automatically, so new installs receive all defaults without needing the full template written to disk by install.

```yaml
# do-work configuration
# Edit this file to customize agent behavior.
# Full schema and defaults: agents/config.md (canonical template)

project:
  name: ""

# Declare your project's layers, e.g. [frontend, backend] for a web app,
# [commands, core, output] for a CLI, [agents, commands, templates] for do-work.
# Capture and verify use this list to gap-check briefs. Leave empty to
# opt out of layer-coverage checks.
layers: []

test:
  suite_command: ""      # e.g. "./vendor/bin/pest", "npx vitest run", "npm test"
```

4. Report what was created vs already existed. Example:

```
do-work installed at /path/to/project/.do-work/

Created:
  .do-work/user-requests/
  .do-work/working/
  .do-work/archive/
  .do-work/logs/
  .do-work/state/
  .do-work/config.yml

Ready. Run `/do-work start` to record your first brief.
Feature work first needs layers declared in .do-work/config.yml
(e.g. layers: [frontend, backend]), or run start with --no-layers.
See the comment already in config.yml.
```

If already installed, report "Already installed." and stop.

---

### upgrade

Bring the project's `.do-work/` state into conformance with the current skill.

1. Detect `{project}`.
2. Read [agents/upgrade.md](agents/upgrade.md) in full.
3. Follow the upgrade agent instructions exactly.

---

### start [brief] [--no-ideate] [--no-layers]

Record a brief and decompose it into REQ files in one shot. Ideate runs by default and ends with an interactive gate (Grill / Continue / Stop).

1. Detect `{project}`.
2. Check if `{project}/.do-work/` exists. If not, run install automatically first, then continue.
3. Determine the brief:
   - If text was provided after `start`, use it as the brief.
   - If not, ask the user to paste their brief and wait.
4. Note whether `--no-ideate` or `--no-layers` are present in the arguments.
5. Read [agents/start.md](agents/start.md) in full.
6. Follow the start agent instructions exactly. Ideate runs by default unless `--no-ideate` was present. Pass `--no-layers` through to capture if present.

---

### go [UR-NNN] [--force] [--auto-fix]

Verify REQ coverage and conditionally execute the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--force` or `--auto-fix` are present in the arguments.
4. Read [agents/go.md](agents/go.md) in full.
5. Follow the go agent instructions exactly. Pass through any flags.

---

### intake [brief]

Record a natural-language brief as the next UR file. Never skip to planning or implementation.

1. Detect `{project}`.
2. Check if `{project}/.do-work/` exists. If not, run install automatically first, then continue.
3. Determine the brief:
   - If text was provided after `intake`, use it as the brief.
   - If not, ask the user to paste their brief and wait.
4. Read [agents/intake.md](agents/intake.md) in full.
5. Follow the intake agent instructions exactly.

---

### capture [UR-NNN]

Decompose a UR brief into discrete REQ files in the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to capture.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/capture.md](agents/capture.md) in full.
5. Follow the capture agent instructions exactly.

---

### ideate [UR-NNN]

Surface assumptions, risks, and connections in a brief before decomposition.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to review.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/ideate.md](agents/ideate.md) in full.
5. Follow the ideate agent instructions exactly.

---

### question [UR-NNN]

Grill the user about their brief — extract assumptions, gaps, and constraints through one-at-a-time questioning.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to question.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/question.md](agents/question.md) in full.
5. Follow the question agent instructions exactly.

---

### audit [UR-NNN]

Interrogate REQ quality for a given UR — auto-fix soft spots and report changes.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to audit.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/audit.md](agents/audit.md) in full.
5. Follow the audit agent instructions exactly.

---

### verify [UR-NNN] [--auto-fix]

Score REQ coverage against the original brief. List gaps and issues.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--auto-fix` is present in the arguments.
4. Read [agents/verify.md](agents/verify.md) in full.
5. Follow the verify agent instructions. If `--auto-fix` was present, follow the auto-fix section.

---

### run [UR-NNN] [--parallel N] [--budget <amount>]

Execute the backlog autonomously — until empty or a stopper is hit. The optional `UR-NNN` argument scopes execution to that UR's REQs only, ignoring all other backlog entries. The orchestrator dispatches a fresh worker subagent per REQ (see [agents/run-worker.md](agents/run-worker.md)) and reads its structured return report.

By default the orchestrator runs **serially** — one REQ at a time. The optional `--parallel N` flag enables **single-session parallel mode**: one orchestrator dispatches up to `N` concurrent workers from a single terminal, then serializes their integration through a merge queue. See `## Parallel Execution → Single-session parallel mode`.

- `N` is the maximum number of concurrently dispatched workers (the window width). Effective `N = min(flag-or-config, 10)`.
- **Default `N = 1`** (absent flag, `--parallel 1`, or `parallel.max_workers: 1`) ⇒ the serial loop runs byte-for-byte unchanged.
- When `--parallel` is absent, the default comes from **`parallel.max_workers`** in `.do-work/config.yml` (default `1`). The flag overrides config per-run; config sets the project default.
- A request above the cap (e.g. `--parallel 20`) is clamped to `10` with a one-line notice.

**Budget (`--budget <amount>`).** `--budget` caps the run's cumulative **estimated** model spend (a tier-weighted dollar estimate per worker attempt, recorded in the ledger's `cost_estimate_num` field — not a metered bill). It overrides `cost.budget` from `.do-work/config.yml` for this invocation only.

- **Stop semantics.** After each worker attempt's ledger write, the orchestrator sums estimated spend (`lib/run-ledger.sh --sum-run`) and compares it to the budget. When estimated spend reaches the budget, it **finishes the in-flight REQ's integration first** (never abandons a mid-merge), then stops gracefully at the next REQ boundary with a **budget-stop report** (estimated spend vs budget, REQs completed vs remaining). It never silently exceeds an explicit budget.
- **Empty / unset budget ⇒ unlimited** (default behaviour, unchanged). The gate is inert and adds no per-run cost.
- Under `--parallel N`, the same gate rides the merge queue: once the budget is reached the orchestrator stops refilling the window and lets live workers drain, then emits the budget-stop report.

1. Detect `{project}`.
2. Determine UR scope:
   - If `UR-NNN` was provided, record it — the run agent will filter the backlog to that UR.
   - If not provided, the full backlog is in scope.
3. Resolve the parallel window width: `--parallel N` if given, else `parallel.max_workers` (default 1), clamped to 10. `N == 1` runs serial; `N > 1` runs `agents/run.md`'s `## Parallel Run Mode`. Resolve the effective budget: `--budget <amount>` if given, else `cost.budget` (empty = unlimited).
4. Pre-flight checks:
   - Working/ files are classified by agents/run.md's pre-flight (mine/sibling/stale buckets); stale slots are surfaced only when the backlog has no claimable REQ — do not prompt merely because working/ is non-empty.
   - If no `REQ-NNN-*.md` files exist in `{project}/.do-work/` (backlog root) within scope, report "Backlog is empty." and stop.
5. Read [agents/run.md](agents/run.md) in full.
6. Follow the run agent instructions exactly, passing through the UR scope, the resolved parallel window width, and the effective budget.

---

### status [UR-NNN]

Render a read-only live situation room: all in-flight REQs, their claimers, heartbeat ages, any deadlock warnings, and a Coverage section showing intended/proven/unproven REQs.

1. Detect `{project}`.
2. Determine UR scope:
   - If `UR-NNN` was provided, pass it through to scope the report to that UR's REQs.
   - If not provided, all in-flight REQs are reported.
3. Confirm `{project}/.do-work/` exists. If not, report "do-work not installed." and stop.
4. Read [agents/status.md](agents/status.md) in full.
5. Follow the status agent instructions exactly. No state changes, no commits, no prompts.

---

### close UR-NNN

Validate the integrated result of a UR against its verbatim brief — walking every path-unit's entry point to its terminal state in the merged app — and write a per-path-unit closure report.

1. Detect `{project}`.
2. Confirm `UR-NNN` was provided. If not, report "close requires a UR id (e.g. /do-work close UR-042)." and stop.
3. Confirm `{project}/.do-work/user-requests/UR-NNN/input.md` exists. If not, report "UR-NNN not found at {project}/.do-work/user-requests/UR-NNN/. Check the UR number and try again." and stop.
4. Read [agents/close.md](agents/close.md) in full.
5. Follow the close agent instructions exactly. The close agent is dispatched as a fresh subagent — pass only the project do-work path, the UR reference, and the merged branch.

---

### unblock REQ-NNN

Force a stuck in-flight REQ out of `working/` and back into the backlog. Use when a worker died, a concurrent-conflict won't resolve, or scope creep needs human triage.

1. Detect `{project}`.
2. Confirm `REQ-NNN` was provided. If not, report "unblock requires a REQ id (e.g. /do-work unblock REQ-042)." and stop.
3. Confirm `{project}/.do-work/working/REQ-NNN-*.md` exists. If not, report "REQ-NNN is not in working/ — nothing to unblock." and stop.
4. Read [agents/unblock.md](agents/unblock.md) in full.
5. Follow the unblock agent instructions exactly, including the judgment gate on partial commits (Step 3 in the agent file).

---

### resume REQ-NNN

Re-dispatch a fresh worker for a stopped REQ without sending it back through the backlog. Preserves the existing claim stamp; only the heartbeat is refreshed.

1. Detect `{project}`.
2. Confirm `REQ-NNN` was provided. If not, report "resume requires a REQ id (e.g. /do-work resume REQ-042)." and stop.
3. Confirm `{project}/.do-work/working/REQ-NNN-*.md` exists and its `**Status:**` is `stopped`. If not in `working/`, report "REQ-NNN is not in working/ — nothing to resume." If status is not `stopped`, report the actual status and stop.
4. Read [agents/resume.md](agents/resume.md) in full.
5. Follow the resume agent instructions exactly. Resume is a one-shot — do not loop back to the backlog after dispatch.

---

### log

Generate build-in-public draft posts for configured social media platforms.

1. Detect `{project}`.
2. Read [agents/log.md](agents/log.md) in full.
3. Follow the log agent instructions exactly.

---

### retro

Mine the run ledger and feedback fingerprints; produce a human report; regenerate `.do-work/state/calibration.md` as advisory capture guidance.

1. Detect `{project}`.
2. Confirm `{project}/.do-work/` exists. If not, report "do-work not installed." and stop.
3. Read [agents/retro.md](agents/retro.md) in full.
4. Follow the retro agent instructions exactly. Pass the resolved `{project}/.do-work/` path as the project do-work path.
