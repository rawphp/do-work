# How do-work Works

> **Operators / first run:** use [getting-started.md](getting-started.md) for install and the happy path. This page is the phase-by-phase deep dive (design rationale included).

A walkthrough of the do-work system — every phase, every file it produces, and the design reasoning behind each choice.

---

## What it is

do-work is an agent-harness skill that turns a natural-language brief into a sequence of small, traceable, individually-committed tasks — executed autonomously with TDD. It runs on any agent that loads skills from a shared hub.

It is **file-based by default**: every artifact (brief, decomposed task, claim stamp, commit) is a file in the project's git history. There is no daemon, no in-memory queue, no central coordinator. Optional backends store the same work items in **Linear**, a local **SQLite** DB, or **do-work.io** (remote MCP) only (see [Multi-tracker](#multi-tracker-work-item-backends) below); runtime and git isolation stay local on every backend.

**Why file-based (default):** The alternative is a stateful tool (a queue, a server, an MCP backend). Files give you four things for free that a stateful tool charges for:
1. **Auditability** — `git log` *is* the audit log.
2. **Resumability** — kill the process, the state survives.
3. **Multi-agent coordination** — `git mv` is an atomic primitive across processes; no lock service needed.
4. **Inspectability** — `cat`, `ls`, and `grep` are the debugger.

---

## Multi-tracker (work-item backends)

Work items (Issues, REQs, decisions, verify/close reports, run notes) go through a **tracker port**. Config key `tracker.backend` selects the store:

| `tracker.backend` | Work-item store |
|-------------------|-----------------|
| **unset / empty / `markdown`** | Default: local `.do-work/` + `lib/*.sh` |
| **`linear`** | Linear only (product Project / **Issue milestones** / Issues) — **no dual-write** |
| **`sqlite`** | Local `.do-work/work.db` only via `lib/dw-db.sh` — **no dual-write**; greenfield empty DB on switch |
| **`do-work-io`** | do-work.io only (remote MCP; slugs `UR-NNN` / `REQ-NNN`; identity `status_map`) — **no dual-write**; web UI is the board |

**Load path** (every phase agent that touches work items):

1. Load config (`agents/config.md`)
2. Resolve `tracker.backend` (missing/empty → `markdown`)
3. Read `agents/tracker/port.md` (shared op catalog + rules)
4. Read `agents/tracker/<backend>.md` (`markdown.md`, `linear.md`, `sqlite.md`, or `do-work-io.md`)
5. Call **only** named port ops for storage — never raw `.do-work/REQ-*` paths, raw Linear tools, freehand `sqlite3`, or invented HTTP outside the backend doc / `dw-db.sh`

**What stays local on every backend:** worktrees, feature branches, merges, `state/*` locks, events, `config.yml`, optional local run ledger telemetry.

### No dual-write and hard-stop

- With `backend: linear`, `backend: sqlite`, or `backend: do-work-io`, that store is the sole work-item source of truth. Agents do not keep a parallel markdown Issue/REQ store.
- If Linear is unusable (MCP missing/unauthenticated, team unresolved, missing `status_map` state) **or** `agents/tracker/linear.md` is missing, agents **hard-stop** with setup instructions. They never silently fall back to markdown.
- If sqlite is unusable (`sqlite3` missing, corrupt DB / bad `user_version`, missing `agents/tracker/sqlite.md`), agents **hard-stop** the same way — **never** fall back to markdown or Linear.
- If do-work.io is unusable (`do-work-io.md` missing, empty/invalid `base_url`, missing PAT in `token_env`, empty project slug, or MCP tools undiscoverable), agents **hard-stop** — **never** fall back to markdown, Linear, or sqlite.
- Mid-flight MCP failure after a Linear or do-work.io claim leaves the item **claimed**; recover with `/do-work resume` or `/do-work unblock` after MCP recovers — not by inventing local REQ files. Under sqlite, active claims live in `work.db`; same resume/unblock recovery.

### SQLite hierarchy (when `backend: sqlite`)

