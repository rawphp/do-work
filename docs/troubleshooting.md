# Troubleshooting do-work

Symptom-first fixes for install, `start` / `go` gates, capture, and stuck runs.

## Quick checks

1. Skill installed where the agent loads skills (`$AGENTS_SKILLS_HUB/do-work` or `~/.agents/skills/do-work`) and contains `SKILL.md`
2. You are in the **project** directory that should own `.do-work/`
3. `UR-NNN` / `REQ-NNN` ids match folders and filenames under `.do-work/`
4. Read `/do-work status` before force-changing in-flight work
5. For feature work: either declare `layers` in `.do-work/config.yml` or pass `--no-layers`

---

## Install and discovery

### `/do-work` is not available in the agent

**Cause:** Skill not installed, or agent not wired to the skills hub.

**Fix:**

1. Confirm the directory exists and has `SKILL.md`:
   ```bash
   ls "${AGENTS_SKILLS_HUB:-$HOME/.agents/skills}/do-work/SKILL.md"
   ```
2. Reinstall:
   ```bash
   git clone https://github.com/rawphp/do-work.git ~/.agents/skills/do-work
   # or from a checkout:
   DO_WORK_REPO_URL=https://github.com/rawphp/do-work.git bash install.sh
   ```
3. Point the agent at the same hub path your install used.

### Install cloned a different GitHub org than expected

**Cause:** `install.sh` defaults `DO_WORK_REPO_URL` to `https://github.com/agent-native/do-work.git` unless overridden.

**Fix:** Set the URL explicitly:

```bash
DO_WORK_REPO_URL=https://github.com/rawphp/do-work.git bash install.sh
```

Or clone `rawphp/do-work` directly into the hub (see [Getting started](getting-started.md)).

### Existing hub directory blocked update

**Cause:** Non-git directory or leftover symlink at the skill path.

**Fix:** Re-run `install.sh`. It backs up non-git directories under `$HUB/.backups/` and replaces symlinks when reinstalling from git. For a live dev link, use `bash install.sh --from-cwd` or `--source <path>`.

---

## Start and capture

### Capture halts because layers are not declared

**Cause:** Feature-class brief with `layers: []` (or unset equivalent) and no `--no-layers`. Capture expects either declared layers or an explicit opt-out.

**Fix:**

1. Set layers in `.do-work/config.yml`, for example:
   ```yaml
   layers: [frontend, backend]
   ```
2. Or skip for this UR:
   ```text
   /do-work start "…" --no-layers
   /do-work capture UR-NNN --no-layers
   ```
   (Pass `--no-layers` on the orchestrator you use; start/go thread it into capture.)

### Start stopped at ideate gate

**Cause:** You chose **Stop** after ideate (or the gate halted the orchestrator).

**Fix:** Edit `.do-work/user-requests/UR-NNN/input.md`, then either:

```text
/do-work capture UR-NNN
```

or run start again only if you intend a **new** UR (intake always creates the next number). Prefer `capture` on the existing UR after revising the brief.

### Start failed at capture; UR exists with no REQs

**Cause:** Capture error after intake succeeded.

**Fix:** Read the error from the agent output, then:

```text
/do-work capture UR-NNN
```

### Feature REQs missing UI or wiring

**Cause:** Layers undeclared or integration block skipped/incomplete; brief under-specified.

**Fix:**

1. Declare layers and re-capture or use verify `--auto-fix`
2. Run `/do-work ideate UR-NNN` / `/do-work question UR-NNN` before capture
3. Run `/do-work verify UR-NNN` and add REQs for gaps
4. Ensure new-surface REQs have a filled `## Integration` section

### Warning: REQs missing verification steps

**Cause:** Help/status heuristics found backlog REQs without typed `## Verification Steps`.

**Fix:**

```text
/do-work verify UR-NNN --auto-fix
```

Or edit each REQ to add test/build/runtime/ui verification steps before `/do-work run`.

---

## Go and verify

### `go` stops with score below threshold

**Cause:** Verify confidence &lt; `verify.threshold` (default 90) and neither `--force` nor a successful `--auto-fix` applied.

**Fix:**

1. Read the gap list from verify
2. Add or edit REQs manually, or:
   ```text
   /do-work go UR-NNN --auto-fix
   ```
3. If you accept the risk of incomplete coverage:
   ```text
   /do-work go UR-NNN --force
   ```
4. Lowering `verify.threshold` in config changes the gate for future runs—prefer fixing coverage when you can

### `UR-NNN not found`

**Cause:** Wrong number, or `.do-work` lives in another directory.

**Fix:** List requests:

```bash
ls .do-work/user-requests/
```

Confirm `user-requests/UR-NNN/input.md` exists. Re-run go with the correct id.

### Auto-fix still below threshold

**Cause:** One `--auto-fix` pass cannot invent missing product intent; score remains under threshold.

**Fix:** Manual review of gaps; extend the brief or REQs; re-run verify/go. Do not expect multiple silent auto-fix loops—`go` runs auto-fix **once**.

