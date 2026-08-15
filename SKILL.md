---
name: do-work
description: >
  Autonomous project-management loop: natural-language briefs → traceable work
  items (Issues/REQs) → isolated TDD workers with one git commit per task. Default
  store is local markdown under .do-work/; optional Linear, sqlite, or
  do-work-io as sole backend via tracker.backend (no dual-write, hard-stop if
  the active backend is unusable). Differentiator: multi-agent runs with footprint-aware claims,
  worktree isolation, and verify/review/archive gates — not a generic todo list.
  Triggers on: "do-work", "intake", "capture", "verify", "run the loop",
  "backlog", "issue", "REQ-", "UR-", "question", "audit",
  "linear backlog", "tracker.backend", "migrate to Linear", "sqlite board".
---

# do-work

Start → Go. (Or granular: Intake → Capture → Verify → Run.)

Work-item storage is pluggable (`tracker.backend`: **markdown** default, **linear**, **sqlite**, or **do-work-io**). Runtime/git (worktrees, merges, state locks, `config.yml`) always stay local.

## Primary loop

Most days you only need these:

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Record a brief and build the REQ backlog (ideate on by default; auto-installs). |
| `/do-work go [UR-NNN]` | Verify coverage, then audit + run when confidence ≥ threshold (default 90%). |
| `/do-work status [UR-NNN]` | Live situation room: in-flight, backlog, recent done, coverage. |
| `/do-work board` | Regenerate static HTML board from work.db (sqlite only). |
| `/do-work` | Help + suggested next steps for this project. |

