# Getting started with do-work

Install the skill, wire it into your agent, then run your first brief with `/do-work start` and `/do-work go`.

## Before you start

- An agent that can load skills from a shared hub (Claude Code, Codex CLI, or another tool pointed at the same hub)
- `git` available on your PATH
- A project directory where you want work tracked under `.do-work/`
- Optional: a project test command you can put in `.do-work/config.yml` as `test.suite_command` (for example `npx vitest run` or `./vendor/bin/pest`)

Time: a few minutes to install; first `start` + `go` depends on the size of your brief.

Related: [Concepts](concepts.md) · [Commands](commands.md)

## Steps

### 1. Install the skill into the skills hub

Default hub path: `~/.agents/skills/do-work`.

Override the hub with `AGENTS_SKILLS_HUB` if your agents load skills from somewhere else.

**Option A — clone this repository (recommended for rawphp/do-work):**

```bash
git clone https://github.com/rawphp/do-work.git ~/.agents/skills/do-work
```

**Option B — run `install.sh` from a checkout:**

```bash
git clone https://github.com/rawphp/do-work.git
cd do-work
bash install.sh
```

`install.sh` clones or updates into `$AGENTS_SKILLS_HUB/do-work` (default `~/.agents/skills/do-work`).

If you use the script’s default remote without a local checkout, note the current default in `install.sh`:

```bash
# Default REPO_URL inside install.sh (override if needed):
# DO_WORK_REPO_URL defaults to https://github.com/agent-native/do-work.git
DO_WORK_REPO_URL=https://github.com/rawphp/do-work.git bash install.sh
```

**Option C — live symlink from a checkout (development):**

```bash
cd /path/to/do-work
bash install.sh --from-cwd
# or: bash install.sh --source /path/to/do-work
```

`--env` is accepted and ignored. All agents share one hub install.

### 2. Wire your agent to the hub

Point Claude Code, Codex, or your other agent at the skills hub so it can load `do-work` (`SKILL.md` in the install directory). Exact agent settings differ by product; the install only places files on disk.

You should be able to invoke `/do-work` (or bare `/do-work` for help) inside a project session.

### 3. Open your project and start a brief

In the project root (or any directory where you want `.do-work/` created):

```text
/do-work start I need a user settings page with email and password change
```

What this does:

1. Creates `.do-work/` on first use if needed (same as `/do-work install`)
2. Records your brief **verbatim** as the next `UR-NNN` under `.do-work/user-requests/UR-NNN/input.md`
3. Runs **ideate** by default (assumptions, risks, connections), then an interactive gate: **Grill** / **Continue** / **Stop**
4. **Capture** decomposes the brief into backlog REQ files (`.do-work/REQ-NNN-slug.md`)

Useful flags:

- `--no-ideate` — skip creative review and the ideate gate
- `--no-layers` — skip layer-coverage checks for this UR (recorded for audit)

If capture stops because layers are undeclared, either set layers in config or pass `--no-layers` (see [Troubleshooting](troubleshooting.md)).

### 4. Configure layers and tests (recommended before a large feature)

On first install, edit `.do-work/config.yml`:

```yaml
project:
  name: "my-project"

layers: [frontend, backend]   # example for a web app; [] opts out until you set them

test:
  suite_command: "npx vitest run"   # your real suite command

verify:
  threshold: 90   # go auto-runs only at or above this score unless --force
```

Empty `layers: []` opts out of layer gap-checks, but **feature** briefs may halt capture until you declare layers or pass `--no-layers`.

Full key list: [`agents/config.md`](../agents/config.md).

### 5. Execute with go

Use the UR number from the start report (example `UR-001`):

```text
/do-work go UR-001
```

What this does:

1. **Verify** — scores REQ coverage against your original brief (0–100%) plus structural checks
2. If score ≥ `verify.threshold` (default **90**): **audit** (sharpen acceptance criteria), then **run** the backlog
3. Each REQ: claim → worktree on `req/REQ-NNN` → TDD → evidence and review gates → archive + commit
4. Optional **close** offer (path-unit flows) and **log** drafts if logging is enabled

Flags:

- `--force` — run even when confidence is below threshold (verify still runs so you see the report)
- `--auto-fix` — create missing REQs once, re-score, then run only if still ≥ threshold
- `--no-layers` — skip layer-coverage checks for this UR (threaded into verify/capture when auto-fix runs)

### 6. Check status while work runs

```text
/do-work status
/do-work status UR-001
```

Read-only situation room: backlog vs working vs archive, claimers, heartbeats, deadlock warnings, coverage rollup.

## How you know it worked

After install:

- Directory exists: `~/.agents/skills/do-work` (or `$AGENTS_SKILLS_HUB/do-work`) with a `SKILL.md` inside
- Your agent exposes `/do-work` / do-work help

After `start`:

- `.do-work/user-requests/UR-NNN/input.md` holds your brief under `## Request`
- One or more `.do-work/REQ-*-*.md` files appear in the backlog root
- Start report lists REQs and totals

After a successful `go`:

- Message like `Go complete for UR-NNN` with verify %, audit outcome, and run count
- Completed REQs under `.do-work/archive/` with status done
- Git history includes commits shaped like `feat(REQ-NNN): short title`
- Optional: `.do-work/runs/RUN-NNN.yml` when `ledger.enabled` is true

## If something goes wrong

| Symptom | What to do |
|---------|------------|
| `/do-work` not found | Confirm hub path and agent skill loading; re-run install |
| Capture halts on layers | Set `layers` in config or use `--no-layers` |
| `go` stops below 90% | Read verify gaps; fix REQs, or use `--auto-fix` / `--force` |
| UR not found | Check `.do-work/user-requests/` for the real `UR-NNN` |
| REQ stuck in `working/` | `/do-work status` then `/do-work unblock REQ-NNN` or `/do-work resume REQ-NNN` |

Full table: [Troubleshooting](troubleshooting.md).

## Related

- [Concepts](concepts.md) — UR, REQ, gates, evidence
- [Commands](commands.md) — full command list
- [How it works](HOW-IT-WORKS.md) — phase design deep dive
