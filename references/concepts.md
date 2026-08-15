# Concepts reference

On-demand detail for naming, milestones, parallel execution, layers, path-units, decisions, REQ schema, commits, and checkpointed verification. Read from `SKILL.md` when needed; do not load unless the active subcommand requires it.

## File Naming

- Issues (product noun): agent slug `UR-001`, `UR-002`, ... (zero-padded to 3 digits). Wire/param remain `ur` / `ur.*` on do-work-io — not `ISSUE-NNN` / `issue.*`.
- Feature requests: `REQ-001-short-slug.md`, `REQ-002-short-slug.md`, ...
- Slugs are lowercase kebab-case, max 5 words

## Milestone Mode

When an Issue (`UR-NNN`) contains both:

1. The marker `source: /saas-thesis handoff` (in frontmatter or body)
2. A `### Milestones` heading with `#### M1` (or higher) subheadings

`/do-work` enters **milestone mode**. The differences from normal flow:

- Capture decomposes ONE milestone at a time, not the whole Issue.
- REQ files are prefixed: `REQ-M1-001-<slug>.md`, `REQ-M2-001-<slug>.md`.
- Run loop halts at the end of each milestone's REQs and prompts for the deploy gate.
- Deploy-gate sign-off is non-delegable human confirmation.
- State files in `{project}/.do-work/state/`:
  - `active-milestone.md` — single line, current milestone identifier (e.g. `M1`).
  - `milestones.md` — checklist of all milestones with status: `pending` / `captured` / `running` / `deployed`.

Milestone mode is **implicit** — triggered by Issue shape, not a flag. Issues that do not match the trigger continue to behave as before. The `/saas-thesis` skill produces Issue briefs with the correct shape for handoff.

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
**Session:** 9f3c1a20-1b2c-4d5e-8f90-a1b2c3d4e5f6
<!-- claimed-end -->
```

**`**Session:**`** is an **optional** claim-block field (last line before `<!-- claimed-end -->`) correlating the REQ with the live do-work session, so the extension can re-adopt a session after a restart (see the event-stream telemetry, `lib/session-hook.sh`). `lib/claim-req.sh` resolves it via `lib/resolve-session.sh`: the `session.start` whose `data.marker` matches `$DO_WORK_UI_MARKER`, else the single un-ended session for the project. When no session can be determined without guessing — no marker match with multiple live sessions, or no `events.jsonl` at all (older projects) — the line is **omitted entirely**, and its absence is valid everywhere. Heartbeat refreshes leave it untouched; `unblock` strips it with the rest of the stamp; a `resume` that re-resolves a session updates it.

**Checkpoint-based liveness.** Each worker stamps the `**Heartbeat:**` timestamp in its REQ file via `lib/heartbeat.sh` at natural progress checkpoints — after reading the REQ, after each TDD cycle, after each verification step, and before commit — rather than from a background timer (a backgrounded loop cannot survive a fresh-shell-per-call harness). `lib/scan-stale.sh` (called during pre-flight and by `/do-work status`) flags REQs whose heartbeat is older than `parallel.stale_threshold_seconds` (default 900 s / 15 minutes — sized to span the gap between checkpoints) as potentially dead. Stale REQs surface in the status report for human triage — they are not automatically unblocked.

**Deadlock detection.** `lib/deadlock-check.sh` checks for circular wait chains across the `working/` set: does REQ-A depend on REQ-B which depends on REQ-A (both in-flight)? Any cycle found is reported immediately by `/do-work status` under a `DEADLOCK DETECTED` banner. Recovery is manual: use `/do-work unblock REQ-NNN` to break the cycle.

**Visible differences from single-agent mode:**

- The per-REQ announce line is prefixed with `[<agent-id>]` (where `agent-id` is `hostname.pid`) so you can attribute output across terminals.
- Multiple REQs appear in `working/` simultaneously, each carrying the ownership stamp above.
- The final cross-REQ test suite runs once, from whichever orchestrator drains last (gated by `.do-work/state/final-suite-running.md` lockfile).
- On a commit or merge conflict, the losing worker waits up to ~110 seconds (5 retries: 5s / 15s / 30s / 60s backoff) before exiting with `status: stopped`, `reason: concurrent-conflict`. Use `/do-work resume REQ-NNN` to re-dispatch.

### Isolation per REQ

Workers always run in isolated git worktrees at `{project}/.worktrees/req-NNN` on a `req/REQ-NNN` branch. The orchestrator merges the branch back into the base branch and tears down the worktree after integration. See [agents/run-worker.md](../agents/run-worker.md) `## Isolation Mode` and `## Worktree Workflow` for the canonical procedure.

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

`.do-work/decisions.md` is an append-only, cross-Issue record of standing decisions (ADR-lite). It gives capture, ideate, and workers a shared institutional memory so a call made in one UR ("validation lives server-side") is not re-litigated or contradicted in the next.

**Format** — one line per decision, no paragraphs (this is a memory, not documentation; anything needing prose belongs in a design doc):

```
YYYY-MM-DD | Issue/REQ ref | decision | rationale
```

- `YYYY-MM-DD` — the date the decision was recorded.
- `Issue/REQ ref` — the Issue or REQ the decision was made under (e.g. `UR-035` or `REQ-224`).
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
| `**Depends on:**` | optional | REQ ids this REQ must not start before, separated by commas and/or whitespace (e.g. `REQ-144, REQ-145` or `REQ-144 REQ-145`) — tokenized by `lib/pick-req.sh` / `lib/check-deps.sh` and checked against `archive/` |

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
**Session:** 9f3c1a20-1b2c-4d5e-8f90-a1b2c3d4e5f6
<!-- claimed-end -->
```

The heartbeat timestamp is refreshed in-place by `lib/heartbeat.sh` — this is a filesystem-only operation, never a git commit. The optional `**Session:**` line (see the **Atomic claim** description above) correlates the REQ with the live session and is omitted when no session can be resolved. Canonical documentation: `.do-work/archive/REQ-144-extend-req-template-schema.md`.

## Commit Convention

**Markdown backend** (`tracker.backend` unset / `markdown`):

```
feat(REQ-NNN): short title

REQ: .do-work/archive/REQ-NNN-slug.md
UR: .do-work/user-requests/UR-NNN/input.md
Output: path/to/primary/output
```

**Linear backend** (`tracker.backend: linear`) — Linear issue id only (design §6.5):

```
feat(ENG-123): short title

Issue: ENG-123
UR: UR-007
Output: path/to/primary/output
```

Commits are created per-REQ (or per Linear issue) on completion. Under markdown, the claim/heartbeat update path (`lib/heartbeat.sh`) is filesystem-only — it writes directly to the REQ file and does **not** produce a git commit. Under Linear, heartbeat is a claim-protocol comment refresh (see Tracker backends). Unblock operations use `chore(REQ-NNN): unblock — return to backlog` (markdown) or the Linear-id equivalent when `backend: linear`.

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