### Audit changed my REQs

**Cause:** Expected. Audit inside `go` sharpens vague acceptance criteria before run.

**Fix:** Read the audit change report. Adjust criteria if the auto-fix misread intent, then continue or re-run verify if you changed scope substantially (audit alone does not re-score).

---

## Run, parallel, delivery

### REQ stuck in `working/`

**Cause:** Worker crashed, session killed, or heartbeat went stale.

**Fix:**

```text
/do-work status
/do-work unblock REQ-NNN
```

Then `/do-work run` or `/do-work go UR-NNN` again as appropriate. Unblock may ask what to do about partial commits—answer deliberately.

### `status: stopped`, `reason: concurrent-conflict`

**Cause:** Parallel workers collided on shared files after retries (~110s backoff).

**Fix:**

```text
/do-work resume REQ-NNN
```

Reduce overlap (narrow `**Files:**` footprints) or run fewer parallel workers.

### Deadlock banner in status

**Cause:** Circular wait among in-flight REQs (`Depends on:` chains).

**Fix:**

```text
/do-work status
/do-work unblock REQ-NNN   # break the cycle on one participant
```

Fix dependency declarations in backlog REQs if the graph is wrong. Capture-time cycle check should prevent many bad graphs; runtime deadlocks still need human triage.

### `missing-creds` stopper (PR delivery)

**Cause:** `delivery.mode: pr` but `gh` or git remote is missing/misconfigured. do-work does **not** silently fall back to merge.

**Fix:** Configure remote + authenticated `gh`, or set `delivery.mode: merge` in `.do-work/config.yml` if local merge is intended.

### Integration base: dirty tree on `main` / `master` (hard-stop)

**Symptom:** `/do-work go` or `/do-work run` stops immediately with stderr from `ensure-integration-base.sh` about a dirty working tree on a protected branch; no workers start.

**Cause:** Pre-flight will not create `ur/UR-NNN` or `work/<UTC>` while the orchestrator is on a protected default (`main`, `master`, or remote HEAD) with uncommitted changes. It never stashes and never switches over dirt.

**Fix:** Commit or discard local changes on that branch, then re-run go/run. If you already intend a non-default base, check out that branch yourself first (clean or dirty is fine once off the protected default — ensure only auto-switches when leaving the default).

### Integration base: auto-switched off the default branch

**Symptom:** After go/run, the main checkout is on `ur/UR-NNN` (scoped) or `work/<timestamp>` (unscoped), not `main`/`master`.

**Cause:** Expected. `lib/ensure-integration-base.sh` leaves protected defaults so REQ merges never land on remote HEAD. Scoped runs reuse `ur/UR-NNN` (same name as `delivery.pr.granularity: ur`; pr mode is not required). `/do-work start` does not switch branches.

**Fix:** None required for the run. When you want to promote, merge or open a PR from the integration base to the default branch yourself. To stay on a long-lived feature base, check it out before go/run so ensure is a no-op.

### Review or evidence gate failed

**Cause:** Worker finished coding but orchestrator rejected evidence, policy, or post-build review.

**Fix:** Read the stopper output and the REQ in `working/`. Fix tests/evidence or policy violations; `resume` or `unblock` per status. Do not treat a worker narrative alone as proof of archive.

### Budget stop

**Cause:** `/do-work run --budget …` or `cost.budget` reached after finishing the in-flight REQ’s integration.

**Fix:** Raise or clear the budget and run again; remaining backlog REQs stay eligible.

### Worktree / dependency issues

**Cause:** Isolated worktree missing `node_modules`, `vendor`, etc.

**Fix:** Configure `worktree.link_paths` and/or `worktree.setup_command` in `.do-work/config.yml` (see `agents/config.md`). Ensure the main checkout has dependency dirs the provisioner can symlink.

---

## Linear tracker backend

