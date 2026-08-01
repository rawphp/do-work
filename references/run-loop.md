# Run loop sequences (reference)

One hop from [`agents/run.md`](../agents/run.md). Load when executing the serial run loop (claim → dispatch → gates → integrate → recover). Hard rules and step outline stay in the agent file.

---

## Agent Identity

Each `/do-work run` process derives a stable `hostname.pid` identifier once at startup and reuses it for the lifetime of that run loop.

### ID derivation

```bash
AGENT_ID="$(hostname).$$"
# Example result: mbp-tom.42137
```

- `hostname` — machine name, distinguishes agents on different machines sharing a repo
- `$$` — the shell PID of the current `/do-work run` process, unique per process on the same machine
- The combined string is computed **once** when the orchestrator starts and stored in the shell variable `AGENT_ID`

### Ownership stamp format

When the orchestrator claims a REQ into `working/`, it inserts the following block at the top of the REQ file, immediately under the `# REQ-NNN:` heading and before the existing `**UR:** ...` field:

```markdown
<!-- claimed-start -->
**Claimed by:** <agent-id>
**Claimed at:** <ISO-8601 UTC>
**Heartbeat:** <ISO-8601 UTC>
<!-- claimed-end -->
```

Example of a claimed REQ header:

```markdown
# REQ-115: Pre-flight concurrent-slot check

<!-- claimed-start -->
**Claimed by:** mbp-tom.42137
**Claimed at:** 2026-05-15T14:03:22Z
**Heartbeat:** 2026-05-15T14:03:22Z
<!-- claimed-end -->

**UR:** UR-025
**Status:** in-progress
```

### Stamp lifecycle

| Phase | Actor | Action |
|---|---|---|
| Claim time | Orchestrator (REQ-114) | Inserts `<!-- claimed-start … claimed-end -->` block after claiming the file into `working/` |
| Pre-flight | Sibling orchestrators (REQ-115) | Read `working/REQ-*.md` files; parse the block to attribute each slot to its owning agent |
| Archive time | Worker (this file) | Strips the `<!-- claimed-start … claimed-end -->` block before moving the file to `archive/` |

The stamp is a filesystem-visible, human-readable contract. Archived REQs do not retain ownership metadata — only the git commit message records which agent committed the change.

---


---

## Pre-flight Check

> **Default behaviour:** By default the orchestrator claims unblocked backlog work; stale-slot triage is a fallback that fires only when the backlog is empty for this agent. The `working/` scan at §3 is informational — it populates buckets used by the picker's overlap exclusion and, if the backlog is drained, the fallback prompt. It is NOT a gate on starting work.

Before starting the loop:

### 1. Branch and working-directory checks

