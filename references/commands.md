# Subcommand instructions

Deep step-by-step stubs for each `/do-work` subcommand. `SKILL.md` keeps the Quick Reference table and agent-file index; load this file when executing a subcommand that needs the full stub (especially `install` bootstrap template). After project-root detection and conformance (see `SKILL.md`), prefer reading the phase agent file and following it exactly. Store I/O must follow the tracker port after Load Config — paths below describe the **markdown** default; under `tracker.backend: linear`, use port ops from [agents/tracker/linear.md](../agents/tracker/linear.md) instead of listing local UR/REQ trees as live truth.

## Subcommand Instructions

### No subcommand

Print the Quick Reference table, then read and follow [agents/help.md](../agents/help.md) to display contextual suggestions.

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

# Work-item store. Unset/empty tracker.backend also means markdown (default).
# Full tracker.linear.* schema: agents/config.md (design §7).
# tracker:
#   backend: markdown    # markdown | linear
#   linear:
#     team_id: ""
#     team_key: ""
#     status_map:
#       backlog: "Todo"
#       in_progress: "In Progress"
#       stopped: "Canceled"
#       done: "Done"
```

4. Wire the do-work **session telemetry hooks** into the project's Claude Code
   settings so session start/stop is captured (the resume / terminal-adoption
   flow depends on the `session.start` event carrying the session id). Run the
   idempotent installer — where `{skill-root}` is this skill's install directory
   (the folder containing `lib/`):

   ```bash
   bash {skill-root}/lib/install-hooks.sh {project}
   ```

   This merges a `SessionStart` and a `Stop` hook into
   `{project}/.claude/settings.json`, each invoking `{skill-root}/lib/session-hook.sh`,
   which appends `session.start` / `session.end` lines to
   `.do-work/state/events.jsonl`. The hooks are safe no-ops (exit 0, no writes)
   in any project without `.do-work/`, and the installer dedups by command
   string so re-running install never duplicates them. If `python3` is
   unavailable the installer prints a warning and reports `skipped` (telemetry
   degrades gracefully) — the install still succeeds.

5. Report what was created vs already existed. Example:

```
do-work installed at /path/to/project/.do-work/

Created:
  .do-work/user-requests/
  .do-work/working/
  .do-work/archive/
  .do-work/logs/
  .do-work/state/
  .do-work/config.yml
  .claude/settings.json  (SessionStart + Stop telemetry hooks)

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
2. Read [agents/upgrade.md](../agents/upgrade.md) in full.
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
5. Read [agents/start.md](../agents/start.md) in full.
6. Follow the start agent instructions exactly. Ideate runs by default unless `--no-ideate` was present. Pass `--no-layers` through to capture if present.

---

### go [UR-NNN] [--force] [--auto-fix]

Verify REQ coverage and conditionally execute the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--force` or `--auto-fix` are present in the arguments.
4. Read [agents/go.md](../agents/go.md) in full.
5. Follow the go agent instructions exactly. Pass through any flags.

---

### intake [brief]

Record a natural-language brief as the next UR file. Never skip to planning or implementation.

1. Detect `{project}`.
2. Check if `{project}/.do-work/` exists. If not, run install automatically first, then continue.
3. Determine the brief:
   - If text was provided after `intake`, use it as the brief.
   - If not, ask the user to paste their brief and wait.
4. Read [agents/intake.md](../agents/intake.md) in full.
5. Follow the intake agent instructions exactly.

---

### capture [UR-NNN]

Decompose a UR brief into discrete REQ files in the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to capture.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/capture.md](../agents/capture.md) in full.
5. Follow the capture agent instructions exactly.

---

### ideate [UR-NNN]

Surface assumptions, risks, and connections in a brief before decomposition.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to review.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/ideate.md](../agents/ideate.md) in full.
5. Follow the ideate agent instructions exactly.

---

### question [UR-NNN]

Grill the user about their brief — extract assumptions, gaps, and constraints through one-at-a-time questioning.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to question.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/question.md](../agents/question.md) in full.
5. Follow the question agent instructions exactly.

---

### audit [UR-NNN]

Interrogate REQ quality for a given UR — auto-fix soft spots and report changes.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to audit.
3. Confirm `{project}/.do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/audit.md](../agents/audit.md) in full.
5. Follow the audit agent instructions exactly.

---

### verify [UR-NNN] [--auto-fix]

