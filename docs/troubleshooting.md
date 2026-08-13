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

### Integration base: dirty tree on `main` / `master`

**Symptom:** You have uncommitted changes on a protected default and run go/run.

**Cause (current behaviour):** Leave-default still runs. Uncommitted changes **carry** onto `new-work` (create-if-missing, or checkout existing + merge the protected tip). There is no dirt-only hard-stop.

**If something fails:** Merge conflicts when updating an existing stale `new-work`, detached HEAD, or checkout failure still hard-stop — resolve those, then re-run. To avoid carrying dirt, commit or stash before go/run.

### Integration base: auto-switched off the default branch

**Symptom:** After go/run, the main checkout is on `new-work`, not `main`/`master`.

**Cause:** Expected. `lib/ensure-integration-base.sh` leaves protected defaults so REQ merges never land on remote HEAD. Leave-default always uses fixed branch `new-work` (same name as `delivery.pr.granularity: ur` accumulation; pr mode is not required). Existing `new-work` is updated by merging the protected tip. `/do-work start` does not switch branches.

**Fix:** None required for the run. When you want to promote, merge or open a PR from `new-work` to the default branch yourself. To stay on a long-lived feature base, check it out before go/run so ensure is a no-op.

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

## SQLite tracker backend

Optional local work-item store when `tracker.backend: sqlite` in `.do-work/config.yml`. Markdown remains the default when the key is unset or `markdown`. Deep dive: [How it works → Multi-tracker](HOW-IT-WORKS.md#multi-tracker-work-item-backends). Canonical sequences: `agents/tracker/sqlite.md`. CLI: `lib/dw-db.sh`.

### Switch to sqlite (greenfield)

**Cause:** You want a single local DB for URs/REQs instead of markdown files or Linear.

**Fix — opt in:**

```yaml
tracker:
  backend: sqlite
  sqlite:
    path: ""                 # default .do-work/work.db
    board_path: ""           # default .do-work/board/index.html
    busy_timeout_ms: 5000
```

Rules that matter:

- **Greenfield only** — first ensure creates an **empty** `.do-work/work.db`. Prior markdown URs/REQs and Linear history are **not** imported in v1.
- **No dual-write** — with `backend: sqlite`, `.do-work/work.db` is the sole work-item store. Do not treat `REQ-*.md` / `user-requests/` as live truth.
- **`work.db` is gitignored** — `/do-work upgrade` ensures `.gitignore` has `.do-work/work.db`, `.do-work/work.db-*`, and board output paths.
- **No markdown→Linear migrate under sqlite** — `/do-work upgrade migrate` **refuses** when `tracker.backend` is `sqlite` (`migrate-linear: refused-sqlite-backend`). There is no sqlite→Linear path either.

To leave sqlite: set `tracker.backend: markdown` (or remove the key) or `linear` when that backend is ready. Switching **away** does not export DB rows into markdown.

### HARD STOP: `sqlite3` not on PATH

**Cause:** `tracker.backend` is `sqlite` but the `sqlite3` CLI is missing or not executable. do-work **does not** fall back to markdown.

**Fix — install sqlite3:**

```bash
# macOS (Homebrew)
brew install sqlite

# Debian / Ubuntu
sudo apt-get install sqlite3

# Verify
command -v sqlite3 && sqlite3 -version
```

Then re-run the phase. Agents call `lib/dw-db.sh` only — do not invent freehand `sqlite3` one-liners for work items.

### HARD STOP: corrupt DB or bad `user_version`

**Cause:** `.do-work/work.db` exists but is unreadable, not a SQLite database, or `PRAGMA user_version` is not the schema the skill expects (v1 = `1`).

**Fix:**

1. Confirm the path (empty `tracker.sqlite.path` → `{project}/.do-work/work.db`)
2. Inspect version (read-only):
   ```bash
   sqlite3 .do-work/work.db 'PRAGMA user_version;'
   ```
3. If the file is corrupt or from an incompatible experiment: **back it up**, remove `work.db` and WAL sidecars (`work.db-wal`, `work.db-shm`), then re-run — ensure recreates an empty greenfield DB
4. Do **not** hand-edit schema SQL to “force” a version; do **not** fall back to markdown trees as live store while config still says `sqlite`

### Board not updating

**Cause:** `/do-work board` is **sqlite-only** and regenerates the static HTML snapshot **only when you invoke it**. It is not a live server and does not auto-refresh on every claim/archive.

**Fix:**

```text
/do-work board
```

Default output: `.do-work/board/index.html` (override with `tracker.sqlite.board_path`). Hard-stop if `backend` is not `sqlite`. Open the HTML file in a browser after regenerate.

### Accidentally set `backend: sqlite` without sqlite3

**Cause:** Config flipped before the CLI was installed.

**Fix:** Install `sqlite3` (above), or set `tracker.backend: markdown` (or remove the key) to return to the default local file store. Do not dual-write.

### Tried `/do-work upgrade migrate` on sqlite

**Cause:** `upgrade migrate` is **markdown→Linear only**.

**Fix:** Expect refuse:

```text
Migration refused: tracker.backend is sqlite.
/do-work upgrade migrate is markdown→Linear only. No sqlite→Linear path.
```

Stay on sqlite, or switch backend intentionally (greenfield implications apply). See `agents/upgrade.md` Step 9.

---

## do-work.io tracker backend

Optional remote work-item store when `tracker.backend: do-work-io` in `.do-work/config.yml`. Markdown remains the default when the key is unset or `markdown`. Deep dive: [How it works → Multi-tracker](HOW-IT-WORKS.md#multi-tracker-work-item-backends). Canonical sequences: `agents/tracker/do-work-io.md`.

### Switch to do-work.io

**Cause:** You want URs/REQs to live only on do-work.io (remote MCP), not in local markdown, Linear, or sqlite.

**Fix — opt in:**

- Set `tracker.backend: do-work-io`
- Mint a **control** PAT in the web UI (email must be verified)
- Export `DOWORK_IO_PAT` (or the env name in `tracker.dowork.token_env`) in the agent’s environment — never commit it, and **do not paste the token into chat**
- Set `tracker.dowork.base_url` (e.g. `https://api.do-work.test`) and `tracker.dowork.project` (slug)
- Point MCP at `{base_url}/mcp/dowork.control` with `Authorization: Bearer $DOWORK_IO_PAT`

```yaml
tracker:
  backend: do-work-io
  dowork:
    base_url: ""                 # e.g. https://api.do-work.test (origin, no /mcp path)
    token_env: DOWORK_IO_PAT     # process env var holding the Sanctum PAT
    project: ""                  # project slug (identity key)
    mcp_profile: dowork.control  # dowork.read | dowork.control | dowork.admin
```

Rules that matter:

- **No dual-write** — with `backend: do-work-io`, do-work.io is the sole work-item store. Do not treat `REQ-*.md` / `user-requests/` or Linear as live truth.
- **Unusable MCP / missing PAT / unknown project → hard-stop**; no markdown fallback
- **Stale claims:** read `active_claim.heartbeat_at`; recover with `/do-work resume` or `/do-work unblock`, or let the next `req.claim` take over if stale
- **`/do-work board`** is sqlite-only — the do-work.io web dashboard is the live board
- **`/do-work upgrade migrate`** (markdown→Linear) **refuses** when `tracker.backend` is `do-work-io`

### HARD STOP: MCP / PAT / project unusable

**Cause:** `tracker.backend` is `do-work-io` but `agents/tracker/do-work-io.md` is missing, `tracker.dowork.base_url` is empty/invalid, `${tracker.dowork.token_env}` is unset, `tracker.dowork.project` is empty, or MCP tools are undiscoverable / 401. do-work **does not** fall back to markdown, Linear, or sqlite.

**Fix:**

1. Export the Sanctum PAT (do **not** paste the token into chat):
   ```bash
   export DOWORK_IO_PAT='…'
   ```
   Mint a PAT in the do-work.io web UI (verified email). Profile must include the loop tools (default `tracker.dowork.mcp_profile` = `dowork.control`).
2. Set `tracker.dowork.base_url`, `tracker.dowork.project` (slug), and optionally `tracker.dowork.token_env` / `tracker.dowork.mcp_profile` in `.do-work/config.yml`.
3. Point the MCP host at `{base_url}/mcp/{mcp_profile}` with `Authorization: Bearer $<token_env>`. Restart / refresh MCP and verify via `search_tool` `req.claim`.

Then re-run the phase. If a claim was already active when MCP died mid-flight, **leave it** — use `/do-work resume` or `/do-work unblock` after MCP recovers.

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