```
.do-work/work.db   (sole work-item store; gitignored)
├── urs            (Issue briefs / status / artifacts)
├── reqs           (REQ rows + parent UR + status)
├── claims         (active claim / heartbeat rows)
└── …              (decisions, milestones, artifacts — see schema)

.do-work/board/index.html   (static HTML snapshot; regenerated only by `/do-work board`)
```

- **Greenfield switch:** setting `tracker.backend: sqlite` does **not** import markdown or Linear history. First `dw-db ensure` creates an empty schema (`user_version=1`, WAL).
- **Board:** `/do-work board` is **sqlite-only** — regenerates `tracker.sqlite.board_path` (default `.do-work/board/index.html`) when invoked; not a live server.
- **Commit / branch:** same as markdown (`feat(REQ-NNN): …`, worktree `req/REQ-NNN`) — ids stay `UR-NNN` / `REQ-NNN` in the DB.
- **Config keys:** `tracker.sqlite.path`, `board_path`, `busy_timeout_ms` — defaults in `agents/config.md`.

### do-work.io hierarchy (when `tracker.backend: do-work-io`)

```
do-work.io project (tracker.dowork.project slug)
├── user_requests (UR-NNN)
│   └── requirements (REQ-NNN) ± active_claim
└── artifacts / decisions / run_notes
```

- **Slugs** at the agent surface: `UR-NNN` / `REQ-NNN`. Identity `status_map` (`backlog` / `in_progress` / `stopped` / `done`) is **REQ-only**; Issue closure is `closed_at`.
- **MCP:** `{tracker.dowork.base_url}/mcp/{tracker.dowork.mcp_profile}` (default profile `dowork.control`) with `Authorization: Bearer ${tracker.dowork.token_env}` (default env `DOWORK_IO_PAT`). Mint the PAT in the web UI; **do not paste it into chat**.
- **Board:** `/do-work board` is sqlite-only. The do-work.io web dashboard is the live board.
- **Milestone cursor** (`read_active_milestone` / `set_active_milestone` / `list_milestone_reqs`) is **not served** in v1.1 — treat as not in milestone mode. `write_gate_state` stays local.
- **Commit / branch:** same as markdown/sqlite (`feat(REQ-NNN): …`, worktree `req/REQ-NNN`).
- **Config keys:** `tracker.dowork.base_url`, `tracker.dowork.token_env`, `tracker.dowork.project`, `tracker.dowork.mcp_profile` — defaults in `agents/config.md`.

### Linear hierarchy (when `backend: linear`)

```
Team (config team_id / team_key)
└── Product Project (tracker.linear.product_project — one shared Project per local product)
    ├── Project Milestone (Issue brief / ideate / verify / close)
    │   └── Issue (REQ / path-unit) ± sub-issues (layer children)
    └── Project Milestone (next UR)
        └── Issue …
```

**`product_project` resolve (default empty):** explicit `tracker.linear.product_project` (name|UUID) if set; else `project.name`; else git-root directory basename. Then `ensure_product_container` create-if-missing and **always persists** the Project UUID back to config. Empty config never falls through to the skill name `do-work` — that name is only an example when this skill's own repo is the local product.

**Why milestones, not Initiatives:** official Linear MCP exposes Project Milestone create/list/get, but not Initiative create/list. do-work therefore homes each Issue on a **Project Milestone**.

REQs use **Linear issue ids** only (e.g. `ENG-123`). `UR-NNN` remains the Issue-milestone slug.

### Commit convention (Linear)

```
feat(ENG-123): short title

Issue: ENG-123
UR: UR-007
Output: path/to/primary/output
```

Branch / worktree: `req/ENG-123` (sanitized for git refs). Markdown mode still uses `feat(REQ-NNN): …` and `req/REQ-NNN`.

### Claim protocol warning (human operators)

Under Linear, the **human** remains Issue **assignee**; agents claim with a workflow state change plus a claim-protocol comment (`<!-- do-work-claim -->` by default) carrying `agent_id`, heartbeats, and `status: active`.

**Do not clear, edit, or delete agent claim comments in the Linear UI while a run is live.** That breaks claim/heartbeat arbitration. Use `/do-work status`, then `resume` / `unblock` when the agent has stopped.

### Migration (markdown → Linear)

One-shot, **idle-only** cutover: working set empty, no active claims, operator confirms (or dry-run).