Flags for start/go (`--no-ideate`, `--force`, `--auto-fix`, …) are in the full table below.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Records brief + decomposes into REQs in one shot. Includes ideate by default. Auto-installs if needed. |
| `/do-work start [brief] --no-ideate` | Same as start, but skips the creativity review before decomposition. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks for this Issue (records `layers_in_scope: []`). |
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of confidence score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs if >= 90%. |
| `/do-work go [UR-NNN] --no-layers` | Verify + run, skipping layer-coverage checks for this Issue. |
| `/do-work install` | Creates `.do-work/` structure in current project. |
| `/do-work upgrade` | Brings the project's .do-work/ state into conformance with the current skill — runs the manifest's detectors and applies fixes (interactive confirmation on destructive rows). Idempotent. |
| `/do-work intake [brief]` | Records brief verbatim as next Issue file. |
| `/do-work capture [UR-NNN]` | Decomposes an Issue brief into REQ files in the backlog. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections in a brief. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage against brief (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run [UR-NNN]` | Executes backlog: TDD loop, evidence validation, post-build review gate, archive/ledger. Optional UR-NNN scopes the run to that Issue's REQs only. |
| `/do-work run [UR-NNN] --parallel N` | Single-session parallel mode: one terminal dispatches up to N concurrent workers (default 1 = serial, capped at 10), serializing merge/archive through a queue. Defaults from `parallel.max_workers`. |
| `/do-work run [UR-NNN] --budget <amount>` | Caps cumulative estimated model spend for the run; overrides `cost.budget` for this invocation. When estimated spend reaches the budget, the loop finishes the in-flight REQ's integration then stops at the next REQ boundary with a budget-stop report. Empty budget = unlimited (default). |
| `/do-work review` | Internal post-build gate used by run after worker evidence validation and before archive completion; not directly invocable — see agents/review.md. |
| `/do-work status [UR-NNN]` | Renders live situation room: REQs, claimers, heartbeats, deadlock warnings, and coverage rollup. Optional UR-NNN scopes the report. |
| `/do-work board` | Regenerate static HTML board from work.db (sqlite only). |
| `/do-work close UR-NNN` | Validates the integrated result of an Issue against its verbatim brief — walks every path-unit's entry point to its terminal state in the merged app and writes a closure report. |
| `/do-work retro` | Mines the run ledger and feedback fingerprints to produce a human report and regenerate `.do-work/state/calibration.md` — advisory capture guidance derived from historical patterns. |
| `/do-work unblock REQ-NNN` | Forces a stuck REQ out of working/ back to the backlog — strips claim stamp, resets status. |
| `/do-work resume REQ-NNN` | Re-dispatches a fresh worker for a stopped REQ — preserves claim, refreshes heartbeat. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show this help. |

Deep per-subcommand stubs (install bootstrap template, flag wiring, pre-flight notes): [references/commands.md](references/commands.md).

---

## Agent files

Detailed instructions for each phase live in separate files. Read the referenced file and follow it exactly.

- [agents/start.md](agents/start.md) — Orchestrator: intake + ideate + capture
- [agents/go.md](agents/go.md) — Orchestrator: verify + conditional run
- [agents/intake.md](agents/intake.md) — Records brief verbatim as next Issue file
- [agents/upgrade.md](agents/upgrade.md) — Brings project state into conformance with the current skill
- [agents/question.md](agents/question.md) — Interactive brief questioning
- [agents/audit.md](agents/audit.md) — Autonomous REQ quality audit
- [agents/ideate.md](agents/ideate.md) — Surfaces assumptions, risks, and connections
- [agents/capture.md](agents/capture.md) — Decomposes brief into REQ files
- [agents/verify.md](agents/verify.md) — Scores REQ coverage against brief
- [agents/run.md](agents/run.md) — Orchestrator: dispatches a worker subagent per REQ; deep sequences: [references/run-loop.md](references/run-loop.md), [references/run-parallel.md](references/run-parallel.md)
- [agents/run-worker.md](agents/run-worker.md) — Worker: TDD-and-commits a single REQ in a fresh subagent session
- [agents/review.md](agents/review.md) — Post-build gate: reviews scope, acceptance evidence, tests, secrets, docs, and regression risk before archive
- [agents/status.md](agents/status.md) — Read-only situation room: REQs, claimers, heartbeats, deadlock warnings, coverage rollup
- [agents/board.md](agents/board.md) — Static HTML board snapshot from work.db (`/do-work board`, sqlite only)
- [agents/close.md](agents/close.md) — Validates the integrated result of an Issue against its verbatim brief; walks path-unit entry points in the merged app; writes `UR-NNN/closure.md`
- [agents/unblock.md](agents/unblock.md) — Force a stuck in-flight REQ back to the backlog
- [agents/resume.md](agents/resume.md) — Re-dispatch a fresh worker for a stopped REQ
- [agents/log.md](agents/log.md) — Generates build-in-public draft posts
- [agents/retro.md](agents/retro.md) — Mines the run ledger to produce a learning report and regenerate `calibration.md`
- [agents/config.md](agents/config.md) — Reusable config loading instructions (includes `tracker.backend` resolution)
- [agents/tracker/port.md](agents/tracker/port.md) — Tracker port: shared work-item op catalog and load path
- [agents/tracker/markdown.md](agents/tracker/markdown.md) — Default markdown backend (`.do-work/` + `lib/*.sh`)
- [agents/tracker/linear.md](agents/tracker/linear.md) — Optional Linear backend (when `tracker.backend: linear`); sequences: [references/linear-ops.md](references/linear-ops.md)
- [agents/tracker/sqlite.md](agents/tracker/sqlite.md) — Optional SQLite backend (when `tracker.backend: sqlite`; `.do-work/work.db` + `lib/dw-db.sh`)
- [agents/tracker/do-work-io.md](agents/tracker/do-work-io.md) — Optional do-work.io backend (when `tracker.backend: do-work-io`; remote MCP + PAT)
- [agents/help.md](agents/help.md) — Contextual help when invoked with no subcommand

Run ledger: when `ledger.enabled: true`, `/do-work run` writes append-only `.do-work/runs/RUN-NNN.yml` records. Set `ledger.enabled: false` to disable.

---

## Hard-stops (tracker summary)

Full multi-backend deep dive: [references/tracker.md](references/tracker.md).

| `tracker.backend` | Behavior |
|-------------------|----------|
| **unset / empty / missing** | Treat as **`markdown`** — no hard-stop, no Linear/`sqlite3` required |
| **`markdown`** | Default: local `.do-work/` files + `lib/*.sh` |
| **`linear`** | Linear is the sole work-item store |
| **`sqlite`** | `.do-work/work.db` is the sole work-item store (`lib/dw-db.sh`) |
| **`do-work-io`** | do-work.io is the sole work-item store (remote MCP; hard-stop if MCP/PAT/project unusable) |

**Load path** (every phase that touches work items): (1) [agents/config.md](agents/config.md), (2) resolve `tracker.backend` (default **markdown**; also accepts **linear**, **sqlite**, and **do-work-io**), (3) [agents/tracker/port.md](agents/tracker/port.md), (4) `agents/tracker/<backend>.md`, (5) call only named port ops for storage.

**Hard-stop (no silent fallback):** when the **active** backend is unusable, agents **hard-stop** with setup instructions — they never fall through to another backend:

| Backend | Hard-stop when |
|---------|----------------|
| **linear** | MCP missing/unauthenticated, team unresolved, missing `status_map` state, or `agents/tracker/linear.md` missing/unreadable |
| **sqlite** | `sqlite3` missing, `agents/tracker/sqlite.md` missing/unreadable, DB corrupt / bad `user_version` (never markdown fallback) |
| **do-work-io** | MCP missing/unauthenticated, PAT/base_url/project missing, or `agents/tracker/do-work-io.md` missing/unreadable |
| **any** | Unknown `tracker.backend` string; skill-root cannot be resolved at entry or Load Config step 8 |

Canonical contract: `agents/tracker/port.md` hard-stop matrix + Load Config steps 6–7c / 8 in `agents/config.md`.

**No dual-write.** One active backend owns work-item truth (markdown, linear, sqlite, **or** do-work-io). Agents must not mirror Issues/REQs across stores, and must not fall back when the active backend fails (hard-stop instead). Switching to sqlite is **greenfield** (empty DB; no history migration in v1). `/do-work board` is **sqlite-only** (static HTML snapshot). After idle markdown→Linear migration (`/do-work upgrade migrate`), historical `.do-work/user-requests/` and `archive/` trees remain on disk as **read-only history** — work-item ops ignore them. **Refuse** `migrate_markdown_to_linear` when already on `sqlite` or `do-work-io`.

**Linear hierarchy:** **Issue (slug UR-NNN) = Project Milestone** on a **shared product Project** per local product (`tracker.linear.product_project` — name or UUID; **default empty**). Resolve: explicit `product_project` → `project.name` → git-root basename; `ensure_product_container` create-if-missing + **always persist UUID**. Never invent skill name `do-work` for empty config (example name for this skill repo only). REQs = Linear Issues on that milestone. Not Initiatives (MCP has no Initiative create tools).

**Linear commit / branch** (when `backend: linear`): subject uses Linear issue id only (`feat(ENG-123): …`); footer `Issue:` / `UR:` / `Output:`; branch/worktree `req/<sanitized-linear-id>` (dir hard-defaults lowercase). Markdown backend still uses `feat(REQ-NNN): …` with `REQ:` / `UR:` archive paths — see [references/concepts.md](references/concepts.md#commit-convention).

**Operator warning (Linear claims):** human remains Issue assignee; agents claim via workflow state + claim-protocol comment (`<!-- do-work-claim -->`). Do not clear/edit/delete agent claim comments in the Linear UI while a run is live. Recover with `/do-work status`, then `resume` or `unblock`.

Markdown remains the default. Operator setup: [docs/troubleshooting.md](docs/troubleshooting.md) § Linear tracker backend; [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) § Multi-tracker; [docs/getting-started.md](docs/getting-started.md).

---

## Project Root Detection

At the start of every subcommand:

```bash
git rev-parse --show-toplevel
```

If this fails (not a git repo), use the current working directory.
All references below use `{project}` to mean this resolved root.

### Skill-root resolve (before conformance)

Immediately after resolving `{project}` and **before** the conformance check, resolve `$SKILL_ROOT` / `{skill-root}` — the absolute path of the do-work skill install root (directory containing `lib/` **and** at least one skill marker: `SKILL.md` **or** `agents/`).

**Recipe:** same walk-up as Load Config step 8 in [agents/config.md](agents/config.md) — **not** a second folklore one-level `dirname/..`. Start from the absolute path of **this** file (`SKILL.md`); walk parents until markers match; hard-stop at filesystem root if none found. **No** env / hub / CWD fallback.

```bash
# Start at the directory of this SKILL.md; walk parents until
# markers match (lib/ AND (SKILL.md OR agents/)). Hard-stop at filesystem
# root if none found. No env/hub/CWD fallback.
d="$(cd "$(dirname "<absolute path of SKILL.md>")" && pwd)"
SKILL_ROOT=""
while true; do
  if [ -d "$d/lib" ] && { [ -f "$d/SKILL.md" ] || [ -d "$d/agents" ]; }; then
    SKILL_ROOT="$d"
    break
  fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
# non-empty $SKILL_ROOT required — else hard-stop (see below)
```

**Inherit for phase agents:** keep this resolved `$SKILL_ROOT` in context for the whole agent turn. Phase agents (and Load Config step 8) **inherit** it when it is still an absolute directory that satisfies the markers — they re-resolve only if missing, empty, non-absolute, or invalid. Do not invent a second resolve recipe in phase docs.

**Hard-stop when skill-root is unknown at entry.** If the harness did not provide an absolute path for this `SKILL.md` **and** walk-up cannot find a valid skill install root, **stop immediately** — do not run conformance, do not dispatch:

`skill-root unknown: cannot resolve $SKILL_ROOT (walk-up from loaded file; no env/hub/CWD fallback). Provide an absolute path to the loaded instruction file under the skill install root, or a valid pre-resolved $SKILL_ROOT that contains lib/ and (SKILL.md or agents/).`

### Conformance check

Immediately after `$SKILL_ROOT` is resolved and before executing any subcommand-specific instructions, run the conformance detectors via the skill install root (**never** bare `bash lib/conformance-scan.sh` — that assumes CWD is the skill root and fails in consumer projects):

```bash
bash {skill-root}/lib/conformance-scan.sh "{project}"
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

**Critical: skill directory is read-only at runtime.** The skill is loaded from a skill install path (e.g. `~/.claude/skills/do-work/` or `~/.grok/skills/do-work/`) — a separate clone. NEVER edit files, stage changes, or commit inside the skills directory. All edits and commits MUST happen in `{project}`. If a REQ targets agent files (e.g. `agents/log.md`), edit them at `{project}/agents/log.md`, not at the skill clone path.

---

## Dispatch

After project-root detection and conformance:

1. Match the subcommand (Quick Reference).
2. For deep stubs (install template, flag/pre-flight detail): read [references/commands.md](references/commands.md) for that subcommand.
3. Read the matching agent file from the index above and follow it exactly.
4. **Before any work-item store I/O:** Load Config → resolve `tracker.backend` → port → backend. Do not treat local `.do-work/user-requests/` or backlog trees as live truth when `backend: linear` or `backend: sqlite`.

No subcommand → print Quick Reference, then follow [agents/help.md](agents/help.md).

---

## On-demand references

Load only when the active task needs them (one hop from this file):

| Reference | When |
|-----------|------|
| [references/commands.md](references/commands.md) | Executing a subcommand; install bootstrap YAML; full step stubs |
| [references/tracker.md](references/tracker.md) | Configuring or debugging multi-tracker / Linear keys, claims, commits |
| [references/concepts.md](references/concepts.md) | Naming, milestone mode, parallel coordination, layers, path-units, decisions, REQ header schema, commit convention, checkpointed verification |
| [references/field-lessons.md](references/field-lessons.md) | Start of a skill run (read); end of run append **only** if **“Will this improve do-work?”** is Yes (skill process for the next run). Product/repo lessons → project via session-capture, never here. Always read before acting if present. |

Recovery (stuck / stopped / deadlock): `/do-work unblock`, `/do-work resume`, `/do-work status` — see agent files and [references/concepts.md](references/concepts.md#recovery-commands).