Optional work-item store when `tracker.backend: linear` in `.do-work/config.yml`. Markdown remains the default when the key is unset or `markdown`. Deep dive: [How it works → Multi-tracker](HOW-IT-WORKS.md#multi-tracker-work-item-backends). Canonical hard-stop copy: `agents/tracker/linear.md`.

### HARD STOP: Linear MCP not usable

**Cause:** `tracker.backend` is `linear` but Linear MCP tools are missing, unauthenticated, or undiscoverable. do-work **does not** fall back to markdown work-item storage.

**Fix — connect Linear MCP:**

1. **Preferred (API key):**
   - Create a Personal API key in Linear → Settings → Account → Security & access
   - Export in the shell that launches the agent (do not paste the key into chat):
     ```bash
     export LINEAR_API_KEY='lin_api_...'
     ```
   - Configure MCP server `linear` at `https://mcp.linear.app/mcp` with `Authorization: Bearer ${LINEAR_API_KEY}`
   - Restart the agent / refresh MCP and verify tools (e.g. `search_tool "linear"`)

2. **OAuth alternative** (if your host supports it): add HTTP MCP server `linear` → `https://mcp.linear.app/mcp`, authenticate in the host MCP UI. If OAuth sticks on "authenticating", use the API key path.

3. **Grok CLI examples** (host-specific):
   ```bash
   grok mcp add --transport http linear https://mcp.linear.app/mcp
   grok mcp enable linear
   grok mcp doctor linear
   ```

Then re-run the phase. If a claim was already active when MCP died mid-flight, **leave it** — use `/do-work resume` or `/do-work unblock` after MCP recovers.

### Team unresolved (`team_id` / `team_key`)

**Cause:** Linear MCP works but config has empty/wrong team.

**Fix:** Set a real team in `.do-work/config.yml`:

```yaml
tracker:
  backend: linear
  linear:
    team_id: "<linear-team-uuid>"   # preferred
    team_key: ""                    # optional alternate resolve
```

Do **not** guess a team. Agents hard-stop until one resolves. Full schema: `agents/config.md`.

### `status_map` state missing on team

**Cause:** Defaults (`Todo` / `In Progress` / `Canceled` / `Done`) do not match your team’s workflow names.

**Fix:** Rename the team workflow state to match, **or** override `tracker.linear.status_map.<key>` to an existing state name. Missing states are never invented.

### Operator cleared agent claim comments mid-run

**Cause:** Human edited/deleted `<!-- do-work-claim -->` comments (or equivalent `agent_claim_marker`) in the Linear UI while a worker was live. Assignee stays human; agents rely on those comments for claim + heartbeat.

**Fix:**

1. Prefer: **do not clear claim comments while a run is live**
2. If already cleared: treat protocol as broken — stop inventing state; wait until agents stop, then `/do-work status` and `/do-work unblock` / re-claim via a fresh run
3. Recover mid-flight MCP stops with `/do-work resume` only when the claim comment is still intact and status is stopped

### Want Linear but still on markdown history

**Cause:** Project has local URs/REQs; you want cutover.

**Fix:** Idle only (`working/` empty, no active claims):

```text
/do-work upgrade migrate
```

Use dry-run first when offered. After cutover: no dual-write; historical markdown trees are read-only. Refuse if already `backend: linear` or if working/ is non-empty.

### Accidentally set `backend: linear` without Linear

**Cause:** Config flipped before MCP/team were ready.

**Fix:** Either connect MCP + set `team_id` (above), or set `tracker.backend: markdown` (or remove the key) to return to the default local store. Do not dual-write.

### Intake hard-stops looking for Initiatives

**Cause:** Older skill text required Initiative + per-UR Project. Current hierarchy uses **Project Milestones** for URs (Linear MCP has milestone CRUD, not Initiative create).

**Fix:** Use skill version with Milestone-as-UR (`agents/tracker/linear.md` § Hierarchy). Ensure the shared product Project resolves: set `tracker.linear.product_project` (name|UUID) **or** leave it empty so resolve uses `project.name` → git-root basename, then `ensure_product_container` create-if-missing + persists UUID. Do **not** expect a universal default Project named `do-work` (that name is only an example for this skill repo). Confirm milestone tools appear in `search_tool "linear milestone"`.

---

## Upgrade and legacy layout

### Prompt to run `/do-work upgrade`

**Cause:** Conformance scan found legacy paths, stale config keys, or similar.

**Fix:**

```text
/do-work upgrade
```

Confirm destructive rows interactively. Prefer an idle project (no mid-flight `run`) before migrating layouts.

### State still under legacy `do-work/` (non-hidden)

**Cause:** Older projects used a visible `do-work/` directory; current default is `.do-work/`.

**Fix:** Follow skill migration / `/do-work upgrade` guidance in `SKILL.md`. Do not hand-move `working/` files while a run is active.

---

## Log and close

### Log did nothing after `go`

**Cause:** Stopper hit; or `log.enabled: false`; or `log.platforms` empty.

**Fix:** Check `.do-work/config.yml`:

```yaml
log:
  enabled: true
  platforms: [x, linkedin]
```

Run `/do-work log` manually after archive has new REQs.

### Close not offered / closure gaps

**Cause:** Close applies when path-unit REQs (entry point + terminal state) exist; gaps mean a path did not reach the expected terminal state in the merged app.

**Fix:** Run explicitly:

```text
/do-work close UR-NNN
```

Treat gap rows as product issues to fix with new REQs; they do not by themselves block logging.

---

## Still stuck

1. `/do-work status UR-NNN`
2. Inspect `.do-work/working/`, `.do-work/archive/`, and latest `.do-work/runs/RUN-*.yml` if ledger is enabled
3. Re-read [Concepts](concepts.md) for gate meaning
4. Deep dive: [How it works](HOW-IT-WORKS.md) and `SKILL.md`

## Related

- [Getting started](getting-started.md)
- [Commands](commands.md)
- [Concepts](concepts.md)
