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
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR brief into REQ files in the backlog. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections in a brief. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage against brief (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run [UR-NNN]` | Executes backlog: TDD loop, evidence validation, post-build review gate, archive/ledger. Optional UR-NNN scopes the run to that UR's REQs only. |
| `/do-work review` | Internal post-build gate used by run after worker evidence validation and before archive completion. |
| `/do-work status [UR-NNN]` | Renders live situation room: REQs, claimers, heartbeats, deadlock warnings, and coverage rollup. Optional UR-NNN scopes the report. |
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
- [agents/question.md](agents/question.md) — Interactive brief questioning
- [agents/audit.md](agents/audit.md) — Autonomous REQ quality audit
- [agents/ideate.md](agents/ideate.md) — Surfaces assumptions, risks, and connections
- [agents/capture.md](agents/capture.md) — Decomposes brief into REQ files
- [agents/verify.md](agents/verify.md) — Scores REQ coverage against brief
- [agents/run.md](agents/run.md) — Orchestrator: dispatches a worker subagent per REQ
- [agents/run-worker.md](agents/run-worker.md) — Worker: TDD-and-commits a single REQ in a fresh subagent session
- [agents/review.md](agents/review.md) — Post-build gate: reviews scope, acceptance evidence, tests, secrets, docs, and regression risk before archive
- [agents/status.md](agents/status.md) — Read-only situation room: REQs, claimers, heartbeats, deadlock warnings, coverage rollup
- [agents/unblock.md](agents/unblock.md) — Force a stuck in-flight REQ back to the backlog
- [agents/resume.md](agents/resume.md) — Re-dispatch a fresh worker for a stopped REQ
- [agents/log.md](agents/log.md) — Generates build-in-public draft posts
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

### Migration check

Immediately after resolving `{project}` and before executing any subcommand-specific instructions, check whether this project's data folder needs migrating from the legacy `do-work/` location to `.do-work/`. Apply these four detection branches:

| State at `{project}` | Action |
|---|---|
| `.do-work/` exists AND `do-work/` does not exist | Already migrated. Continue silently. |
| `do-work/` exists AND `.do-work/` does not exist | Migrate (see below), then continue. |
| Both `do-work/` and `.do-work/` exist | **Halt.** Output the conflict message below and stop the subcommand. |
| Neither exists | No migration needed. Continue (the `install` flow handles fresh projects). |

**Migration procedure** (legacy `do-work/` → `.do-work/`):

```bash
# Prefer `git mv` so history follows the rename. Fall back to plain `mv` if the path is
# gitignored or this is not a git repo (both make `git mv` fail).
git mv {project}/do-work {project}/.do-work 2>/dev/null \
  || mv {project}/do-work {project}/.do-work
```

Then rewrite `.gitignore` if it contains a line matching `^do-work/?$`:

```bash
if [ -f {project}/.gitignore ] && grep -Eq '^do-work/?$' {project}/.gitignore; then
  sed -i.bak -E 's|^do-work/?$|.do-work/|' {project}/.gitignore && rm {project}/.gitignore.bak
fi
```

After the directory rename and `.gitignore` rewrite succeed, scan the consumer project for hardcoded `do-work/` references and print a warning if any are found.

**Consumer-ref scan targets:**

- All `*.md` files in `{project}` (recursive), excluding: `.git/`, `node_modules/`, `vendor/`, `.worktrees/`, `dist/`, `build/`
- `{project}/.gitignore` itself (in case it contains other `do-work/` patterns beyond the one already rewritten)

**Pattern:** regex `(^|[^.])do-work/` — matches the literal legacy form; the leading `[^.]` guard excludes post-migration `.do-work/` references so only genuine stale references surface.

If matches are found, print:

```
Migration warning: consumer files still reference the legacy do-work/ path.
Review and update these manually — migration does NOT auto-rewrite consumer docs:

  CLAUDE.md:14:  Run intake: read systems/do-work/agents/intake.md
  CLAUDE.md:18:  Identify which project the work is for in {project}/do-work/
  README.md:42:  See do-work/ for backlog state
  ...

(Total: N references across M files.)
```

If zero matches, print nothing — silent success.

**Advisory only.** This warning is informational. Never auto-rewrite consumer files — that is a separate explicit user action.

**Failure handling.** If the scan command itself fails (permission denied, regex error on a particular platform, or any other non-zero exit from the underlying grep), skip the warning step silently. Migration already succeeded; the consumer-ref scan is best-effort and must never block the user from completing migration.

**Skill source exclusion.** When this skill is invoked against its own source clone (`~/.claude/skills/do-work/`), that clone intentionally gitignores `.do-work/` and is excluded from this scan — no self-referential warnings will fire.

Output `Migrated do-work/ → .do-work/` and continue with the subcommand.

**Both-exist conflict.** When both `{project}/do-work/` and `{project}/.do-work/` are present, do not migrate. Halt the subcommand with this exact text and exit:

```
Migration conflict: both do-work/ and .do-work/ exist at {project}. Resolve manually before re-running.
```

**No mid-flight protection.** This check does not inspect `working/` for in-flight REQs before migrating. Migration is rare in practice; the assumption is that the user runs it on an idle project. A migration that runs while a parallel `/do-work run` is mid-REQ will cause that worker to fail on the next file-system access — accept that risk rather than introducing a coordination layer for a once-per-project event.

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

`/do-work run [UR-NNN]` is safe to launch from multiple terminals simultaneously. Up to 10 orchestrators can run in parallel — each claims a different REQ from the backlog. Coordination is handled by a dedicated library layer; no flag, no daemon, no in-memory state is required.

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

**Heartbeat-based liveness.** Each worker refreshes the `**Heartbeat:**` timestamp in its REQ file while active via `lib/heartbeat.sh`. `lib/scan-stale.sh` (called during pre-flight and by `/do-work status`) flags REQs whose heartbeat is older than `parallel.stale_threshold_seconds` (default 300 s / 5 minutes) as potentially dead. Stale REQs surface in the status report for human triage — they are not automatically unblocked.

**Deadlock detection.** `lib/deadlock-check.sh` checks for circular wait chains across the `working/` set: does REQ-A depend on REQ-B which depends on REQ-A (both in-flight)? Any cycle found is reported immediately by `/do-work status` under a `DEADLOCK DETECTED` banner. Recovery is manual: use `/do-work unblock REQ-NNN` to break the cycle.

**Visible differences from single-agent mode:**

- The per-REQ announce line is prefixed with `[<agent-id>]` (where `agent-id` is `hostname.pid`) so you can attribute output across terminals.
- Multiple REQs appear in `working/` simultaneously, each carrying the ownership stamp above.
- The final cross-REQ test suite runs once, from whichever orchestrator drains last (gated by `.do-work/state/final-suite-running.md` lockfile).
- On a commit or merge conflict, the losing worker waits up to ~110 seconds (5 retries: 5s / 15s / 30s / 60s backoff) before exiting with `status: stopped`, `reason: concurrent-conflict`. Use `/do-work resume REQ-NNN` to re-dispatch.

### Isolation per REQ

The worker chooses `same-branch` (default) or `worktree` at dispatch time based on REQ scope. Worktree mode triggers when the REQ task mentions `migration`, `schema change`, `rename across`, `refactor across`, `extract module`, or `restructure`; when the Integration block lists ≥ 3 distinct service dependencies; or when the REQ has > 6 acceptance criteria. Worktree REQs work in `{project}/.worktrees/req-NNN` on a `req/REQ-NNN` branch and merge back into the base branch on completion.

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
| `**Criteria approved:**` | optional | Acceptance-criteria provenance: `agent-drafted` when capture generated it, or `human <approver> <YYYY-MM-DD>` when a human previously reviewed it. This field does not block run. |
| `**Files:**` | yes | Space-separated list of primary output files — used by `lib/check-footprint.sh` for overlap detection |
| `**Depends on:**` | optional | Space-separated REQ ids this REQ must not start before (e.g. `REQ-144 REQ-145`) — checked by `lib/check-deps.sh` |

A **path-unit** is a REQ whose `**Entry point:**` and `**Terminal state:**` are both non-empty. Path-units describe a vertical, reachable slice of intent. Child layer-tasks point back to a path-unit with `**Parent:**`; legacy REQs without these fields remain valid because the migration is additive.

`**Status:**` remains writable and authoritative for coordination (`backlog`, `working/`, dependency gating, stale checks, and archive flow). `**Closure proof:**` is a separate evidence signal used to derive whether a done REQ is proven; it does not replace the coordination status field.

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
3. Create `{project}/.do-work/config.yml` if it does not already exist, using the default template below:

```yaml
# do-work configuration
# Edit this file to customize agent behavior.
# Full key reference: agents/config.md

project:
  name: ""

layers: []                 # declare project layers, e.g. [frontend, backend]

log:
  enabled: true
  platforms: []            # e.g. [x, linkedin]
  drafts_per_platform: 2

feedback:
  enabled: false           # set true to file GitHub issues on anomalies
  repo: ""                 # target repo for feedback issues, e.g. myorg/myrepo
  label: auto:do-work-feedback
  project_repo: ""         # if different from repo

parallel:
  stale_threshold_seconds: 300   # heartbeat age (seconds) before a slot is flagged stale

review:
  required: true

acceptance:
  evidence_required: true

risk:
  require_review:
    - migrations
    - auth
    - billing
    - payments
    - files_changed_over: 8
    - acceptance_criteria_over: 6

security:
  blocked_paths:
    - .env
    - .env.*
  blocked_commands:
    - rm -rf
    - production

model:
  default: sonnet
  escalation: opus

cost:
  budget: ""

ledger:
  enabled: true
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
```

If already installed, report "Already installed." and stop.

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

### run [UR-NNN]

Execute the backlog autonomously — one REQ at a time — until empty or a stopper is hit. The optional `UR-NNN` argument scopes execution to that UR's REQs only, ignoring all other backlog entries. The orchestrator dispatches a fresh worker subagent per REQ (see [agents/run-worker.md](agents/run-worker.md)) and reads its structured return report.

1. Detect `{project}`.
2. Determine UR scope:
   - If `UR-NNN` was provided, record it — the run agent will filter the backlog to that UR.
   - If not provided, the full backlog is in scope.
3. Pre-flight checks:
   - If a REQ file exists in `{project}/.do-work/working/`, report it and ask the user: resume or abort?
   - If no `REQ-NNN-*.md` files exist in `{project}/.do-work/` (backlog root) within scope, report "Backlog is empty." and stop.
4. Read [agents/run.md](agents/run.md) in full.
5. Follow the run agent instructions exactly, passing through the UR scope if provided.

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