```text
/do-work upgrade migrate
```

Surfaced under `/do-work upgrade` (and conformance — not a separate forever command). After cutover: `tracker.backend: linear`; historical markdown trees stay as read-only history; **no dual-write**. Details: `agents/tracker/linear.md` + `agents/upgrade.md` Step 9.

**Refuse under sqlite:** if `tracker.backend` is already `sqlite`, migrate **stops** with `migrate-linear: refused-sqlite-backend` — markdown→Linear does not apply, and there is no sqlite history import or sqlite→Linear path.

**Refuse under do-work-io:** if `tracker.backend` is already `do-work-io`, migrate **refuses**. Leave `tracker.backend` and remote work items unchanged.

**Operator setup:** Linear (MCP + `team_id`) — [troubleshooting.md § Linear tracker backend](troubleshooting.md#linear-tracker-backend). SQLite (`sqlite3` + greenfield switch + board) — [troubleshooting.md § SQLite tracker backend](troubleshooting.md#sqlite-tracker-backend). do-work.io (PAT env + `base_url` + project slug) — [troubleshooting.md § do-work.io tracker backend](troubleshooting.md#do-workio-tracker-backend). Config schema: `agents/config.md`. Skill summary: `SKILL.md` § Tracker backends.

---

## The two-command surface

Most users only ever type two commands:

```
/do-work start <brief>     # define the work
/do-work go UR-NNN         # execute it
```

The granular commands (`intake`, `capture`, `verify`, `run`, etc.) are the building blocks underneath. `start` and `go` are orchestrators that chain them together with sensible defaults and interactive gates.

**Why two commands instead of one:** A single `/do-work do-everything` would erase the human gate between "I described the work" and "the machine is about to execute the work." That gate matters — `verify` runs in `go`, and if confidence is below 90% the run halts. Splitting `start` from `go` makes the gate a deliberate user action rather than an automatic side effect.

---

## The lifecycle

### Phase 0 — Install

Triggered by `/do-work install`, or automatically on first `/do-work start`.

Creates per-project state under `{project}/.do-work/`:

```
.do-work/
├── config.yml          # project configuration
├── user-requests/      # one folder per Issue
├── working/            # REQs currently claimed by a worker
├── archive/            # completed REQs
├── logs/               # build-in-public log drafts
└── state/              # coordination state (gate-owner, lockfiles, milestone tracking)
```

**Why `.do-work/` (hidden) instead of `do-work/`:** The folder is operational state, not source. Hiding it keeps `ls` output clean and signals "tooling artifact, not your code." There is a migration path for projects that started on the legacy `do-work/` location (see SKILL.md § Migration check).

**Why per-project, not per-user:** Each project has its own backlog, layers, and config. State that lives in `~/.claude/` would force projects to share a queue — wrong default.

---

### Phase 1 — Intake

Triggered by `/do-work intake` (or implicitly by `/do-work start`).

The brief is written **verbatim** as `user-requests/UR-NNN/input.md`. No interpretation, no normalisation, no decomposition. UR numbers are sequential and zero-padded (`UR-001`, `UR-002`, ...).

**Why verbatim:** The brief is the source of truth that `verify` later scores against. If `intake` "improves" the brief, downstream coverage scoring measures the rewrite, not the user's intent. Faithfully recording the original input is non-negotiable.

**Why a folder per Issue (not a single file):** The UR accretes artifacts as it moves through the pipeline — `input.md`, `ideate.md`, optional `assets/`, frontmatter that tracks `layers_in_scope` etc. A folder keeps related artifacts colocated.

---

### Phase 2 — Ideate (default-on, gated)

Triggered automatically by `/do-work start` unless `--no-ideate` is passed.

Surfaces assumptions, risks, missing context, and adjacent concerns in the brief. The output is written to `user-requests/UR-NNN/ideate.md`.

Ends at an **interactive gate** with three options:
- **Grill** — drop into `/do-work question`, which asks the user one targeted question at a time
- **Continue** — proceed to capture as-is
- **Stop** — pause so the user can edit `input.md` themselves before re-running

**Why default-on:** Most briefs under-specify. Without a creative review step, capture turns vague briefs into vague REQs, and the cost surfaces at run time when a worker is halfway through implementing the wrong thing. Cheaper to interrogate the brief than to roll back a half-built feature.

**Why an interactive gate (not auto-grill or auto-continue):** Auto-grill is annoying when the brief is already crisp. Auto-continue silently absorbs gaps. A gate lets the user decide based on what ideate actually surfaced.

---

### Phase 3 — Capture

Triggered by `/do-work capture` (or implicitly by `/do-work start`).

Decomposes the brief into discrete REQ files in the backlog (`{project}/.do-work/REQ-NNN-slug.md`).

Each REQ carries a structured header:

| Field | Purpose |
|---|---|
| `**UR:**` | Parent UR identifier — traces every REQ back to its brief |
| `**Status:**` | `backlog` / `in-progress` / `stopped` / `done` |
| `**Created:**` | ISO date |
| `**Layer:**` | One of the project's declared layers, or `none` |
| `**Files:**` | Primary output files — used by the footprint checker for overlap detection |
| `**Depends on:**` | Optional list of REQs that must finish first |

#### Layers

Each project declares its layers once in `config.yml`:

```yaml
layers: [frontend, backend]
```

For `feature`-class briefs, capture enforces that every declared layer is covered (or that an explicit "no" decision is recorded for skipped layers). Bug-fix / pure-refactor / test-only REQs use `Layer: none`.

**Why layers:** Without this check, capture systematically under-covers full-stack briefs. A "user settings page" brief frequently produces backend REQs and forgets the form, or produces a form REQ and forgets validation. Forcing a per-layer accounting catches the gap at capture time, not at run time.

#### Integration block

Every feature REQ that adds *new surface* (anything callable or visible from outside its own code) carries an `## Integration` section answering three questions, with concrete file references:

- **Reachability** — how does the user/caller reach this?
- **Data dependencies** — what existing data does it read or write?
- **Service dependencies** — what existing services or modules does it extend?

Capture inspects the codebase to draft the answers, **verifies cited files actually exist** before claiming high confidence, and asks the user when it can't tell.

**Why Integration:** REQs frequently ship code that compiles but is unreachable — a new page with no route, a new endpoint with no client call. The Integration block forces capture to think about wiring at decomposition time, not patch it up after.

#### Dependency graph

If REQs declare `Depends on:` chains, capture passes the graph through `lib/cycle-check.sh`. Cycles are rejected at capture time so the run loop never has to deal with deadlocks rooted in bad decomposition.

---

### Phase 4 — Audit (always-on)

Triggered by `/do-work audit` (or implicitly by `/do-work go`).

Interrogates every REQ's acceptance criteria. Auto-fixes vague spots (e.g. "handle errors gracefully" → concrete error cases and expected behaviour), and reports the diff to the user.

**Why always-on inside `go`:** REQs that look reasonable at capture time often turn out to have soft acceptance criteria that lead to ambiguous "is this done?" judgments at run time. Auditing once before execution catches the soft spots when fixes are cheap.

---

### Phase 5 — Verify

Triggered by `/do-work verify` (or implicitly by `/do-work go`).

Scores REQ coverage against the original brief — produces a 0–100% confidence number plus a structured list of gaps.

Three structural checks beyond raw coverage:
1. **Layer coverage** — every declared layer represented (or explicitly skipped)
2. **Integration block present** — on every new-surface feature REQ
3. **Partial-confidence acknowledgement** — capture flagged any low-confidence answers

`--auto-fix` lets verify create missing REQs in-place before scoring.

`/do-work go` uses the score as a gate: **≥90% → auto-run, <90% → halt** and surface the gaps. `--force` bypasses the gate; `--auto-fix` patches first then re-checks.

**Why the 90% threshold:** Below 90% empirically correlates with rework. Above 90% the marginal cost of one more REQ pass exceeds the cost of catching the gap during run. The number is tunable per project via config in future iterations; today it is the global default.

---

### Phase 6 — Run

Triggered by `/do-work run` (or implicitly by `/do-work go` when verify passes).

Executes the backlog autonomously, one REQ at a time, until empty or a stopper is hit.

#### Integration base (pre-flight)

Before any claim, worker dispatch, or worktree provision, go and run call `lib/ensure-integration-base.sh` so workers never integrate into a protected default branch (`main`, `master`, or the remote HEAD short name when resolvable):

| Orchestrator checkout | Behaviour |
|-----------------------|-----------|
| Already off a protected default | Keep that branch; it is the integration base |
| On protected default (scoped or unscoped) | Create-or-checkout fixed branch `new-work`; if it already exists, checkout and **merge** the protected tip just left into `new-work` |
| On protected default + **dirty** tree | Allowed — uncommitted changes **carry** onto `new-work` (no dirt-only hard-stop) |
| Detached HEAD | **Hard-stop** |

`/do-work start` does **not** call this helper and does not switch branches — only go/run enforce the guard.

The same `new-work` name is shared with `delivery.pr.granularity: ur` (one PR per Issue). Merge mode reuses that branch for accumulation; using `new-work` does **not** require `delivery.mode: pr`.

**Why leave the default:** Landing REQ merges on `main`/`master` while agents run makes it easy to ship half-finished work or fight over the shared default. An integration base keeps the default clean until the operator promotes deliberately.

#### The TDD loop (per REQ)

The orchestrator claims the REQ (atomic `git mv` from backlog root into `working/`, plus a claim stamp written to the file via `lib/claim-req.sh`), then dispatches a **fresh worker subagent** for each REQ (see `agents/run-worker.md`). The worker:

1. Creates a git worktree at `{project}/.worktrees/req-NNN` on a `req/REQ-NNN` branch (from the post-ensure integration base)
2. Writes a failing test for the first acceptance criterion
3. Implements until the test passes
4. Repeats for remaining criteria
5. Runs the project's full test suite
6. Commits with `feat(REQ-NNN): short title` and a body pointing back to the REQ, UR, and primary output
7. Returns a structured YAML report to the orchestrator

The orchestrator then validates the report, merges the worktree branch into the **integration base** (not `main`/`master`), moves the REQ from `working/` to `archive/` with `Status: done`, tears down the worktree, and records the ledger entry.

**Why a fresh subagent per REQ:** Context isolation. A worker that just finished implementing REQ-007 carries 30k tokens of context that are irrelevant — and often actively misleading — for REQ-008. Spawning a fresh subagent enforces a clean room per REQ. The orchestrator (the parent) only sees structured return reports, not the worker's internal monologue, so the parent's context stays small even across hundreds of REQs.

**Why TDD inside the worker:** A failing test is the cheapest specification format. It compiles or it doesn't; it passes or it doesn't. Acceptance criteria written as code remove the "is this what you meant?" ambiguity that natural-language criteria leave open.

**Why one commit per REQ:** Each commit is independently revertible. If REQ-012 turns out to be wrong, `git revert <sha>` removes exactly that work without disturbing REQ-011 or REQ-013. Squashing into one big merge commit kills this property.

#### Isolation mode

Every REQ runs in a dedicated git worktree at `{project}/.worktrees/req-NNN` on a `req/REQ-NNN` branch forked from the integration base (`new-work` after leave-default, or the non-protected branch already checked out). The orchestrator creates the worktree before dispatch and tears it down after merging the worker's commit into that base. Worktree-always is the canonical mode — same-branch execution is retired.

**Why worktree-always:** Uniform isolation removes a per-REQ judgment call and eliminates the class of conflicts that arises when two workers touch overlapping files on the same branch. The worktree overhead is negligible compared to the TDD loop.

---

### Phase 7 — Log (build-in-public)

Triggered by `/do-work log`, or automatically after a clean `/do-work go`.

Scans `archive/` for REQs completed since the last log entry, generates multiple draft posts per configured platform (X, LinkedIn, blog), and surfaces them for the user to pick one.

Per-platform character ceilings are enforced **mechanically** — a generated draft over `log.max_chars[platform]` is rewritten once, then truncated at the last sentence boundary if still over.

**Why mechanical truncation:** Aspirational length limits ("aim for ~280 chars") drift. Drafts that exceed the platform's hard limit become unpostable. Cutting at the agent layer keeps the user out of the per-draft compliance loop.

---

## Parallel Execution

`/do-work run` is safe to launch from multiple terminals simultaneously. Up to 10 orchestrators can run in parallel — each claims a different REQ from the backlog.

**Why parallel:** Backlogs of 5+ independent REQs sit idle in single-agent mode while one REQ at a time finishes. Parallel execution turns a 10-REQ backlog into a few-minutes wallclock job instead of an hour. No flag, no daemon — open a second terminal and run the same command.

### Three guarantees that keep parallel terminals from stepping on each other

#### 1. Footprint-aware claiming

Before claiming, each orchestrator calls `lib/pick-req.sh`, which uses `lib/check-footprint.sh` to detect file-level overlap between the candidate REQ and every REQ currently in `working/`. Overlap → skip the candidate → try the next backlog entry.

**Why footprint-first:** The primary source of cross-agent conflict isn't claim races — those resolve with `git mv`. It's two workers editing the same file in their respective TDD loops, then colliding at commit time. Skipping overlapping candidates eliminates the root cause instead of patching the symptom.

#### 2. Dependency-aware ordering

`lib/pick-req.sh` also calls `lib/check-deps.sh` to verify that all `Depends on:` REQs have status `done` (i.e. live in `archive/`) before the candidate is eligible. Cycles are caught at capture time by `lib/cycle-check.sh`, so the run loop only deals with acyclic graphs.

#### 3. Atomic claim with ownership stamp

Once a safe, dep-satisfied candidate is picked, `lib/claim-req.sh` writes the ownership stamp:

```markdown
<!-- claimed-start -->
**Claimed by:** hostname.pid
**Claimed at:** 2026-05-21T11:42:08Z
**Heartbeat:** 2026-05-21T11:42:08Z
<!-- claimed-end -->
```

And `git mv`s the REQ from backlog root into `working/`. Two orchestrators racing for the same file resolve via the OS — the loser sees the source gone and falls through to the next candidate.

**Why hostname.pid:** It's unique per orchestrator process and trivially attributable in `status` output across multiple terminals.

### Heartbeat-based liveness

Each worker refreshes the `**Heartbeat:**` timestamp in its REQ file while active via `lib/heartbeat.sh`. `lib/scan-stale.sh` flags REQs whose heartbeat is older than `parallel.stale_threshold_seconds` (default 300s) as potentially dead.

**Why filesystem-only heartbeats, not git commits:** A heartbeat every few seconds would flood `git log` with `chore: heartbeat` commits. Direct file writes don't pollute history.

**Why surface stale slots instead of auto-unblocking:** Auto-unblock would unblock REQs whose worker is *slow*, not dead — and the cost of re-doing work plus a possible conflict cleanup exceeds the cost of waiting for human triage. Stale slots show up in `/do-work status`; the human runs `/do-work unblock REQ-NNN` if confirmed dead.

### Deadlock detection

`lib/deadlock-check.sh` checks for circular wait chains across the `working/` set (REQ-A depends on REQ-B, both in-flight). Cycles surface in `/do-work status` under a `DEADLOCK DETECTED` banner.

### Final test suite

Runs once, from whichever orchestrator drains last — gated by a `final-suite-running.md` lockfile in `.do-work/state/`. Prevents N orchestrators from each running the full suite N times in parallel.

### Concurrent-conflict retry

If a worker's commit collides on shared files, it waits with exponential backoff (5 retries: 5s / 15s / 30s / 60s ≈ 110s total) before exiting with `status: stopped`, `reason: concurrent-conflict`. The user re-dispatches with `/do-work resume REQ-NNN`.

### What stays single-agent (by design)

- **Milestone deploy gates** — the first orchestrator to detect milestone-complete owns the gate via `state/gate-owner.md`; siblings idle and resume when the milestone advances. Gates are non-delegable human sign-offs.
- **Stale-slot prompt** — whichever orchestrator finds a stale slot first owns the prompt.

---

## Recovery commands

| Situation | Command | What it does |
|---|---|---|
| Worker died / stuck / heartbeat stale | `/do-work unblock REQ-NNN` | Strips claim, returns REQ to backlog. Includes a judgment gate on partial commits. |
| REQ stopped (concurrent-conflict / transient error) | `/do-work resume REQ-NNN` | Refreshes heartbeat, re-dispatches a fresh worker. Preserves the claim. |
| Unclear state / "what's going on?" | `/do-work status [UR-NNN]` | Live situation room: in-flight REQs, claimers, heartbeat ages, deadlock banners. Read-only. |

**Why three distinct verbs:** `unblock` (force-return), `resume` (re-dispatch), and `status` (observe) are different intents. Collapsing them would force users to pick between destructive and non-destructive paths via flags — slower and more error-prone than three named commands.

---

## Milestone Mode

When an Issue contains the marker `source: /saas-thesis handoff` plus a `### Milestones` heading with `#### M1` (or higher) subheadings, do-work enters **milestone mode**:

- Capture decomposes one milestone at a time, not the whole Issue
- REQ files are prefixed: `REQ-M1-001-slug.md`, `REQ-M2-001-slug.md`, ...
- Run halts at the end of each milestone's REQs and prompts for a **deploy gate** — non-delegable human confirmation
- State files in `.do-work/state/`:
  - `active-milestone.md` — current milestone identifier
  - `milestones.md` — checklist of all milestones with status

**Why implicit (triggered by Issue shape, not a flag):** The `/saas-thesis` skill produces Issue files with the correct shape automatically. Forcing users to remember `--milestone-mode` on `go` would split a single user intent across two commands. The marker in the Issue carries the intent.

**Why deploy gates are non-delegable:** Deploying a milestone is a real-world action with real-world consequences (payment processor enabled, customer-facing copy live, etc.). The skill never assumes consent for an irreversible external action.

---

## Why the design is what it is — five principles

The patterns above are not arbitrary. They all derive from five operating principles:

### 1. Files over state servers

Every piece of coordination state is a file in the project. Claims are filenames in `working/`. Status is a header field. Heartbeats are timestamps in a file. Dependencies are markdown lists.

This means: `git log` is the audit log, `cat REQ-007-slug.md` is the inspector, kill -9 is recoverable, and the only "database" you have to back up is `.do-work/`.

### 2. The brief is the source of truth

Intake never rewrites the brief. Verify scores REQ coverage *against the original brief*. The user's words remain queryable forever.

### 3. Small commits, one per REQ

Every REQ produces exactly one commit. Reverts are surgical. `git bisect` works. PR review chunks are sized to the unit of decomposition.

### 4. Gates, not autonomy, for irreversible actions

The skill is autonomous *inside* well-bounded loops (one REQ → fresh subagent → TDD → commit) but **always halts at irreversible boundaries**: deploy gates, sub-90% verify scores (without `--force`), the ideate review (Grill / Continue / Stop), partial-commit decisions in `unblock`.

### 5. Heuristics replace per-task questions

Defaults are picked from REQ shape (parallel claim ordering, layer enforcement) and system-level policy (worktree-always isolation). The user can override, but they almost never need to. Removing micro-decisions from the human is the only way the autonomous loop earns its name.

---

## Reference

- [getting-started.md](getting-started.md) — install and first run (optional Linear / SQLite / do-work.io pointers)
- [concepts.md](concepts.md) — user-facing mental model
- [commands.md](commands.md) — command reference
- [troubleshooting.md](troubleshooting.md) — failure symptoms (including Linear MCP / team_id / sqlite3 / work.db / do-work.io PAT)
- `SKILL.md` — full command reference, tracker backends, migration semantics
- `agents/tracker/port.md` — shared work-item op catalog
- `agents/tracker/markdown.md` / `agents/tracker/linear.md` / `agents/tracker/sqlite.md` / `agents/tracker/do-work-io.md` — backend implementations
- `agents/*.md` — per-phase agent instructions
- `lib/*.sh` — coordination primitives (markdown claim/footprint; `lib/dw-db.sh` for sqlite)
- `.do-work/state/` — runtime coordination files (gate-owner, lockfiles, milestone tracking)
- `.do-work/config.yml` — per-project configuration (layers, log, parallel, test, next_steps, `tracker.*`)
- `.do-work/archive/REQ-144-extend-req-template-schema.md` — canonical REQ header schema reference