- Confirm you are on the correct git branch.
- Confirm your working directory is `{project}` (the user's repo), NOT the skill clone at `~/.claude/skills/do-work/`. All file edits and git commits must happen in `{project}`. If you are in the skills directory, `cd` to `{project}` before proceeding.
- **Ensure `.do-work/state/` exists.** Run `mkdir -p {project}/.do-work/state` defensively. Subsequent steps (stale reclaim, milestone mode, deadlock surfacing, gate-owner writes, final-suite lockfile) write here; installs from before REQ-170 may not have created the directory.

### 2. Resolve agent id

Compute `AGENT_ID` per `## Agent Identity`:

```bash
AGENT_ID="$(hostname).$$"
```

### 2a. Resolve `{skill-root}` to a concrete absolute path

**Single home:** resolve once via **Load Config step 8** in [`agents/config.md`](../agents/config.md) (walk-up from loaded instruction file with marker requirements + inherit of a valid `$SKILL_ROOT`; hard-stop if the path is unknown). Keep `$SKILL_ROOT` in context for this run. Do **not** re-implement a second full recipe here — no env/hub/CWD fallback.

`{skill-root}` is the absolute skill install root (directory containing `agents/`, `lib/`, `SKILL.md`). Lib invocations throughout this file (`{skill-root}/lib/scan-stale.sh`, etc.) and in `agents/run-worker.md` (heartbeat, file-feedback) only resolve when `{skill-root}` is a real absolute path. A worker `cd`'d into a consumer project's worktree has no `lib/` of its own, so the orchestrator substitutes `$SKILL_ROOT` into every `{skill-root}/lib/...` call it makes and passes that same absolute value as the worker **Skill root** input (Step 2 dispatch).

### 2b. Generate or refresh the project context pack

Workers run context-starved by design (their "When Invoked" rule). To raise implementation quality without making each worker re-explore the repo, the orchestrator maintains **one** project context pack at `{project}/.do-work/state/context-pack.md` and passes its path to every worker. One orchestrator-level scan amortises across every worker in every run.

**Staleness rule (documented, pick-one): the pack is stale when it is older than 14 days OR more than 50 commits behind `HEAD`.** Regenerate only when stale or absent — a fresh pack costs no per-run scan.

```bash
PACK="{project}/.do-work/state/context-pack.md"
REGEN=0
if [ ! -f "$PACK" ]; then
    REGEN=1                                   # absent → must generate
else
    PACK_MTIME=$(stat -f %m "$PACK" 2>/dev/null || stat -c %Y "$PACK")
    AGE_DAYS=$(( ($(date +%s) - PACK_MTIME) / 86400 ))
    # Commits landed on HEAD since the pack was last written.
    COMMITS_SINCE=$(git rev-list --count --since="@$PACK_MTIME" HEAD 2>/dev/null || echo 0)
    if [ "$AGE_DAYS" -ge 14 ] || [ "$COMMITS_SINCE" -ge 50 ]; then
        REGEN=1                               # stale → refresh
    fi
fi
```

**If `REGEN=0` (pack is fresh): skip generation entirely.** Do not scan, do not rewrite the file. This is the common case and it must carry zero per-run scan cost.

**If `REGEN=1` (absent or stale): scan the project once and write a ~200-line pack.** Keep it to roughly 200 lines — a map, not a copy of the codebase. Cover:

- **Architecture** — the top-level shape of the system (layers, services, entry points) in a few sentences.
- **Directory roles** — one line per significant top-level directory (what lives there, what it is for).
- **Key services / modules** — the handful of files or modules a worker is most likely to touch or extend, with a one-line role each.
- **Naming & test conventions** — how files, tests, and symbols are named; where tests live; the dominant test idiom.
- **How to run the suite** — the exact command(s) to run the project's tests (mirror `config.test.suite_command` when set).

Write the result to `$PACK` (filesystem only — `.do-work/state/` is orchestrator-owned; do not commit it from here). The pack is project-level state, regenerated on the staleness cadence above, and read by every dispatched worker.

### 3. Scan and classify working/ slots (informational — hold all buckets in memory, do not prompt)

**Staleness detection — delegate to `lib/scan-stale.sh`:**

```bash
STALE_SLOTS=$(bash {skill-root}/lib/scan-stale.sh)
```

`scan-stale.sh` (REQ-149, extended in REQ-172) reads `parallel.stale_threshold_seconds` from `.do-work/config.yml` (default 300 s) and prints one line per stale slot in the form `<req-path> <heartbeat-iso-or-"absent"> age=<seconds-or-"unknown">`. Slots with a missing or malformed `**Heartbeat:**` are treated as stale by the script and emit `age=unknown`. The orchestrator does not re-implement this logic inline.

**Ownership classification — inline (cheap deterministic read):**

Glob `{project}/.do-work/working/REQ-*.md`. For each file found, read its ownership stamp (the `<!-- claimed-start --> … <!-- claimed-end -->` block) and classify the slot into one of three buckets. **Retain all three buckets in memory. Do not prompt at this stage regardless of what the stale bucket contains.**

| Bucket | Condition | Action |
|---|---|---|
| **`mine`** | `**Claimed by:**` in the stamp matches `AGENT_ID` | Resume this REQ — skip the claim step and jump directly to worker dispatch for it |
| **`sibling`** | `**Claimed by:**` is set, differs from `AGENT_ID`, AND the slot path is NOT in `$STALE_SLOTS` | Leave alone — another live orchestrator owns it |
| **`out-of-milestone`** | Milestone mode is active (`.do-work/state/active-milestone.md` exists) AND the slot's milestone id (parsed from the filename: `REQ-M<n>-NNN-slug.md` → `M<n>`) differs from the active milestone | Silently ignore — treat the same as `sibling` (a previous-milestone REQ still in flight during a milestone transition is informational only) |
| **`stale`** | Slot path appears in `$STALE_SLOTS` output | Hold in memory — surface only as fallback when backlog has no claimable REQ |

### 3a. Timestamp reasoning rule

All timestamps in REQ files (`**Claimed at:**`, `**Heartbeat:**`, and any
`<ISO-8601 UTC>` value) are UTC with a `Z` suffix. The local wall-clock
date may differ from the UTC date by ±1 day based on the host's
timezone. Do NOT decide whether a slot is fresh by comparing the
heartbeat's calendar date to "today" — that reasoning will misclassify
recent slots as stale across the UTC/local date boundary.

Slot staleness is determined solely by `$STALE_SLOTS` (the output of
`lib/scan-stale.sh`, which compares UTC epochs deterministically).
When you need to surface "how long ago" to the user, use the `age=<seconds>`
token from `scan-stale.sh`'s output — not the raw ISO timestamp.

### 3b. Legacy stranded REQ triage (advisory — no automatic state change)

While classifying `working/` slots in §3, also identify **legacy stranded REQs**: files whose `**Status:**` is `stopped` and whose `**Reason:**` value is not in the documented stopper enum (`tests-failing`, `verification-failing`, `missing-creds`, `ambiguous-criteria`, `scope-creep`, `dependency-missing`, `concurrent-conflict`, `unknown-error`). The canonical example is `awaiting-human-verification`, an improvised reason from an older human-wait flow.

**Detection:** for each `working/REQ-*.md` file, read `**Status:**` and `**Reason:**`. If `**Status:** stopped` AND `**Reason:**` is non-empty AND the reason does not match any enum value above, record the file as a **legacy stranded slot**.

**Advisory output (emit once per run, immediately after §3 classification — do NOT block the run or prompt):**

If any legacy stranded slots were found, print a triage notice before proceeding to §4:

```
⚠ Legacy stranded REQ(s) detected in working/:
  - REQ-NNN  reason: <raw-reason-value>  (<slug>)
  ...
These REQs stopped with an unrecognized reason and were never migrated to the
current delivery flow. Triage guidance (advisory — take the appropriate action manually):
  • If the req/ branch exists and still needs work:
      → Resume it: /do-work resume REQ-NNN
  • If the code was not delivered and no usable branch remains:
      → Unblock it: /do-work unblock REQ-NNN  (returns it to backlog for re-dispatch).
Run continues — no automatic state change was made.
```

This triage report is informational only. The orchestrator does NOT automatically move files, rewrite status fields, or modify any REQ. The human (or a subsequent operator) takes the appropriate action based on the guidance. The legacy slots are classified into the `stale` bucket for footprint exclusion purposes (same as any stopped slot).

### 4. Resume any `mine` slot

If the `mine` bucket is non-empty, resume that REQ — skip the claim step and jump directly to worker dispatch for it.

### 5. Try the backlog (primary path)

No `mine` slot is present. Immediately attempt `lib/pick-req.sh`:

```bash
PICK_STDERR=$(mktemp)
REQ_PATH=$(bash {skill-root}/lib/pick-req.sh "$SCOPE" "$AGENT_ID" 2>"$PICK_STDERR")
```

`pick-req.sh` already excludes any REQ whose `**Files:**` overlaps with a slot in `working/` — **both `sibling` and `stale` slots are treated as in-flight** for the purpose of footprint exclusion. You do not need to communicate the stale list to the picker separately; it reads `working/` directly.

- **If `pick-req.sh` returns a path:** claim it (proceed to The Loop, Step 1 claim sequence). **Do not surface any stale-slot prompt**, regardless of what `$STALE_SLOTS` contains.
- **If `pick-req.sh` returns nothing:** continue to §6.

### 6. Fallback: backlog drained — evaluate working set

Reached only when `pick-req.sh` returned no candidate AND the `mine` bucket is empty. Now the stale bucket matters:

- **`stale` is non-empty:** prompt the user once (batch all stale slots into a single message — do NOT prompt per slot):

  ```
  N stale REQ(s) found in working/:
    - REQ-NNN (claimed by <agent-id-or-unknown>, last activity <human-age> ago)
    - ...
  These appear abandoned. Reclaim into this run, return to backlog, or abort?
  ```

  Where `<human-age>` is derived from the `age=<seconds>` token in `$STALE_SLOTS` output: convert seconds to the coarsest human unit that is non-zero (e.g. `42s`, `7m`, `2h`, `3d`). When `age=unknown`, render `unknown` in place of a duration. Do NOT use the raw ISO heartbeat timestamp to fill this field.

  - **Reclaim into this run:** For each stale REQ, rewrite its stamp to the local `AGENT_ID` and a fresh `**Claimed at:**` (ISO-8601 UTC). These REQs become the first ones this orchestrator processes in the loop — treat them as `mine`.

    Before rewriting the stamp, classify *why* the slot went stale and emit feedback (best-effort, non-blocking) iff there has been **no commit activity** touching any path under the REQ's `**Files:**` declaration in the last hour:

    ```bash
    LAST_COMMIT_AGE_SEC=$(($(date +%s) - $(git log -1 --format=%ct -- <files-from-REQ> 2>/dev/null || echo 0)))
    if [ "$LAST_COMMIT_AGE_SEC" -gt 3600 ] || [ "$LAST_COMMIT_AGE_SEC" -eq "$(date +%s)" ]; then
        # Classify the reason using the age=<seconds> token from $STALE_SLOTS — not the raw
        # ISO heartbeat. One of:
        #   no-heartbeat      — age=unknown AND heartbeat field absent or malformed in the REQ file
        #   heartbeat-frozen  — age=<seconds> present (numeric) AND older than the stale threshold
        #   no-progress       — age=<seconds> present and under threshold but no commits on REQ's files
        # Do NOT decide reason class by comparing **Heartbeat:** calendar dates to "today".
        REASON_CLASS="<no-heartbeat|heartbeat-frozen|no-progress>"
        FINGERPRINT="stale-slot:${REASON_CLASS}"
        bash {skill-root}/lib/file-feedback.sh stale-slot \
          "$FINGERPRINT" \
          '{"req":"REQ-NNN","prior_owner":"<previous-agent-id>","reason_class":"'"$REASON_CLASS"'","last_commit_age_sec":'"$LAST_COMMIT_AGE_SEC"'}' \
          "Stale-slot reclaim: REQ-NNN (${REASON_CLASS})" \
          "REQ-NNN sat in working/ with no commit progress in over an hour before reclaim. Prior owner appears abandoned; this orchestrator is taking the slot." \
          || true
    fi
    ```

    > **JUDGMENT:** The title carries the REQ id and the reason class so an inbox skim tells you whether agents are dying silently (no-heartbeat) versus making progress without committing (no-progress). The body is one sentence — a single stale reclaim is routine; the inbox's fingerprint dedup surfaces the recurrence pattern.

  - **Return to backlog:** For each stale REQ, `git mv` it back to the backlog root, strip its ownership stamp, reset `**Status:**` to `backlog`, and commit per REQ. Stage **only** that REQ's file path — do not sweep `.do-work/`. Example:
    ```bash
    git mv {project}/.do-work/working/REQ-NNN-slug.md {project}/.do-work/REQ-NNN-slug.md
    # edit the file to strip the claim block and reset Status
    git add {project}/.do-work/REQ-NNN-slug.md
    git commit -m "chore(REQ-NNN): return stale claim to backlog"
    ```
  - **Abort:** Exit pre-flight and halt this orchestrator.

- **`stale` is empty AND `sibling` is non-empty:** fall through to `## When the Backlog is Empty` — siblings are still doing the remaining work.

- **`stale` is empty AND `sibling` is empty:** fall through to `## When the Backlog is Empty`.

### 7. Backlog emptiness check

If both `pick-req.sh` returned nothing (§5) AND the stale set is empty (§6 fallback was not triggered or returned to backlog), fall through to `## When the Backlog is Empty`.

---

## REQ Classification

Before dispatching a worker for a REQ, classify the REQ to pick the most appropriate `subagent_type` for the `Agent` tool. Classification is config-driven: the routing rules live in `config.routing` (see `agents/config.md`), not hard-coded here, so the stock skill ships portable and each user routes specialist work to whatever subagents exist on their own machine.

### Apply the routing config

Read `config.routing` — the ordered list of `{match, agent}` rules loaded at startup (see `## Load Config` in `agents/config.md`). Then:

1. Scan the REQ's `## Task`, `## Context`, `## Acceptance Criteria`, and `## Verification Steps`.
2. Walk the `routing` rules **top to bottom, first match wins**. Each rule's `match` is a signal description or keyword list; if the REQ's content fits it, the chosen `subagent_type` is that rule's `agent`, and you stop scanning.
3. If no rule matches — or `routing` is empty (the shipped default) — the `subagent_type` is `general-purpose`.

There are no hard-coded specialist agents in this section. Portable agents (`Explore` for pure exploration, `feature-dev:*` for architecture/review) are routed only when a `routing` rule names them — they are not assumed present. `agents/config.md` ships a commented example `routing` block reproducing the original specialist table; a user restores that behaviour by uncommenting it and confirming each named agent exists locally.

### Fallback rule

When no `routing` rule matches with confidence — or none is configured — **fall back to `general-purpose` silently**. Never block, never ask the user, never stop the loop on classification ambiguity. The cost of picking `general-purpose` for a specialist task is small; the cost of stalling the loop is large.

### Logging

Include the chosen `subagent_type` in the per-REQ progress line so the user can see routing decisions:

```
Starting REQ-NNN [type=general-purpose]: [title]
```

This is the only "progress" signal the orchestrator emits before the worker returns — the worker runs in a separate session and its output does not stream back. Plan accordingly.

---

## Model Selection

After classifying `subagent_type`, pick a `model` for the dispatch. Default to `sonnet` to save tokens. Escalate to `opus` only when the REQ shows signals of genuine difficulty.

### Primary signals → model

Two structural signals are read directly from the REQ header and take precedence over everything below — check them first, in order:

| Primary signal | model |
|---|---|
| REQ has a previous `status: stopped` attempt recorded in its body (retry after Sonnet failed) | `opus` |
| REQ header carries `**Size:** L` (capture sized this REQ large from its file count / layer span / criteria count) | `opus` |

If either primary signal fires, select `opus` and skip the lexical scan. The `**Size:**` field, when present, is capture's own up-front difficulty estimate — trust it over re-deriving difficulty from prose.

### Fallback signals → model (REQs without `**Size:**`)

When the REQ has **no `**Size:**` field** (legacy REQs, or capture left it off because the shape was ambiguous), fall back to scanning the REQ's `## Task`, `## Context`, and `## Acceptance Criteria` (top to bottom; first match wins). When `**Size:** S` or `**Size:** M` is present, these lexical rules still apply as a secondary check but never downgrade a `Size: L`:

| Fallback signal in REQ | model |
|---|---|
| Task touches 4+ distinct files, OR spans 3+ layers (e.g. controller + model + view + test) | `opus` |
| Task introduces new architecture: new service, new abstraction, new module boundary, schema design, or "design X" | `opus` |
| Task involves debugging across layers, race conditions, concurrency, or performance investigation | `opus` |
| `subagent_type` is `feature-dev:code-architect` or `feature-dev:code-reviewer` | `opus` |
| Anything else: single-file edits, doc/markdown updates, agent/skill/config edits, mechanical refactors, scoped bug fixes, test additions, exploration | `sonnet` |

### Fallback rule

When in doubt, **default to `sonnet`**. The worker's stopping-rules already catch failures: if Sonnet can't make tests pass after 3 attempts, it returns `status: stopped` and the orchestrator's retry path picks `opus` automatically (signal #1 above).

### Logging

The chosen `model` appears in the per-REQ announce line alongside `subagent_type` (see Step 1).

---


---

## The Loop

Repeat until the backlog is empty:

### Step 1: Claim the next REQ

#### Step 1.0 — Milestone filter (milestone mode only)

Resolve whether milestone mode is active via the tracker backend (REQ-298 Linear path; REQ-299 ops).

**Markdown backend:**

- Check whether `{project}/.do-work/state/active-milestone.md` exists.
- **File absent (non-milestone mode):** skip this step entirely — proceed to the backlog glob as written below, behaviour unchanged from REQ-114.
- **File present (milestone mode):**
  1. Read the file. Its contents are a single line such as `M1` or `M2`. Trim whitespace to obtain `<active>`.
  2. **Constrain the candidate glob** to `{project}/.do-work/REQ-M<active>-*.md` instead of `{project}/.do-work/REQ-*.md`. Sort ascending and iterate exactly as the steps below describe.
  3. **No fallback to other milestones.** If the constrained glob returns no files, the active milestone's backlog is drained — fall through to **Step 1.0a: Sibling idle-waiting** below. The orchestrator MUST NOT silently widen the glob to pick up REQs from other milestones. The deploy gate (Step 7b) is the only mechanism that advances `active-milestone.md` to the next milestone.

**Linear backend (REQ-298 path; REQ-299 ops):**

1. Call port op **`read_active_milestone`** (`agents/tracker/linear.md`) for the scoped UR Project (`do-work/{UR-id}` when `/do-work run UR-NNN`, else each active Project the run scopes). Cursor lives on Project description `<!-- do-work-milestone -->` — **not** local `active-milestone.md`. When the Project description has **no milestone marker**, the op returns `active: null` and **does not invent a milestone id**.
2. **`active` null (non-milestone mode / empty marker):** skip this step; proceed with unconstrained `list_claimable_reqs`.
3. **`active` set (e.g. `M1`):** constrain claim pool to that milestone — pass milestone scope into **`list_claimable_reqs`** and/or intersect with **`list_milestone_reqs`** for `M<active>` (status backlog / claimable). Issue markers: label `M<n>` and/or body `**Milestone:** M<n>` (see linear.md).
4. **No fallback to other milestones.** If the constrained list is empty, fall through to **Step 1.0a**. Deploy gate (Step 7b) + **`set_active_milestone`** are the only advances of the cursor.

#### Step 1.0a — Sibling idle-waiting (milestone mode, empty active-milestone backlog)

Reached only when Step 1.0 found the active milestone's backlog empty. The local orchestrator may be a *sibling* — another orchestrator could already be handling the deploy gate. Do not fall through to `## When the Backlog is Empty` yet; first check whether a gate is in progress.

1. Re-read the active cursor and capture as `<active_at_entry>`:
   - **Markdown:** re-read `{project}/.do-work/state/active-milestone.md`.
   - **Linear:** **`read_active_milestone`** again (Project description).
2. Check gate ownership via **local** `{project}/.do-work/state/gate-owner.md` (port **`write_gate_state`** home — **both backends**; never Linear). Concurrent gate ownership **serializes via this local file** even when milestone cursor content is remote (REQ-299):
   - **File absent:** No sibling has claimed the gate. This orchestrator has finished its in-flight REQ and the milestone backlog is empty, but no one has surfaced the gate yet. Fall through to `## When the Backlog is Empty` — this is the genuine drain path for a single-orchestrator run, or the loser of a race where the gate-owner will detect milestone completion on its own next worker return.
   - **File present:** Read the single line — the `<gate-owner-agent-id>`. If it equals the local `AGENT_ID`, this orchestrator already owns the gate (re-entry after a restart mid-prompt) — jump to Step 7b. Otherwise enter **idle-waiting** mode (**siblings idle on deploy gate same as markdown mode**).
3. **Idle-waiting loop.** Log exactly once:

   ```
   [<agent-id>] Idle — waiting on milestone M<active_at_entry> deploy gate (handled by <gate-owner-agent-id>).
   ```

   Then poll every 30 seconds:

   - **Markdown —** poll `{project}/.do-work/state/active-milestone.md`:
     - **File contents changed** (new milestone id, e.g. `M<active_at_entry+1>`): the gate-owner advanced. Exit idle-waiting and restart the loop at Step 1.
     - **File deleted:** the gate-owner stopped the run (user answered `n`). Exit idle-waiting → `## When the Backlog is Empty`.
     - **File unchanged AND `gate-owner.md` deleted while `active-milestone.md` is also gone:** treat as stop → empty-backlog path.
     - **File unchanged after 30 minutes:** surface stuck-owner prompt (same text as before).
     - **Otherwise:** continue polling.
   - **Linear —** poll **`read_active_milestone`** (+ still read local `gate-owner.md` — never a Linear lock):
     - **`active` changed** to a new id: gate-owner advanced. Exit idle-waiting → Step 1.
     - **`active` null / cleared** while gate-owner released: stop → empty-backlog path.
     - **Unchanged after 30 minutes:** same stuck-owner user prompt.
     - **Otherwise:** continue polling.

No commits are made while idle-waiting — the orchestrator is reading cursor + local gate state only.

**Compute your agent-id** using the rule in `## Agent Identity`:

```bash
AGENT_ID="$(hostname).$$"
```

**Scope argument:** `SCOPE` is derived from the optional `UR-NNN` argument at startup (see `## When Invoked`). Default is `any`. When `/do-work run UR-NNN` is invoked, `SCOPE=UR-NNN` and the picker filters out REQs whose `**UR:**` field does not match. The picker is also milestone-aware:

- **Markdown:** when `state/active-milestone.md` exists it constrains its glob to `REQ-M<active>-*.md` regardless of `SCOPE`.
- **Linear:** when **`read_active_milestone`** returns a non-null `active`, constrain via **`list_milestone_reqs`** / claimable scope to that `M<n>` (Issue markers), regardless of `SCOPE`.

**Pick the next claimable REQ — port op `list_claimable_reqs`:**

- **Markdown backend:** implement via `lib/pick-req.sh` (below).
- **Linear backend:** implement via **`list_claimable_reqs`** in `agents/tracker/linear.md` (project filter + backlog + **blocks** deps + footprint algorithm + Priority **DESC** (missing→2) → created_at ASC → identifier ASC + skip reasons `dep:`/`overlap:`/`scope:`/`claim:`). When milestone mode is active, apply port op **`list_milestone_reqs`** membership filter for the active M (REQ-298 path; REQ-299 ops). Do **not** run `pick-req.sh` as the Linear store. On empty claimable list, map the op’s skip-reason lines with the same precedence as `drain-classify.sh`: **`overlap-blocked` > `deps-blocked` > `scope-blocked` > `truly-empty`**. No Linear-aware bash required.

```bash
# markdown only — linear: call list_claimable_reqs (linear.md) instead
PICK_STDERR=$(mktemp)
REQ_PATH=$(bash {skill-root}/lib/pick-req.sh "$SCOPE" "$AGENT_ID" 2>"$PICK_STDERR")
```

`pick-req.sh` (REQ-145) applies the full scope / dependency / footprint-overlap filter in one pass and prints the absolute path of the first claimable REQ to stdout (exit 0), or nothing (exit 1) if no candidate survives. Its stderr carries one `<reason>:<detail>` line per rejected candidate.

**If `pick-req.sh` returns empty (exit 1) — classify and branch:**

```bash
CLASSIFICATION=$(cat "$PICK_STDERR" | bash {skill-root}/lib/drain-classify.sh)
rm -f "$PICK_STDERR"
```

`drain-classify.sh` (REQ-152) reads the stderr lines and emits one of four labels, precedence `overlap-blocked > deps-blocked > scope-blocked > truly-empty`:

| Classification | Meaning | Action |
|---|---|---|
| `overlap-blocked` | At least one candidate blocked by footprint overlap with a sibling slot | Idle-wait (see below) |
| `deps-blocked` | All survivors blocked on unsatisfied dependencies | Idle-wait (see below) |
| `scope-blocked` | All candidates excluded by the `<scope>` filter | Idle-wait (see below) — a new capture or a scope change can add eligible REQs |
| `truly-empty` | No candidates considered at all (backlog drained for this picker view) | Fall through to `## When the Backlog is Empty` |

**Idle-wait loop** (entered on `overlap-blocked`, `deps-blocked`, or `scope-blocked`). Log the entry classification once, then poll every **30 seconds**, max **30 minutes**:

```bash
ELAPSED=0
while [ "$ELAPSED" -lt 1800 ]; do
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    # Refresh heartbeat on a still-owned slot, if any. No-op when CURRENT_SLOT is unset.
    if [ -n "${CURRENT_SLOT:-}" ] && [ -e "$CURRENT_SLOT" ]; then
        bash {skill-root}/lib/heartbeat.sh "$CURRENT_SLOT" >/dev/null 2>&1 || true
    fi
    # Re-pick.
    REQ_PATH=$(bash {skill-root}/lib/pick-req.sh "$SCOPE" "$AGENT_ID" 2>"$PICK_STDERR")
    if [ -n "$REQ_PATH" ]; then
        break  # back to the claim step
    fi
done
```

On 30-minute timeout, **run deadlock detection before falling back to the generic prompt**:

```bash
DEADLOCK_OUT=$(bash {skill-root}/lib/deadlock-check.sh)
```

`deadlock-check.sh` (REQ-156) prints empty stdout when no deadlock is detected and a structured report otherwise. Branch on its output:

**If `DEADLOCK_OUT` is empty (no deadlock):** Surface the generic prompt to the user: `Claim blocked (<classification>) — still no claimable REQ after 30 min. Continue waiting, or abort?` Act on user response.

**If `DEADLOCK_OUT` is non-empty (deadlock detected):**

1. Parse the report. Extract `signal`, `fingerprint`, `diagnosis`, `live-slots`, `stale-slots`, `backlog-size`, `last-commit-age`.
2. **Ensure `state/` exists.** Run `mkdir -p {project}/.do-work/state` before any lock acquisition or state write. This is defensive — installs created before REQ-170 may not have `state/`, and orchestrators must not crash on a missing directory.
3. **Acquire the surfacing lock** via `flock -n` on `.do-work/state/feedback.lock` so only one orchestrator writes `deadlock.md` and surfaces to the user. Siblings that fail to acquire the lock skip steps 4–6 and exit the idle-wait loop quietly (they will pick up via their own timeout if the deadlock persists).
4. **Lock-holder only:** write `{project}/.do-work/state/deadlock.md` containing the full `deadlock-check.sh` output plus a timestamp. This file is the cross-process signal that the deadlock has been surfaced.
5. **Lock-holder only:** emit feedback by calling `bash {skill-root}/lib/file-feedback.sh deadlock "<fingerprint>" '<context-json>'` where `<context-json>` is a single-line JSON object with `signal`, `live-slots`, `stale-slots`, `backlog-size`, `last-commit-age`, `classification` (the idle-wait entry classification). The script handles its own enable/disable, deduplication, and lock-on-feedback.lock — call it best-effort and continue regardless of exit code.
6. **Lock-holder only — surface to the user**, gated on standalone mode only (recovery prompts are workflow-critical and must not depend on `config.next_steps.enabled`):
   - **If standalone** (not running as a delegate inside go): use the `AskUserQuestion` tool with options:
     1. **"Reset stale slots"** — return any slots listed in `stale-slots` to the backlog (per the Pre-flight stale-slot return path).
     2. **"Show situation room"** — print the suggestion `Run /do-work status` and exit cleanly.
     3. **"Unblock a REQ"** — ask which REQ id; print `Run /do-work unblock REQ-NNN` and exit cleanly.
     4. **"Abort"** — exit this orchestrator cleanly.
   - **If delegate** (running inside go): print the diagnosis block (the `deadlock-check.sh` output plus a one-line summary) and exit cleanly. Do not prompt.

> **JUDGMENT:** The deadlock diagnosis must distinguish a stuck deadlock from a slow-but-live backlog. `deadlock-check.sh` returning a report is strong evidence (no commits in 5 min OR all slots stale OR runtime cycle) — trust it and surface. Empty output means heartbeats are still advancing or commits are landing; in that case the generic "continue waiting?" prompt is correct. Never silently keep idling past the 30-minute mark — either the deadlock path or the user prompt must fire.

**If pick returns a candidate — claim via port op `claim_req`:**

- **Markdown backend:** `lib/claim-req.sh` (below).
- **Linear backend:** **`claim_req`** in `agents/tracker/linear.md` — optimistic re-read; set `status_map.in_progress`; post `<!-- do-work-claim -->` (config `agent_claim_marker`) comment with `agent_id` / timestamps / `status: active`; **never** change assignee. Race lost → `concurrent-conflict` (retry list/claim or stop; resume allowed for owner). Mid-flight MCP death after claim → **leave claimed**.

```bash
# markdown only — linear: call claim_req (linear.md) with issue id + AGENT_ID
COMMIT_HASH=$(bash {skill-root}/lib/claim-req.sh "$REQ_PATH" "$AGENT_ID")
```

`claim-req.sh` (REQ-146) performs the `git mv` → stamp insertion → `Status: in-progress` update → stage → commit sequence atomically and prints the commit short hash to stdout. On failure it writes a diagnostic to stderr and exits non-zero:

- **Exit 2 (`Claim lost: REQ-NNN`)** — a sibling won the race on this exact file. Re-run `pick-req.sh` from the top of Step 1 (the lost candidate is now in `working/` and will be excluded by the overlap filter). Linear equivalent: re-run **`list_claimable_reqs`** then **`claim_req`**.
- **Any other non-zero exit** — log the stderr diagnostic and re-run pick after a 2 s backoff. After 3 consecutive non-race failures, stop and report to the user.

After a successful claim (`claim-req.sh` or Linear **`claim_req`**):

**Announce:**

```
[<agent-id>] [scope=<UR-NNN|any>] Starting REQ-NNN [type=<subagent_type>, model=<model>, isolation=<mode>]: [title]
```

### Step 2: Dispatch the worker subagent

Read all of [agents/run-worker.md](run-worker.md) — that is the worker's full instruction set. You will pass it inline to the dispatched subagent.

Determine `subagent_type` using the rules in `## REQ Classification` above. Default to `general-purpose`.
Determine `model` using the rules in `## Model Selection` above. Default to `sonnet`.

#### Step 2a: Criteria provenance note

Read the REQ header's `**Criteria approved:**` value when present, but do not block worker dispatch based on it. `agent-drafted` is provenance, not a pre-run approval requirement. If a REQ exists in the backlog and its dependencies, footprint, scope, and policy gates allow it to run, dispatch the worker.

Unexpected ambiguity still stops the run: if the acceptance criteria are missing, contradictory, impossible to verify, or become invalid during implementation, the worker must return `status: stopped` with `reason: ambiguous-criteria` or `verification-failing`. Do not ask for approval merely because criteria were generated by capture.

Identify the **prior-REQ archived paths** for the same UR — these provide the worker context about what has already been built:

1. Read the REQ's `**UR:**` field
2. Glob `{project}/.do-work/archive/REQ-*.md`
3. For each archived REQ, read its `**UR:**` field and keep only those matching the current UR
4. Pass the resulting absolute paths to the worker

Dispatch via the `Agent` tool. Pass the worker **five named inputs** — REQ path, UR path, prior-REQ paths, the project context-pack path (from Pre-flight Step 2b), and the resolved skill-root (from Pre-flight Step 2a) — plus the run-worker.md instructions inline. Substitute the concrete `$SKILL_ROOT` value for `{skill-root}` in the instructions you paste so the worker's `{skill-root}/lib/...` calls resolve to a real path:

```
Agent(
  description: "Run worker for REQ-NNN",
  subagent_type: <classified type>,
  model: <selected model>,
  prompt: """
You are the Run Worker. Follow the instructions below exactly. Prefer the inputs given; bounded exploration of files your implementation genuinely touches is allowed (see your When Invoked rule). Do not load other REQs or URs.

<inputs>
REQ:         {absolute path to working/REQ-NNN-slug.md}
UR:          {absolute path to user-requests/UR-NNN/input.md}
Prior REQs from this UR (may be empty):
  - {absolute path}
  - {absolute path}
Context pack: {absolute path to .do-work/state/context-pack.md}
Skill root:   {resolved absolute $SKILL_ROOT — the directory containing lib/; your {skill-root}/lib/... calls use this value}
</inputs>

<instructions>
{full contents of agents/run-worker.md verbatim, with {skill-root} replaced by the resolved $SKILL_ROOT}
</instructions>

Return your structured YAML report as your final message. Nothing else.
"""
)
```

The worker performs: create worktree → read REQ → read context → TDD red → implement → verify green → run affected tests → check acceptance criteria → execute verification steps → commit on feature branch → return YAML, all in its own session. **The worker does NOT merge, archive, or tear down its worktree** — those are the orchestrator's Step 4 (Integrate) responsibilities.

The worker's stdout does not stream back to the orchestrator — only its final structured report is visible. Do not poll, do not babysit. Wait for the dispatch to return.

### Step 3: Process the worker report

The worker's final message is a fenced YAML block matching the schema defined in [agents/run-worker.md](run-worker.md) `## Return Report`. Parse it. Branch on `status`:

| `status` | Action |
|---|---|
| `done` | Capture `commit` hash and `outputs`. Continue to Step 4 (Integrate). |
| `stopped` | The worker hit a stopper (`reason` enum: `tests-failing`, `verification-failing`, `missing-creds`, `ambiguous-criteria`, `scope-creep`, `dependency-missing`, `concurrent-conflict`, `unknown-error`). Continue to Step 5 (Recover) — handle per `## Stopping Rules`. Skip Step 4. **Workers never report a human-wait stopper** — there is no `awaiting-human-verification` reason. Inherently non-executable verification steps are *deferred* by the worker (returned in `deferred_checks:`) and are recorded as advisory manual checks during the normal archive path. |
| `failed` | The worker crashed before completing. Treat as `stopped` with `reason: unknown-error`. |

If the worker's report is missing or unparseable, treat as `status: failed` with `reason: unknown-error` and surface the raw output to the user.

If the worker reports `status: stopped` with `reason: verification-failing`, parse `last_good_step`, `failed_step`, and `checkpoint_log` from the report. Include the localized failure in the user-facing stopper report, e.g. `Verification failed at step <failed_step>; last good step was <last_good_step>; handoff: <handoff-or-unknown>.`

If the worker reports `status: done`, validate acceptance evidence before Step 4 integration:

```bash
# markdown: path is working/REQ file. linear: pass issue id / exported body via port read_req — same evidence rules; do not invent a second store.
bash {skill-root}/lib/check-acceptance-evidence.sh {project}/.do-work/working/REQ-NNN-slug.md <worker-report-yml>
```

If validation fails, treat the result as `status: stopped`, `reason: verification-failing`, surface the validator diagnostics, and do not merge, write closure proof, review, or archive. **Under Linear: do not call `archive_req`** — issue stays `in_progress`/`stopped` with claim protocol intact (optional `set_req_status` → stopped + `append_run_note`). This gate extends the checkpoint/closure-proof model; it does not replace `closure_proof`.

**Review gate (`review.required` — REQ-295):**

1. Read `review.required` from config (default **`true`**).
2. When **`review.required: true`**: after acceptance evidence validation passes, run the post-build review gate **before** Step 4 integration. Worker says done is not final until evidence + review both pass. **Failed review must not call `archive_req`** (Linear) and must not move/archive the markdown REQ.
3. When **`review.required: false`**: skip review dispatch; proceed to Step 4 only if evidence (and policy) gates passed. Still never archive on failed evidence.

**Review is dispatched as a fresh, independent subagent — never followed inline in the orchestrator's own context.** The orchestrator that wants the run to finish must not grade its own work; the reviewer runs cold, with no run history, seeing only the artifacts you hand it.

Before dispatching review, run deterministic policy checks using changed files, command evidence, and REQ metadata:

```bash
bash {skill-root}/lib/check-policy.sh \
  --project {project} \
  --files <changed-files-list> \
  --commands <worker-command-log> \
  --req {project}/.do-work/working/REQ-NNN-slug.md
```

Capture both the exit code and stdout/stderr — they are an input to the review dispatch.

- **Exit `1`:** treat the result as `status: stopped`, `reason: policy-blocked`, surface the blocked path or blocked command diagnostics, leave the REQ in `working/`, and do not review, merge, archive, or write completion state.
- **Exit `2`:** a `risk.require_review` signal fired. Continue into review and pass the `review_required` diagnostics as mandatory review context. This exit code is also the trigger for **adversarial mode** (below).
- **Exit `0`:** continue into review normally.

The helper reads `security.blocked_paths`, `security.blocked_commands`, and `risk.require_review` from `.do-work/config.yml`.

#### 3a. Dispatch the review subagent

Read all of [agents/review.md](review.md) — that is the reviewer's full instruction set. Pass it inline to the dispatched subagent, exactly as Step 2 does for the worker. The reviewer receives **five named inputs and nothing else** — no run narrative, no prior-REQ context, no memory of the worker's reasoning:

```
Agent(
  description: "Post-build review for REQ-NNN",  # or ENG-123 under Linear
  subagent_type: general-purpose,
  model: <model>,
  prompt: """
You are the Review agent. Follow the instructions below exactly. You run as an independent subagent with no run history — judge only the artifacts handed to you.

<inputs>
# markdown:
Working REQ:    {absolute path to working/REQ-NNN-slug.md}
UR:             {absolute path to user-requests/UR-NNN/input.md}
# linear (instead of Working REQ path):
# Issue id:     {ENG-123 — load via read_req; no .do-work/working/ as store}
# UR context:   {UR-NNN / Project do-work/UR-NNN when known}
Worker report:  {the worker's returned YAML report, inline}
Diff / commit:  {the implementation diff, or the feature-branch commit reference}
Policy check:   {the captured check-policy.sh output and exit code}
</inputs>

<instructions>
{full contents of agents/review.md verbatim}
</instructions>

Return your structured YAML review report as your final message. Nothing else.
"""
)
```

Parse the reviewer's returned YAML (schema in [agents/review.md](review.md) `## Output`). Branch on its `status`:

- **`status: passed`:** continue to Step 4 (Integrate).
- **`status: failed`:** treat the result as `status: stopped`, `reason: review-failed`, surface the review `findings`, leave the REQ in `working/` (markdown) **or** leave the Linear issue claimed (`in_progress`/`stopped` + active claim — **do not call `archive_req`**), and do not merge, write closure proof, archive, or record completion. Optional Linear: `set_req_status` → stopped + `append_run_note` with `result: stopped:review-failed` / `review: failed`.

#### 3b. Adversarial mode (config-gated, risk-triggered)

Read `review.adversarial` (loaded at startup; default `false`).

- **`review.adversarial` is `false` (default), OR `check-policy.sh` exited `0`:** dispatch exactly **one** reviewer as in §3a. This is the shipped path.
- **`review.adversarial` is `true` AND `check-policy.sh` exited `2`:** dispatch **three** reviewers in parallel, each scoped to a distinct lens — **correctness**, **security**, **regression**. Use the same §3a dispatch shape per reviewer, adding a line to the prompt naming the lens (e.g. `Review lens: security — weight your findings toward this lens; still report blockers you see outside it.`). Aggregate the three returned reports into one verdict:
  1. **Majority gate:** the gate passes only when at least **2 of 3** reviewers return `status: passed`.
  2. **Blocker override:** any `severity: blocker` finding from **any** reviewer fails the gate regardless of the majority outcome. Blockers are never out-voted.
  3. On failure (majority not met OR any blocker present), apply the same handling as a single failed review: `status: stopped`, `reason: review-failed`, surface the union of all three reviewers' `findings`, leave the REQ in `working/`.

  Default stays single-reviewer to contain token cost until run-level budget enforcement (REQ-226) exists.

### Step 3b: Run Ledger

Collect ledger inputs while the run progresses: REQ id (or Linear issue id), agent id, selected model, branch, started and ended timestamps, command evidence, test evidence, changed files, result, cost estimate or budget note, review outcome, and derived proof status.

**Backend branch for run notes (REQ-294):**

| Backend | Authoritative note | Optional local file |
|---------|--------------------|---------------------|
| **markdown** | When `ledger.enabled`: `lib/run-ledger.sh` → `.do-work/runs/RUN-NNN.yml` (`append_run_note` in `markdown.md`) | same file is the store |
| **linear** | **`append_run_note`** on the Issue (YAML-fenced comment per `linear.md`) | If `ledger.enabled: true`, **may also** write `RUN-NNN.yml` via `lib/run-ledger.sh` — **telemetry only**, not a second work-item store. Retro prefers Linear comments; falls back to local runs if comments unavailable |

When `ledger.enabled` is true (either backend), record one append-only local run ledger entry per worker attempt under `{project}/.do-work/runs/RUN-NNN.yml` using `lib/run-ledger.sh` — under Linear this is the optional telemetry path above, **in addition to** `append_run_note`.

Finalize the (local) ledger after the attempt reaches a terminal outcome:

```bash
bash {skill-root}/lib/run-ledger.sh \
  --project {project} \
  --req <working-or-archived-REQ-path-or-linear-issue-id> \
  --agent <agent-id> \
  --model <selected-model> \
  --branch <branch-name> \
  --started <iso8601> \
  --ended <iso8601> \
  --result <done|stopped:reason|failed> \
  --review <passed|failed|not-run> \
  --cost <estimate-or-budget-note> \
  --cost-estimate <numeric-dollar-estimate-for-this-attempt> \
  --pr <pr-url-when-delivery-mode-pr-else-omit> \
  --commands <command-evidence-list> \
  --tests <test-evidence-list> \
  --changed-files <changed-files-list>
```

For stopped workers, write the ledger (and Linear **`append_run_note`** when backend is linear) before returning control to the user, with `result: stopped:<reason>` and the best available evidence lists. For policy-blocked or acceptance-evidence failures before review, use `review: not-run`. If `ledger.enabled` is false, skip **local** ledger creation; under Linear still prefer **`append_run_note`** when the attempt warrants a durable note.

When `deferred_checks:` is non-empty, still write `result: done` with the normal review and evidence fields. Delivery happened and all automated gates passed; any human/device follow-up is advisory data in the archived REQ, not a distinct ledger result.

The worker also reports `milestone_complete` (boolean) and `milestone` (id when true). Step 7b uses these.

#### Step 3b.1: Budget gate (enforcement hook)

Run this **immediately after** the ledger write above, on every worker attempt — serial mode here, and at the same point inside the merge queue's Stage B for parallel mode (P3 reuses Step 3b verbatim; the gate rides along).

**Inert unless armed.** If the effective budget (resolved at startup) is empty/unset, **skip this gate entirely** — never sum, never stop. This preserves today's unlimited behaviour with zero overhead. Likewise skip when `ledger.enabled` is false (no ledger to sum).

When the budget is non-empty:

1. Sum cumulative estimated spend for this run from the ledger:
   ```bash
   SPENT="$(bash {skill-root}/lib/run-ledger.sh --sum-run {project}/.do-work/runs)"
   ```
2. Compare `SPENT` against the effective `BUDGET` (numeric, same dollar unit):
   - **`SPENT < BUDGET` ⇒ under budget.** Continue normally to Step 4 (Integrate) and loop.
   - **`SPENT >= BUDGET` ⇒ budget exhausted.** Do **not** abandon the current attempt. **Finish the current REQ's integration first** (complete Step 4 fully — merge/archive/teardown/commit, or the PR delivery sequence — so the loop never stops mid-merge or mid-archive). Then, at the REQ boundary (where Step 8 would normally claim the next REQ), **stop gracefully** instead of looping: emit the **budget-stop report** and end the run.

> **JUDGMENT:** The gate trips *after* the attempt that crossed the line, never mid-attempt. An in-flight integration always completes — abandoning a half-merged REQ would corrupt state, which is a worse failure than a small budget overshoot. The estimate is tier-weighted (see budget unit above), so the report names spend as an estimate, not a metered total.

**Budget-stop report** (print before ending; under `next_steps.enabled` + standalone, surface via `AskUserQuestion` like a stopper, else print and stop):

```
Budget reached — stopping at REQ boundary.

Estimated spend: $<SPENT> / budget $<BUDGET>   (tier-weighted estimate, not a metered bill)
REQs completed this run: <N>
REQs remaining in backlog: <M>
Last integrated: REQ-NNN

Re-run with a higher --budget (or raise cost.budget) to continue.
```

The in-parallel variant is identical: when the gate trips inside Stage B, finish that report's Step 4 integration, then **stop admitting new reports to Stage B and stop refilling the window (P2)** — let live workers drain naturally (their integrations still complete), then emit the budget-stop report. No worker is killed mid-attempt; the window simply stops being refilled past the budget boundary.

### Step 4: Integrate (worker = code, orchestrator = state)

> **JUDGMENT:** The integration sequence below is the orchestrator's responsibility BECAUSE workers run in isolated worktrees. The worker has committed implementation files to `req/REQ-NNN`; the orchestrator now merges that branch into the base branch, archives the REQ, tears down the worktree, and commits the metadata change. This is the only place where `.do-work/` lifecycle writes happen.

Reached only when `status: done` and both acceptance evidence validation and post-build review passed.

**Delivery mode dispatch.** Read `config.delivery.mode` (default `merge`):

- **`merge`** (default) — execute substeps **4a → 4b → 4c → 4d** below, in order; each must succeed before the next. This is the historical local-merge behaviour, unchanged.
- **`pr`** — skip 4a–4d entirely and execute the **PR delivery** sequence (`#### 4-pr`) instead. PR mode never runs the local merge.

The guards in 4b and 4-pr.4 (path-unit closure and non-empty closure proof) and the closure-proof model are identical in both delivery modes — only the delivery vehicle differs. Whichever path runs, proceed to Step 7 when it completes.

#### 4a. Merge the feature branch

From the orchestrator's checkout (the main working tree, NOT the worktree). Branch name is backend-specific:

| Backend | Feature branch | Merge subject |
|---------|----------------|---------------|
| **markdown** | `req/REQ-NNN` | `merge(REQ-NNN): integrate` |
| **linear** | `req/<sanitized-linear-id>` (e.g. `req/ENG-123` — same string worker created via linear.md Branch sanitize) | `merge(ENG-123): integrate` |

```bash
# markdown:
git merge --no-ff req/REQ-NNN -m "merge(REQ-NNN): integrate"
# linear (example):
# git merge --no-ff req/ENG-123 -m "merge(ENG-123): integrate"
```

On text-level conflict (any file contains `<<<<<<<`):

1. `git merge --abort`.
2. Apply the 5-retry exponential-backoff policy (5s / 15s / 30s / 60s waits):
   - `git pull --rebase origin <base-branch>` (if remote exists; otherwise local fetch).
   - Re-attempt the merge.
3. On the 5th failure, leave the feature branch alive (do NOT delete it), transition the REQ to `**Status:** stopped`, `**Reason:** concurrent-conflict` (handled in the Recover step below), and surface to the user. The branch can be resumed via `/do-work resume REQ-NNN` (markdown) or `/do-work resume ENG-123` (linear) which checks out the worktree and re-runs the worker on the same branch. **Same stopper enum; resume allowed.**

#### 4b. Archive the REQ file

Read the worker's YAML report's `outputs:` list and `closure_proof` value.

**Linear backend (`tracker.backend: linear` — REQ-294/295):** do **not** rewrite/move local `.do-work/working/` or `.do-work/archive/` REQ files as the work-item store. Execute **`archive_req`** from `agents/tracker/linear.md` on the Linear issue id **only when every pre-archive gate passed**:

1. **Hard gates (any failure → do not call `archive_req`):** path-unit Entry/Terminal when present; non-empty `closure_proof`; acceptance-evidence passed; when `review.required: true`, review `status: passed`. Failed review or failed acceptance-evidence leaves the issue `in_progress`/`stopped` with **claim protocol intact** (no `status: released`, no `status_map.done`).
2. When gates pass: `archive_req` sets workflow → `status_map.done`, writes `**Closure proof:**` + `## Outputs` on the Issue, posts claim `status: released`.
3. On Linear MCP failure mid-archive: **leave claimed** if claim not yet released; stop for resume/unblock; never silent markdown archive.
4. Optional: `append_run_note` for the done attempt if not already written in Step 3b (YAML-fenced ledger fields as Issue comment).
5. Skip the markdown file rewrite/move/integrity-script steps below. Continue to 4c (worktree teardown using the **Linear** branch/worktree paths from 4a/W2) and any local git metadata commit that does not invent a second work-item store.

**Markdown backend** (default): rewrite the REQ file in place under `.do-work/working/REQ-NNN-slug.md`:

0. **Path-unit closure guard.** Before any archive mutation, read `**Entry point:**` and `**Terminal state:**` from the REQ file. If either field is present, both must be present and non-empty. If a path-unit is missing either value, do not archive it. Transition the REQ to `**Status:** stopped`, add `**Reason:** path-unit-incomplete`, and surface: `REQ-NNN cannot close: path-unit requires non-empty Entry point and Terminal state.` Non-path REQs with both fields absent are unaffected.
1. Require non-empty `closure_proof` when the worker returned `status: done`. If it is missing or empty, transition the REQ to `**Status:** stopped`, add `**Reason:** missing-closure-proof`, and do not archive.
2. Strip the ownership stamp (`<!-- claimed-start --> … <!-- claimed-end -->`).
3. Update `**Status:**` to `done`.
4. Write the worker's `closure_proof` value into `**Closure proof:**`. If the header is absent, insert it before `**Files:**`.
5. Append a `## Outputs` section based on the `outputs:` array from the worker's YAML report. One bullet per entry: `- <path> — <description>`.
5a. **Manual checks (advisory).** If the worker report's `deferred_checks:` list is non-empty OR the REQ already carries a `## Manual checks (advisory)` section, consolidate all deferred items into that section before archiving. Create the section if absent. Keep existing bullets, and add one unchecked bullet per worker item: `- [ ] <step text> (<category>: <reason>)`. This section is advisory only; it never blocks archive. If any consolidated item carries `category: suite-not-run`, additionally write a `**Suite:** not-run` header field on the archived REQ (placed with the other header fields, below `**Closure proof:**`). This marker makes `lib/derive-status.sh` derive the REQ `unproven` even though it archives as `done` — archive and merge are unaffected; only the derived proof view changes. Human/device/environment deferrals never carry `category: suite-not-run` and never produce this marker.
5b. **Archive-integrity gate.** With the working file now fully rewritten, run the deterministic guardrail on it before the move:
   ```bash
   bash {skill-root}/lib/check-archive-integrity.sh {project}/.do-work/working/REQ-NNN-slug.md
   ```
   It asserts the final on-disk state is internally consistent: `**Status:** done`, a non-empty `**Closure proof:**`, and zero unchecked `- [ ]` items inside `## Acceptance Criteria`. **Exit non-zero ⇒ do not archive:** transition the REQ to `**Status:** stopped`, add `**Reason:** archive-integrity`, surface the script's stderr diagnostics, and leave the file in `working/`. This is the persistence-boundary enforcement of the invariants steps 3–4 and the worker's acceptance-criteria ticking (`agents/run-worker.md` Step "Mark each `- [x]`") are supposed to satisfy — those are prose an LLM can silently skip; this gate cannot be skipped. (`archive-integrity` is an orchestrator-assigned reason like `path-unit-incomplete` and `missing-closure-proof`; it is not a worker reason.)
6. Move the file to `archive/`:
   ```bash
   mv {project}/.do-work/working/REQ-NNN-slug.md {project}/.do-work/archive/REQ-NNN-slug.md
   ```

#### 4c. Tear down the worktree

Use the same branch and worktree paths the worker created:

```bash
# markdown:
git worktree remove {project}/.worktrees/req-NNN
git branch -d req/REQ-NNN   # safe delete; refuses if not fully merged
# linear (example ENG-123 → sanitized slug eng-123):
# git worktree remove {project}/.worktrees/req-eng-123
# git branch -d req/ENG-123
```

If `git branch -d` refuses (the merge somehow incomplete), surface to the user; leave the branch alive for manual investigation. Never use `-D`.

#### 4d. Commit the metadata change

If `.do-work/` is tracked in this project, stage only the archive move and commit.

For the **archive** path (4b):

```bash
git add {project}/.do-work/archive/REQ-NNN-slug.md
git add {project}/.do-work/working/REQ-NNN-slug.md   # stages the removal
git commit -m "chore(REQ-NNN): archive

REQ: {project}/.do-work/archive/REQ-NNN-slug.md
UR: {project}/.do-work/user-requests/UR-NNN/input.md"
```

If `.do-work/` is gitignored: skip this commit silently. The move is filesystem-only, and the worker's `feat(REQ-NNN): ...` commit (now on the base branch via the merge) is the authoritative record.

Proceed to Step 7.

#### 4-pr. PR delivery (delivery.mode: pr)

Runs *instead of* 4a–4d when `config.delivery.mode` is `pr`. The closure-proof model is unchanged — evidence still gates archive; the PR is the delivery vehicle, not the proof. Execute these substeps in order; each must succeed before the next.

**4-pr.0 Precondition — remote + `gh` (never a silent merge fallback).** Before any push, verify both:

```bash
git remote get-url origin    # a remote must be configured
gh auth status               # the gh CLI must be installed and authenticated
```

If a remote is missing **or** `gh` is absent/unauthenticated, **stop**: do NOT merge, do NOT push, do NOT archive. Leave the REQ in `working/` (and the branch alive), transition it to `**Status:** stopped`, `**Reason:** missing-creds`, and surface to the user per `## Stopping Rules`. PR mode must **never** silently fall back to `merge` mode.

**4-pr.1 Push the REQ branch.** With the precondition met, push the worker's branch to the remote:

```bash
git push -u origin req/REQ-NNN
```

**4-pr.2 Determine the PR target by granularity.** Read `config.delivery.pr.granularity` (default `req`):

- **`req`** (default) — open the PR immediately, from `req/REQ-NNN` into the base branch. Continue to 4-pr.3.
- **`ur`** — do NOT open a per-REQ PR. Instead accumulate this REQ onto the UR's shared integration branch:
  1. Resolve the UR id from the REQ's `**UR:**` field → integration branch `ur/UR-NNN`.
  2. If `ur/UR-NNN` does not yet exist on the remote, create it from the base branch and push it.
  3. Merge `req/REQ-NNN` into `ur/UR-NNN` (`git merge --no-ff`, applying the same conflict/retry policy as 4a) and push `ur/UR-NNN`.
  4. Archive this REQ now (4-pr.4) recording the `ur/UR-NNN` branch, but **defer PR creation**: the single PR opens at UR drain. After the last REQ for this UR archives and the UR's backlog is empty (see `## When the Backlog is Empty` drain check), open one PR from `ur/UR-NNN` into the base branch using the same title/body shape as 4-pr.3 (title/body keyed to the UR rather than a single REQ; the body links the UR and lists each integrated REQ). Record that PR's URL on the UR. Then continue past 4-pr.5 to Step 7.

**4-pr.3 Open the PR (`req` granularity, or the single UR-drain PR).**

```bash
gh pr create \
  --base <base-branch> \
  --head req/REQ-NNN \
  --title "<REQ title>" \
  --body "<body — see below>"
```

PR body mirrors the commit convention (see SKILL.md / README `## Commit Convention`) and ends with the standard generated-with footer:

```
REQ: .do-work/archive/REQ-NNN-slug.md
UR: .do-work/user-requests/UR-NNN/input.md
Output: <primary output path>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Capture the PR URL printed by `gh pr create`.

**4-pr.4 Archive the REQ.** Apply the **same** archive logic as 4b (path-unit closure guard, non-empty closure-proof requirement, strip ownership stamp, set `**Status:** done`, write `**Closure proof:**`, append `## Outputs`, consolidate `deferred_checks:` or an existing `## Manual checks (advisory)` section into advisory bullets — including the `**Suite:** not-run` header write from 4b step 5a when a consolidated item carries `category: suite-not-run` —, **archive-integrity gate (4b step 5b — `bash {skill-root}/lib/check-archive-integrity.sh` on the rewritten file; non-zero ⇒ stop with `**Reason:** archive-integrity`, do not archive)**, `mv` to `archive/`) — with one addition: append the PR URL to `## Outputs` as a bullet, e.g. `- PR — <pr-url>`. For `ur` granularity where the PR opens later, record the integration branch in `## Outputs` now and append the PR URL bullet when the UR-drain PR opens.

**4-pr.5 Tear down the worktree — but keep the branch.** Remove the worktree; do **not** delete the branch (the PR owns it):

```bash
git worktree remove {project}/.worktrees/req-NNN
# NO `git branch -d` — the open PR owns req/REQ-NNN (or it lives on in ur/UR-NNN).
```

**4-pr.6 Record the PR URL in the ledger.** When `ledger.enabled` is true, pass the captured URL to the ledger via `--pr` (see Step 3b) so the run record's `pr_url` field carries it. If the metadata commit (4d-equivalent) runs for a tracked `.do-work/`, stage and commit the archive move per 4d — `chore(REQ-NNN): archive`.

Proceed to Step 7.

### Step 5: Recover (on stopper)

Reached only when `status: stopped` or `failed`. The REQ file is still in `working/` (worker didn't move it). Handle per `## Stopping Rules`.

For `reason: concurrent-conflict` after Step 4a's 5-retry exhaustion: leave the feature branch alive; update the REQ to `**Status:** stopped` and `**Reason:** concurrent-conflict`. `/do-work resume REQ-NNN` is the recovery path.

For other stoppers: surface to the user via `AskUserQuestion` (existing stopping-rules behaviour).

Do not proceed to Step 7.

### Step 6 — (reserved; removed in an earlier revision)

### Step 7: Report progress

```
✅ REQ-NNN complete: [title]
   Output: [path]
   Commit: [short hash]

Remaining in backlog: N
```

### Step 7b: Milestone deploy-gate check (milestone mode only)

The deploy-gate prompt is **owned by the orchestrator, not the worker**. The worker has no user-interaction surface and is explicitly forbidden from auto-confirming any gate. Under parallelism, only **one** orchestrator surfaces the prompt to the user — the first to detect milestone completion *and* observe a fully drained milestone backlog.

**Is milestone mode active?**

- **Markdown:** `{project}/.do-work/state/active-milestone.md` exists.
- **Linear (REQ-298/299):** **`read_active_milestone`** returns non-null `active` (Project description `<!-- do-work-milestone -->`). Empty / missing marker → null (not-in-milestone; does not invent a milestone id). Do **not** require local `active-milestone.md`.

If not in milestone mode, the worker typically reports `milestone_complete: false` and the orchestrator simply continues until the backlog is empty. Skip the rest of this step.

If milestone mode is active:

1. Read `milestone_complete` from the worker's most recent return report.
2. **Markdown:** if `milestone_complete` is `false`, continue the loop normally — claim the next REQ. If `true`, run the **first-to-detect drain check** before showing any prompt.
3. **Linear:** if `milestone_complete` is `true`, **or** after a successful archive **`list_milestone_reqs`** for active M with status `backlog` is empty (and claimable for that M is empty), run the drain check. Worker `milestone_complete` alone is not required when the orchestrator can prove the M backlog is empty via port ops. First-to-detect still means *first whose drain check passes* and who claims the local gate.

#### Step 7b.1 — Drain confirmation

Let `<active>` be:

- **Markdown:** trimmed contents of `{project}/.do-work/state/active-milestone.md`.
- **Linear:** `active` from **`read_active_milestone`**.

**Markdown drain:**

1. Glob `{project}/.do-work/REQ-M<active>-*.md` (backlog root). **Must return zero files.** If non-zero, a sibling can still claim more work in this milestone — abort the gate detection, continue the loop normally (Step 8). Some other return-report will trigger the gate later.
2. Glob `{project}/.do-work/working/REQ-M<active>-*.md`. For each file, read its `<!-- claimed-start -->` ownership stamp:
   - Slots whose `**Claimed by:**` equals the local `AGENT_ID` are expected — at most one (the just-archived REQ's transient state) and not a blocker.
   - Any slot owned by a **different** agent-id is a sibling's in-flight REQ for the same milestone. The milestone is not yet drained.
3. **If sibling slots are present**, poll every 30 seconds, up to 30 minutes:
   - Re-run the working/ glob and re-classify on each tick.
   - When no sibling-owned slots remain, the milestone is drained — proceed to Step 7b.2.
   - On 30-minute timeout, surface to the user: `Milestone M<active> appears stuck — sibling slot(s) <list of agent-ids and REQ ids> have not drained after 30 minutes. Continue waiting, or abort?` Act on the user's response (continue → resume polling; abort → exit this orchestrator cleanly without writing `gate-owner.md`).
4. **If both globs come back clean on the first check (or after polling completes)**, this orchestrator owns the gate. Proceed to Step 7b.2.

**Linear drain (REQ-298 path; REQ-299 ops):**

1. Port op **`list_milestone_reqs`** for `M<active>` with status `backlog` (or claimable intersection). **Must return zero issues.** If non-zero, abort gate detection → Step 8.
2. Port op **`list_milestone_reqs`** for `M<active>` with status `in_flight` (active claim). For each issue, read active claim comment:
   - Claims by local `AGENT_ID` are expected (just-archived / releasing) and not a blocker once archive completed.
   - Any **foreign** active claim means the milestone is not drained.
3. **If foreign in-flight issues exist**, poll every 30 seconds, up to 30 minutes (re-list + re-classify). Timeout → same stuck-sibling user prompt (list Linear issue ids + agent ids). Abort without writing `gate-owner.md` if user aborts.
4. **If clean**, this orchestrator owns the gate → Step 7b.2.

#### Step 7b.2 — Claim the gate

1. **Write local gate ownership** via port op **`write_gate_state`** (claim) → `{project}/.do-work/state/gate-owner.md` containing a single line: the local `AGENT_ID`. (**Both backends** — concurrent gate ownership serializes via this **local** file only, even when milestone cursor content is remote — REQ-299; never Linear. Use the op’s re-read / lost-race rules: if another agent already owns the file, **do not** show the prompt; enter Step 1.0a idle-wait instead. Siblings in Step 1.0a read the file to attribute the wait.)
2. Read the deploy gate text for the active milestone:
   - **Markdown:** from `{project}/.do-work/user-requests/UR-NNN/input.md` — line beginning `**Deploy gate:**` under `#### M<active>`.
   - **Linear:** from **`read_ur`** brief / Initiative description — same `**Deploy gate:**` line under `#### M<active>` in the milestone-shaped brief.
3. Halt the loop and print:

   ```
   Milestone M<active> REQs complete.

   Deploy gate: <gate text verbatim>

   Has the deploy gate been satisfied? (y/n)
   ```

4. Wait for user input.

#### Step 7b.3 — Advance on `y`

**Markdown:**

- Update `{project}/.do-work/state/milestones.md` to mark M<active> as `deployed`.
- Identify the next pending milestone (lowest M<n+1> with status `pending` in milestones.md).
  - **If one exists:** update `{project}/.do-work/state/active-milestone.md` to that milestone id. **This file change is the signal that wakes idle siblings** (see Step 1.0a).
  - **If none exists** (all milestones deployed): delete `{project}/.do-work/state/active-milestone.md` so idle siblings fall through to `## When the Backlog is Empty`.
- Delete `{project}/.do-work/state/gate-owner.md` (or **`write_gate_state`** release).

**Linear (REQ-298/299):**

- Call port op **`set_active_milestone`**: mark M<active> checklist line `deployed`; set `**Active:**` to next pending `M<n+1>` **or clear** if none remain. **This Project description change wakes idle siblings** polling `read_active_milestone` (Step 1.0a).
- Do **not** require local `active-milestone.md` / `milestones.md` as the store.
- Release local gate via **`write_gate_state`** / delete `{project}/.do-work/state/gate-owner.md` (local-only).

Then (both backends):

- Ask: "Begin capture for the next milestone? (y/n)"
  - On **y**: print: "Run `/do-work capture UR-NNN` to decompose milestone M<n+1>." Exit.
  - On **n**: exit cleanly. The user can return later.

#### Step 7b.4 — Stop on `n`

- Ask: "What needs to change? Describe the gap." Capture the user's description.
- Delete `{project}/.do-work/state/gate-owner.md` (local release — both backends).
- **Markdown:** Delete `{project}/.do-work/state/active-milestone.md`. **This deletion wakes idle siblings** into the empty-backlog path (see Step 1.0a).
- **Linear:** **`set_active_milestone`** clear (`active` null). **This cursor clear wakes idle siblings** polling `read_active_milestone`.
- Print: "Run `/do-work capture UR-NNN` to add new REQs for the gap, or edit the UR's milestone definition. Idle siblings will exit when the active milestone cursor is cleared."
- Exit.

#### State file: `gate-owner.md` (local — both backends)

| Action | Actor | When |
|---|---|---|
| **Write** | Gate-owning orchestrator (Step 7b.2) via **`write_gate_state`** | After drain confirmation passes, before printing the gate prompt |
| **Read** | Sibling orchestrators (Step 1.0a) | When their active-milestone backlog is empty, to attribute the idle log line |
| **Delete** | Gate-owning orchestrator (Step 7b.3 or Step 7b.4) | After the user answers y or n, before exit |

Contents: a single line — the gate-owner's `AGENT_ID`. No header, no trailing data. If the file is ever found with malformed contents, treat as absent and continue. **Never** store gate ownership in Linear (design §11 / REQ-298 path; REQ-299 concurrent serialize). Concurrent claims use **`write_gate_state`** re-read rules so ownership serializes via this local file even when the milestone cursor is remote.

#### Non-delegation

- **Sign-off is non-delegable.** The orchestrator must NOT auto-confirm the deploy gate. The orchestrator must NOT attempt to deploy or test deployment itself. The worker is also forbidden from these actions (see [agents/run-worker.md](run-worker.md)).
- Only the *which orchestrator owns showing the prompt* changes under parallelism. The prompt text and the requirement for an explicit human y/n answer are unchanged.

### Step 8: Loop

If the Step 3b.1 budget gate tripped on the REQ just integrated, **do not loop** — the budget-stop report has already been emitted and the run ends here. Otherwise, go back to Step 1 and claim the next REQ.

A REQ with `deferred_checks:` is not a stopper — its code merged, its advisory checks were recorded in the archive, and its worktree was torn down. Continue looping exactly as after any done REQ.

**Dependency note.** Deferred manual checks do not change dependency flow. The REQ lands in `archive/`, so `lib/check-deps.sh` and `lib/pick-req.sh` treat it as satisfied through the normal archive-only path.

---


---

## Stopping Rules

Workers cannot pause and ask the user — they have no interaction surface. Every stopper must surface to the user **through the orchestrator**, never inline from the worker. The worker emits `status: stopped` with a structured `reason`; the orchestrator decides what to show the user.

### Stopper category → worker `reason` enum

| Situation | Worker emits `reason` |
|-----------|----------------------|
| Tests cannot be made to pass after 3 attempts | `tests-failing` |
| Verification steps fail after 3 attempts | `verification-failing` |
| A REQ has unmet dependencies on another REQ not yet complete | `dependency-missing` |
| Task requires external credentials or access not available | `missing-creds` |
| Acceptance criteria are ambiguous and cannot be interpreted | `ambiguous-criteria` |
| A change would affect files outside the REQ's stated scope | `scope-creep` |
| Commit or merge conflict unresolved after 5 retries (see run-worker.md `## Concurrent-Conflict Retry`) | `concurrent-conflict` |
| Any other unrecoverable error | `unknown-error` |

The worker captures relevant details in the report's `details` field. The worker does not retry beyond what's defined in [agents/run-worker.md](run-worker.md) and never asks the user a question — it exits with the structured report.

### Orchestrator handles user interaction

When the worker returns `status: stopped`, the orchestrator surfaces the stopper to the user. Recover the REQ from `working/` if it was not archived, then:

If this agent is running **standalone** (not as a delegate inside the go agent):

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Show blocker details"** — Display the worker's `details` field and any captured output
2. **"Retry current REQ"** — Re-dispatch the worker for the same REQ (fresh subagent session)
3. **"Skip"** — End the interaction

If this agent is running as a **delegate** inside go: print the stopper and the worker's `details` field, then stop. Do not loop, do not silently retry, do not auto-resolve.

### Per-REQ retry counter (ambiguous-criteria recurrence)

The orchestrator tracks per-REQ stopped-reason occurrences so a *second* `ambiguous-criteria` stop on the same REQ can surface as feedback (a single ambiguity is normal; a second on the same REQ means the user-facing clarification did not stick or the REQ wording is genuinely defective).

Counter store: `{project}/.do-work/state/retry-counters.md`. Format — one Markdown table row per (REQ, reason) pair:

```markdown
| REQ-NNN | ambiguous-criteria | 2 | 2026-05-21T02:14:22Z |
```

Columns: REQ id, reason, count, last-seen ISO-8601 UTC. The orchestrator keeps this in memory for the lifetime of the loop and flushes to the file after each update. If the file is missing on startup, treat all counters as zero.

When the worker returns `status: stopped`, `reason: ambiguous-criteria`:

1. Increment the (REQ-NNN, ambiguous-criteria) counter in memory and persist to `retry-counters.md`.
2. If the new count is **≥ 2**, emit feedback (best-effort, non-blocking) before surfacing the stopper to the user:

   ```bash
   FINGERPRINT="ambiguous-req:REQ-NNN"
   bash {skill-root}/lib/file-feedback.sh ambiguous-criteria \
     "$FINGERPRINT" \
     '{"req":"REQ-NNN","occurrence":'"$COUNT"',"first_seen":"<iso8601>","last_seen":"<iso8601>"}' \
     "Ambiguous-criteria recurrence: REQ-NNN (occurrence #$COUNT)" \
     "Worker has now stopped on REQ-NNN with reason ambiguous-criteria $COUNT times. The acceptance criteria likely need a rewrite, not another retry." \
     || true
   ```

3. Proceed to the existing user-interaction step above (AskUserQuestion or stop-and-print).

> **JUDGMENT:** Fire feedback only on the 2nd+ occurrence — the first stop is the worker doing its job; the second is the signal. Title states the REQ id and occurrence count so the human inbox immediately knows which REQ needs editing. The body must point at the *criteria* as the problem (not the worker, not the model) so the human reaches for the REQ file rather than a retry button.

---

