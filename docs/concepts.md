# Concepts

Minimal mental model for do-work: what a brief becomes, how work is gated, and what “done” means.

## Why it matters

do-work turns a natural-language brief into small, traceable tasks and runs them with tests and evidence—not one opaque “agent did stuff” blob. Knowing the nouns (Issue, REQ) and the two-command loop (`start` → `go`) keeps you in control of the gates.

## How it works (minimal model)

```text
Your brief
    │
    ▼
  UR-NNN          Issue (verbatim input + side artifacts; slug still UR-NNN)
    │
    ▼
  REQ-NNN-…       backlog tasks (one file each)
    │
    ▼
  working/        claimed, in flight (one worker / worktree per REQ)
    │
    ▼
  archive/        done, with proof metadata
```

**Two-command surface**

| Command | Role |
|---------|------|
| `/do-work start …` | Define work: intake → ideate (default) → capture |
| `/do-work go UR-NNN` | Execute work: verify → audit → run (then optional close/log) |

Granular commands (`intake`, `capture`, `verify`, `run`, …) are the same building blocks; `start` and `go` chain them with defaults and human gates.

**File-based state.** Everything lives under the project’s `.do-work/` (config, Issues, backlog REQs, `working/`, `archive/`, `runs/`, `state/`). There is no separate do-work server. `git` history is the audit trail.

## Key terms

### Issue (slug `UR-NNN`)

Product noun for the top-level brief container (formerly “user request”). Wire/slug stay `UR-NNN` / `ur.*` (do-work-io); do **not** invent `ISSUE-NNN` or `issue.create`.

- Folder (markdown backend): `.do-work/user-requests/UR-NNN/`
- Core file: `input.md` — your brief **verbatim** (do-work does not “improve” the wording on intake)
- May also hold `ideate.md`, `assets/`, later `closure.md`
- Numbering: sequential, zero-padded (`UR-001`, `UR-002`, …); next id is max+1 (gaps are not filled)
- **Linear note:** a do-work Issue is a **Project Milestone**; a **REQ** is a Linear Issue — different entities

### REQ (requirement / task)

- Backlog file: `.do-work/REQ-NNN-slug.md`
- One discrete unit of work with acceptance criteria, verification steps, optional dependencies, layer, and file footprint
- Lifecycle locations: backlog root → `working/` (claimed) → `archive/` (done)
- Each completed REQ normally produces **one git commit** on a `req/REQ-NNN` branch, then delivery per `delivery.mode` (`merge` default, or `pr`)

### Start vs go

- **start** = record + shape the backlog (does not run implementation)
- **go** = score the backlog against the brief, then run if the gate passes

That split is intentional: you get a human decision point before autonomous execution.

### Ideate gate

On `start` (unless `--no-ideate`), ideate ends with:

- **Grill** — one-at-a-time questions (`question`)
- **Continue** — capture as-is
- **Stop** — you revise `input.md` yourself; capture does not run

### Verify gate (confidence)

`go` runs verify first. Score is 0–100% coverage of the brief, plus structural checks:

1. Layer coverage (declared layers represented or explicitly skipped)
2. Integration block on new-surface feature REQs
3. Partial-confidence acknowledgements from capture

Default threshold: **`verify.threshold: 90`** in `.do-work/config.yml`.

| Outcome | Behaviour |
|---------|-----------|
| Score ≥ threshold | Proceed to audit + run |
| Score < threshold | Halt; show gaps (unless `--force` or successful `--auto-fix`) |

### Layers

Project-declared slices of the stack in config, for example:

```yaml
layers: [frontend, backend]
```

Capture tags each REQ with a layer (or `none` for bug-fix / pure refactor). Feature briefs that ignore a declared layer get a prompt—or halt if layers are empty and you did not pass `--no-layers`. See README “Layers and Integration”.

### Integration block

For feature REQs that add **new surface** (page, route, command, endpoint, …), capture writes `## Integration` with codebase-checked answers:

- Reachability
- Data dependencies
- Service dependencies

Stops “compiles but unreachable” work from looking done at decomposition time.

### TDD loop (per REQ)

During run, a fresh worker typically:

1. Works in a dedicated git worktree on `req/REQ-NNN`
2. Writes a failing test for an acceptance criterion
3. Implements until it passes; repeats for remaining criteria
4. Runs the project suite when configured
5. Returns structured evidence to the orchestrator

### Evidence and review gates

A worker report alone does **not** mean archived. The orchestrator validates acceptance evidence, runs policy checks (blocked paths/commands), runs post-build review, writes closure proof fields, and only then archives. Failed review is a **stopper**, not a successful REQ.

### Delivery modes

From `.do-work/config.yml` (`delivery.mode`):

- **`merge`** (default) — merge `req/REQ-NNN` into the base branch locally, archive, tear down worktree, delete branch
- **`pr`** — push and open a GitHub PR via `gh`; requires remote + `gh`. Missing credentials → `missing-creds` stopper (no silent merge fallback)

### Parallelism (short)

- Multi-terminal: several `/do-work run` sessions claim different REQs via atomic `git mv`
- Single-session: `/do-work run --parallel N` (N capped at 10)

Claim stamps, heartbeats, footprint checks, and dependency checks reduce collisions. Recovery: `status`, `unblock`, `resume`.

### Build-in-public log

Optional drafts for X / LinkedIn / blog from completed archive work. Runs after a clean `go` when `log.enabled` is true and `log.platforms` is non-empty—or on demand via `/do-work log`.

## What to do next

1. [Getting started](getting-started.md) — install and first `start` / `go`
2. [Commands](commands.md) — when to use each command
3. [Troubleshooting](troubleshooting.md) — gate failures and stuck REQs
