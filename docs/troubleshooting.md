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