Score REQ coverage against the original brief. List gaps and issues.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/.do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--auto-fix` is present in the arguments.
4. Read [agents/verify.md](../agents/verify.md) in full.
5. Follow the verify agent instructions. If `--auto-fix` was present, follow the auto-fix section.

---

### run [UR-NNN] [--parallel N] [--budget <amount>]

Execute the backlog autonomously — until empty or a stopper is hit. The optional `UR-NNN` argument scopes execution to that UR's REQs only, ignoring all other backlog entries. The orchestrator dispatches a fresh worker subagent per REQ (see [agents/run-worker.md](../agents/run-worker.md)) and reads its structured return report.

By default the orchestrator runs **serially** — one REQ at a time. The optional `--parallel N` flag enables **single-session parallel mode**: one orchestrator dispatches up to `N` concurrent workers from a single terminal, then serializes their integration through a merge queue. See [Parallel Execution](concepts.md#parallel-execution) (single-session parallel mode).

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
5. Read [agents/run.md](../agents/run.md) in full.
6. Follow the run agent instructions exactly, passing through the UR scope, the resolved parallel window width, and the effective budget.

---

### status [UR-NNN]

Render a read-only live situation room: all in-flight REQs, their claimers, heartbeat ages, any deadlock warnings, and a Coverage section showing intended/proven/unproven REQs.

1. Detect `{project}`.
2. Determine UR scope:
   - If `UR-NNN` was provided, pass it through to scope the report to that UR's REQs.
   - If not provided, all in-flight REQs are reported.
3. Confirm `{project}/.do-work/` exists. If not, report "do-work not installed." and stop.
4. Read [agents/status.md](../agents/status.md) in full.
5. Follow the status agent instructions exactly. No state changes, no commits, no prompts.

---

### close UR-NNN

Validate the integrated result of a UR against its verbatim brief — walking every path-unit's entry point to its terminal state in the merged app — and write a per-path-unit closure report.

1. Detect `{project}`.
2. Confirm `UR-NNN` was provided. If not, report "close requires a UR id (e.g. /do-work close UR-042)." and stop.
3. Confirm `{project}/.do-work/user-requests/UR-NNN/input.md` exists. If not, report "UR-NNN not found at {project}/.do-work/user-requests/UR-NNN/. Check the UR number and try again." and stop.
4. Read [agents/close.md](../agents/close.md) in full.
5. Follow the close agent instructions exactly. The close agent is dispatched as a fresh subagent — pass only the project do-work path, the UR reference, and the merged branch.

---

### unblock REQ-NNN

Force a stuck in-flight REQ out of `working/` and back into the backlog. Use when a worker died, a concurrent-conflict won't resolve, or scope creep needs human triage.

1. Detect `{project}`.
2. Confirm `REQ-NNN` was provided. If not, report "unblock requires a REQ id (e.g. /do-work unblock REQ-042)." and stop.
3. Confirm `{project}/.do-work/working/REQ-NNN-*.md` exists. If not, report "REQ-NNN is not in working/ — nothing to unblock." and stop.
4. Read [agents/unblock.md](../agents/unblock.md) in full.
5. Follow the unblock agent instructions exactly, including the judgment gate on partial commits (Step 3 in the agent file).

---

### resume REQ-NNN

Re-dispatch a fresh worker for a stopped REQ without sending it back through the backlog. Preserves the existing claim stamp; only the heartbeat is refreshed.

1. Detect `{project}`.
2. Confirm `REQ-NNN` was provided. If not, report "resume requires a REQ id (e.g. /do-work resume REQ-042)." and stop.
3. Confirm `{project}/.do-work/working/REQ-NNN-*.md` exists and its `**Status:**` is `stopped`. If not in `working/`, report "REQ-NNN is not in working/ — nothing to resume." If status is not `stopped`, report the actual status and stop.
4. Read [agents/resume.md](../agents/resume.md) in full.
5. Follow the resume agent instructions exactly. Resume is a one-shot — do not loop back to the backlog after dispatch.

---

### log

Generate build-in-public draft posts for configured social media platforms.

1. Detect `{project}`.
2. Read [agents/log.md](../agents/log.md) in full.
3. Follow the log agent instructions exactly.

---

### retro

Mine the run ledger and feedback fingerprints; produce a human report; regenerate `.do-work/state/calibration.md` as advisory capture guidance.

1. Detect `{project}`.
2. Confirm `{project}/.do-work/` exists. If not, report "do-work not installed." and stop.
3. Read [agents/retro.md](../agents/retro.md) in full.
4. Follow the retro agent instructions exactly. Pass the resolved `{project}/.do-work/` path as the project do-work path.
