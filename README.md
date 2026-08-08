# Do Work

An agent-harness skill that turns natural-language briefs into discrete, traceable tasks and executes them autonomously — with TDD, evidence gates, review, and a git commit per task. Works with any agent that loads skills from a shared hub (Claude Code, Codex, Cursor, and others).

Two commands: `/do-work start` to define the work, `/do-work go` to execute it.

## User documentation

Task-based guides for installing and running `/do-work` (not contributor internals):

| Guide | Contents |
|-------|----------|
| [docs/README.md](docs/README.md) | Docs index |
| [docs/getting-started.md](docs/getting-started.md) | Install → first start → first go |
| [docs/concepts.md](docs/concepts.md) | UR, REQ, gates, evidence |
| [docs/commands.md](docs/commands.md) | Command and flag reference |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failure symptoms |
| [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Phase-by-phase deep dive |

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/tests-219%2F219-brightgreen?style=flat-square" alt="Tests">
</p>

<p align="center">
  <strong>Any agent harness</strong><br>
  <a href=".claude/">
    <img src="https://img.shields.io/badge/Claude_Code-example-orange?style=flat-square&logo=anthropic" alt="Claude Code">
  </a>
  <a href=".codex/">
    <img src="https://img.shields.io/badge/Codex_CLI-example-412991?style=flat-square&logo=openai" alt="Codex CLI">
  </a>
  <img src="https://img.shields.io/badge/any_skills_hub_agent-welcome-brightgreen?style=flat-square" alt="Any skills hub agent">
</p>

---

## Installation

Installs into the shared skills hub (`~/.agents/skills/do-work` by default). All agents wired to that hub share one install. (`--env` is accepted for compatibility and ignored.)

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/agent-native/do-work/main/install.sh | bash
```

Optional live symlink from a checkout (dev):

```bash
curl -fsSL https://raw.githubusercontent.com/agent-native/do-work/main/install.sh | bash -s -- --from-cwd
# or: bash install.sh --source /path/to/do-work
```

### Or clone manually

```bash
git clone https://github.com/agent-native/do-work.git ~/.agents/skills/do-work
```

Override the hub directory with `AGENTS_SKILLS_HUB` (same as `install.sh`). Wire any agent harness to load skills from that hub.

---

## Quick Start

### Step 1 — Start

```
/do-work start I need a user settings page with email and password change
```

This records your brief, runs a creative review (ideate), and decomposes it into REQ files — all in one shot.

Add `--no-ideate` to skip the creative review. Add `--no-layers` to skip layer-coverage checks for this UR (records the choice in UR state for audit).

Ideate now ends with an interactive gate — after surfacing gaps, it asks whether you want to be **grilled** with one-at-a-time questions, **continue** to capture as-is, or **stop** to revise the brief yourself.

### Step 2 — Go

```
/do-work go UR-001
```

Verifies REQ coverage against your brief. If confidence >= 90%, auto-executes the backlog. Each REQ gets TDD'd, evidence-checked, reviewed, committed, and archived individually.

Flags:
- `--force` — run regardless of confidence score
- `--auto-fix` — auto-create missing REQs before checking the threshold

---

## All Commands

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Records brief + decomposes into REQs. Includes ideate by default. |
| `/do-work start [brief] --no-ideate` | Same, but skips the creative review. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks (records `layers_in_scope: []` for this UR). |
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs. |
| `/do-work go [UR-NNN] --no-layers` | Verifies + runs, but skips layer-coverage checks for this UR. |
| `/do-work install` | Creates `.do-work/` folder structure in current project. |
| `/do-work upgrade` | Brings `.do-work/` state into conformance with the current skill. |
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR into REQ files. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run [UR-NNN]` | Executes backlog: TDD loop, acceptance evidence, policy checks, review, archive/ledger. Optional UR-NNN scopes the run. |
| `/do-work run --parallel N` | Single-session parallel mode: dispatches up to N concurrent workers from one terminal. |
| `/do-work run --budget <amount>` | Caps estimated model spend for the run; stops at the next REQ boundary when reached. |
| `/do-work status [UR-NNN]` | Live situation room: REQs, claimers, heartbeats, deadlock warnings, coverage rollup. |
| `/do-work close UR-NNN` | Validates the integrated result of a UR against its verbatim brief; writes a closure report. |
| `/do-work unblock REQ-NNN` | Forces a stuck REQ out of `working/` back to the backlog. |
| `/do-work resume REQ-NNN` | Re-dispatches a fresh worker for a stopped REQ. |
| `/do-work retro` | Mines the run ledger into a learning report + capture calibration guidance. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show help. |

---

## How It Works

1. **Intake** — Your brief is recorded as `UR-NNN/input.md` (with YAML frontmatter for capture state)
2. **Ideate** — Surfaces assumptions, risks, and connections; ends with an interactive gate (Grill / Continue / Stop)
3. **Capture** — Classifies the brief (bug-fix vs feature), assigns each REQ to one of the project's declared layers, prompts on uncovered layers, and writes an `## Integration` block on every new-surface REQ with codebase-verified file references
4. **Verify** — Scores REQ coverage against the original brief, plus three structural checks: layer coverage, Integration block presence, and partial-confidence acknowledgement
5. **Audit** *(always-on)* — Interrogates every REQ's acceptance criteria, auto-fixes vague spots, reports what changed
6. **Run** — Executes each REQ with TDD, then gates completion through acceptance evidence, policy checks, post-build review, closure proof, archive, and ledger recording

`start` = intake + ideate (with gate) + capture. `go` = verify + audit + run.

**Integration base.** `/do-work go` and `/do-work run` never merge worker branches into `main`, `master`, or the remote HEAD short name. Pre-flight calls `lib/ensure-integration-base.sh`: if the orchestrator is already off a protected default, that branch is the base; if on a protected default with a **clean** tree, scoped runs (`go` / `run UR-NNN`) create-or-checkout `ur/UR-NNN`, and unscoped `run` creates `work/<UTC-timestamp>`. A **dirty** tree on a protected default is a hard-stop (no stash, no switch). `/do-work start` does **not** call this helper and never switches branches. The `ur/UR-NNN` name is the same branch used when `delivery.pr.granularity: ur` accumulates a UR PR — merge mode reuses that name without requiring `delivery.mode: pr`.

**Delivery mode.** How a passing REQ is delivered at the integration step is configurable via `delivery.mode` in `.do-work/config.yml`. The default `merge` mode merges each REQ's `req/REQ-NNN` branch into the **integration base** (not `main`/`master` — see above) locally, archives, tears down the worktree, and deletes the branch. Set `delivery.mode: pr` for team repos with CI and human review: instead of merging, the orchestrator pushes the branch and opens a GitHub PR via `gh`, records the PR URL in the archived REQ's `## Outputs` and the run ledger, and leaves the branch alive (the PR owns it). `delivery.pr.granularity: req` (default) opens one PR per REQ; `ur` accumulates every REQ of a UR onto a shared `ur/UR-NNN` branch and opens a single PR when that UR's backlog drains. PR mode requires a configured git remote and the `gh` CLI — if either is missing the run stops with a `missing-creds` stopper and the REQ stays in `working/`; it never silently falls back to merging. The closure-proof model is unchanged in both modes — evidence still gates archive; the PR is only the delivery vehicle.

Normal completion is proof-backed. Capture may mark generated criteria as `agent-drafted`, but that provenance does not block execution. If a REQ exists in the backlog, it should run unless dependencies, footprint, policy, tests, verification, review, or genuinely ambiguous criteria stop it. Workers return checkpointed evidence and per-criterion acceptance evidence; the orchestrator validates that evidence, runs policy checks for blocked paths or commands, invokes post-build review, writes `**Closure proof:**`, derives `proven` / `unproven`, and records `.do-work/runs/RUN-NNN.yml` when the ledger is enabled. A worker report is only an input to completion, not the archive/proof decision.

---

## Skill Structure

This skill is multi-file. `SKILL.md` is the entrypoint and routes commands to agent files:

```
do-work/
├── SKILL.md              ← entrypoint and command router
├── agents/
│   ├── start.md          ← orchestrator: intake + ideate + capture
│   ├── go.md             ← orchestrator: verify + run
│   ├── intake.md         ← records brief verbatim
│   ├── upgrade.md        ← conformance manifest and fixes
│   ├── question.md       ← interactive brief questioning (opt-in)
│   ├── audit.md          ← autonomous REQ quality audit (always-on)
│   ├── ideate.md         ← surfaces assumptions & risks
│   ├── capture.md        ← decomposes into REQ files
│   ├── verify.md         ← scores coverage
│   ├── run.md            ← orchestrator: dispatches a worker per REQ
│   ├── run-worker.md     ← worker: TDD-and-commits a single REQ
│   ├── review.md         ← post-build scope, evidence, policy, and regression review
│   ├── status.md         ← read-only situation room
│   ├── close.md          ← validates a UR's integrated result against its brief
│   ├── unblock.md        ← forces a stuck REQ back to the backlog
│   ├── resume.md         ← re-dispatches a worker for a stopped REQ
│   ├── retro.md          ← mines the run ledger into learning reports
│   ├── log.md            ← build-in-public draft posts
│   ├── help.md           ← command help
│   └── config.md         ← reusable config loading + canonical config template
├── lib/                  ← deterministic bash primitives (claiming, policy,
│   │                       evidence, ledger, conformance scan, …)
│   └── tests/            ← plain-bash test suites (run-all.sh)
├── docs/
├── install.sh
└── README.md
```

---

## Per-Project Folder Structure

When you run `/do-work start` in a project, it creates:

```
your-project/
└── .do-work/
    ├── config.yml               ← project configuration
    ├── user-requests/
    │   └── UR-001/
    │       ├── input.md         ← your original brief
    │       ├── ideate.md        ← creative review (optional)
    │       └── assets/          ← supporting files
    ├── working/                 ← current REQ in flight
    ├── archive/                 ← completed REQs
    ├── logs/                    ← build-in-public log drafts
    ├── state/                   ← coordination state (milestones, calibration, …)
    ├── runs/                    ← run ledger records (RUN-NNN.yml)
    └── REQ-001-slug.md          ← backlog tasks
        REQ-002-slug.md
        ...
```

Everything is auditable — the brief, decomposed tasks, and outputs all live in git history.

---

## Configuration

Each project gets a `.do-work/config.yml` file, auto-created on first `/do-work start` or `/do-work install`. Edit it to customize agent behavior.

The full schema — every key, its type, default, and description — lives in [`agents/config.md`](agents/config.md). That file is also the canonical default template: on first agent run, the config loader migrates any missing sections and keys automatically, so you only need to set the keys you want to override.

The most commonly customized keys at install time:

```yaml
project:
  name: "my-project"    # display name

layers: []              # e.g. [frontend, backend] — gap-checks briefs per layer

test:
  suite_command: ""     # e.g. "./vendor/bin/pest", "npx vitest run"

log:
  enabled: true
  platforms: [x, linkedin]

model:
  default: sonnet       # sonnet | opus | haiku
  escalation: opus

verify:
  threshold: 90         # minimum confidence score for go to auto-run without --force
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` | Project display name |
| `layers` | list of strings | `[]` | Project's declared layers for gap-aware capture. Empty = opt out. |
| `test.suite_command` | string | `""` | Full test suite command (e.g. `./vendor/bin/pest`, `npx vitest run`). |
| `log.enabled` | boolean | `true` | Whether the log step runs after `/do-work go` |
| `log.platforms` | list | `[]` | Platforms to generate draft posts for (e.g. `[x, linkedin, blog]`) |
| `model.default` | string | `sonnet` | Default worker model |
| `model.escalation` | string | `opus` | Escalation model for high-risk or failed work |
| `verify.threshold` | integer | `90` | Minimum confidence score (0-100) for `go` to auto-run without `--force`. |
| `ledger.enabled` | boolean | `true` | Write structured run records under `.do-work/runs/` |

For the full key reference including `feedback`, `parallel`, `next_steps`, `review`, `acceptance`, `risk`, `security`, `cost`, `ledger`, `delivery`, `routing`, and `worktree`, see [`agents/config.md`](agents/config.md).

---

## Layers and Integration

Feature briefs frequently produce REQs that miss the frontend, miss the wiring, or both. do-work's gap-aware capture prevents this by enforcing two structural checks.

**Declared layers.** Each project declares its layers in `.do-work/config.yml` — `[frontend, backend]` for a web app, `[commands, core, output]` for a CLI, whatever fits your stack. Capture tags each REQ with one of the declared layers (or `none` for bug-fixes / pure refactors). If a brief looks full-stack but capture didn't write a REQ for a declared layer, you're prompted: *"Project has layer X, no REQ covers it. Needed?"* Yes generates the missing REQ; No records the decision so verify doesn't keep flagging it.

**Integration block.** Every feature REQ that adds new surface (a new page, route, command, endpoint, etc.) must have an `## Integration` section answering three questions, with concrete file references:
- **Reachability** — How does the user/caller reach this?
- **Data dependencies** — What existing data does it read or write?
- **Service dependencies** — What existing services or modules does it extend?

Capture inspects the codebase to draft the answers, verifies cited files actually exist before claiming high confidence, and asks you when it can't tell. Verify enforces the block on every new-surface REQ.

**Skip per-UR with `--no-layers`** when the checks don't apply (e.g. internal one-shot scripts). The choice is recorded in UR state, so it's auditable.

---

## Parallel Execution

do-work supports parallel execution in two forms:

- **Multi-terminal.** Open two or three terminals, run `/do-work run` in each, and the orchestrators pick disjoint REQs from the backlog and work in parallel. No flag is needed — parallel mode is implicit when a second terminal joins.
- **Single-session.** Run `/do-work run --parallel N` and one orchestrator dispatches up to N concurrent workers (capped at 10), serializing merge/archive through a queue. Defaults from `parallel.max_workers` in config.

Three guarantees keep the parallel terminals from stepping on each other:

1. **Atomic claim.** Two orchestrators racing for the same REQ resolve via `git mv` — the loser sees the source file gone and falls through to the next REQ. No double-work, no manual coordination.
2. **Visible ownership.** Each claimed REQ in `working/` carries a `**Claimed by: <agent-id>**` stamp at the top of the file so it's clear who is doing what. `agent-id` is `hostname.pid` of the owning `/do-work run` process.
3. **Wait-and-retry on conflicts.** Workers whose commits collide on shared files wait with exponential backoff (5 retries over ~110 seconds), then surface the conflict to the user via `status: stopped`, `reason: concurrent-conflict`. No silent auto-resolve.

**When parallel mode shines.** Backlogs of 5+ independent REQs — the work-sharing payoff grows with the backlog size. For single-REQ work, tightly-coupled REQs, or milestone deploy gates (which stay single-agent by design), the simplicity of one terminal is often the better trade-off.

**Isolation per REQ.** Every REQ runs in a dedicated `git worktree` on a `req/REQ-NNN` branch forked from the integration base (`ur/UR-NNN` or `work/<UTC>`, never protected defaults — see **Integration base** above). The orchestrator creates the worktree before dispatch and tears it down after merging into that base — no REQ ever touches `main`/`master`/remote HEAD directly. Dependency directories (`vendor`, `node_modules`, `.venv`) are symlinked from the main checkout into each worktree automatically; use `worktree.link_paths` and `worktree.setup_command` in config for monorepo layouts the auto-detection misses.

See `SKILL.md` `## Parallel Execution` for the full behavioural reference, including state files (`gate-owner.md`, `final-suite-running.md`).

---

## Build in Public (Log)

The log feature generates draft social media posts based on work you've completed — so you can share progress without writing posts from scratch.

### How it works

1. Scans `.do-work/archive/` for REQs completed since the last log entry
2. Generates multiple draft posts per configured platform (different angles, not minor rewrites)
3. Presents all drafts for you to review
4. You pick one per platform — the selection is recorded in `.do-work/logs/log-history.yml` so the same work isn't re-prompted

### Usage

Run it manually:

```
/do-work log
```

Or let it run automatically — `/do-work go` triggers the log step after a clean run (all REQs executed, no stoppers).

### Supported platforms

| Platform | Format |
|----------|--------|
| **X** | 280-char tweets. Threads if content exceeds one tweet. |
| **LinkedIn** | 1-3 short paragraphs, professional tone, ~1300 chars. |
| **Blog** | 1-3 short paragraphs or a single tight idea, ~500 chars default. Plain prose, no markdown headings in the body. No hashtags. Inline links, used sparingly. |

### Length enforcement

Every draft is hard-capped at `log.max_chars[platform]` before being written to disk. If a generated draft exceeds the ceiling, the agent rewrites it once; if it still exceeds, it truncates at the last sentence boundary that fits, falling back to a hard character truncation with an ellipsis if no boundary is available. The ceiling is mechanical, not aspirational — you can tune it per platform in `.do-work/config.yml`.

### Configuration

Set platforms in `.do-work/config.yml`:

```yaml
log:
  enabled: true
  platforms: [x, linkedin, blog]
  drafts_per_platform: 2
  max_chars:
    x: 280
    blog: 500
    linkedin: 1300
```

### Disabling the log

If you don't want build-in-public posts, set `log.enabled: false` in your project's `.do-work/config.yml`:

```yaml
log:
  enabled: false
```

The log step will be skipped entirely — both for `/do-work log` and the automatic step after `/do-work go`.

---

## Commit Convention

Each completed REQ produces a commit:

```
feat(REQ-001): short title

REQ: .do-work/archive/REQ-001-slug.md
UR: .do-work/user-requests/UR-001/input.md
Output: path/to/primary/output
```

---

## License

MIT
