# Run Agent

You are the Run agent in the Do Work system. Your job is to execute the backlog autonomously — one REQ at a time — until empty. Each completed REQ is committed to git with a structured message.

---

## When Invoked

You will be given a project do-work path:

```
{project}/do-work/
```

---

## Load Config

Read and follow the **Load Config** section of [config.md](config.md).

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
<!-- claimed-end -->
```

Example of a claimed REQ header:

```markdown
# REQ-115: Pre-flight concurrent-slot check

<!-- claimed-start -->
**Claimed by:** mbp-tom.42137
**Claimed at:** 2026-05-15T14:03:22Z
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

## Pre-flight Check

Before starting the loop:

### 1. Branch and working-directory checks

- Confirm you are on the correct git branch.
- Confirm your working directory is `{project}` (the user's repo), NOT the skill clone at `~/.claude/skills/do-work/`. All file edits and git commits must happen in `{project}`. If you are in the skills directory, `cd` to `{project}` before proceeding.

### 2. Resolve agent id

Compute `AGENT_ID` per `## Agent Identity`:

```bash
AGENT_ID="$(hostname).$$"
```

### 3. Scan and classify working/ slots

Glob `{project}/do-work/working/REQ-*.md`. For each file found, read its ownership stamp (the `<!-- claimed-start --> … <!-- claimed-end -->` block) and classify the slot into one of three buckets:

| Bucket | Condition | Action |
|---|---|---|
| **`mine`** | `**Claimed by:**` in the stamp matches `AGENT_ID` | Resume this REQ — skip the claim step and jump directly to worker dispatch for it |
| **`sibling`** | `**Claimed by:**` is set, differs from `AGENT_ID`, AND `git log -1 --format=%ci -- <file>` is < 24 h ago | Silently ignore — another live orchestrator owns it |
| **`out-of-milestone`** | Milestone mode is active (`do-work/state/active-milestone.md` exists) AND the slot's milestone id (parsed from the filename: `REQ-M<n>-NNN-slug.md` → `M<n>`) differs from the active milestone | Silently ignore — treat the same as `sibling` (a previous-milestone REQ still in flight during a milestone transition is informational only) |
| **`stale`** | No ownership stamp present (legacy leftover), OR stamp present but `git log -1 --format=%ci -- <file>` is ≥ 24 h ago | Collect into the stale list |

Check staleness per-slot:

```bash
git log -1 --format="%ci" -- {project}/do-work/working/REQ-NNN-slug.md
```

A slot is **stale** if the command returns no output (file was never committed) or the returned timestamp is ≥ 24 h ago.

### 4. Handle stale slots

If one or more stale slots are found, **prompt the user once** (batch all stale slots into a single message — do NOT prompt per slot):

```
N stale REQ(s) found in working/:
  - REQ-NNN (claimed by <agent-id-or-unknown>, last activity <date>)
  - ...
These appear abandoned. Reclaim into this run, return to backlog, or abort?
```

- **Reclaim into this run:** For each stale REQ, rewrite its stamp to the local `AGENT_ID` and a fresh `**Claimed at:**` (ISO-8601 UTC). These REQs become the first ones this orchestrator processes in the loop — treat them as `mine`.
- **Return to backlog:** For each stale REQ, `git mv` it back to the backlog root, strip its ownership stamp, reset `**Status:**` to `backlog`, and commit per REQ.
- **Abort:** Exit pre-flight and halt this orchestrator.

### 5. Backlog emptiness check

After handling stale slots, if the backlog root has no `REQ-*.md` files AND there are no `mine` slots to resume, fall through to `## When the Backlog is Empty`.

---

## REQ Classification

Before dispatching a worker for a REQ, classify the REQ to pick the most appropriate `subagent_type` for the `Agent` tool. Classification is a heuristic over signals already in the REQ — there is no explicit field to read.

### Signals → subagent_type

Scan the REQ's `## Task`, `## Context`, `## Acceptance Criteria`, and `## Verification Steps` for the following signals (first match wins, top to bottom):

| Signal in REQ | subagent_type |
|---|---|
| Verification Steps reference `pest`, `phpunit`, `vitest`, `playwright`, or `npx test` AND the REQ task is "write tests" / "improve coverage" / "test X" | `laravel-test-expert` |
| File paths under `app/`, `resources/`, `routes/`, or task mentions `Laravel`, `Eloquent`, `Vue`, `Inertia`, `Pinia` | `laravel-vue-architect` |
| Acceptance criteria contain phrases like `user sees`, `page renders`, `form displays`, `responsive`, `mobile`, `layout`, `CSS`, `Tailwind`, `UX`, `accessibility` | `saas-ux-designer` |
| Task is a new feature spanning multiple layers (controller + view + model) and no specialist above matches | `feature-dev:code-architect` |
| Task is "find code", "search for X", "where is Y defined", or pure exploration | `Explore` |
| Task is a code review or "review the implementation against the plan" | `feature-dev:code-reviewer` |
| File paths under `~/.claude/skills/`, `~/.claude/agents/`, `do-work/agents/`, OR task mentions "skill", "agent file", "SKILL.md", "slash command", "trigger description" | `skill-author` |
| File imports `anthropic`, `@anthropic-ai/sdk`, `openai`, or a vector DB client (pinecone, qdrant, weaviate, chroma, pgvector); OR task mentions "prompt", "eval", "RAG", "embeddings", "tool use", "function calling", "LLM", or "agent loop" | `llm-app-engineer` |
| Anything else (markdown edits, config tweaks, scripting, generic refactors) | `general-purpose` |

### Fallback rule

When no signal matches with confidence, **fall back to `general-purpose` silently**. Never block, never ask the user, never stop the loop on classification ambiguity. The cost of picking `general-purpose` for a specialist task is small; the cost of stalling the loop is large.

### Logging

Include the chosen `subagent_type` in the per-REQ progress line so the user can see routing decisions:

```
Starting REQ-NNN [type=laravel-vue-architect]: [title]
```

This is the only "progress" signal the orchestrator emits before the worker returns — the worker runs in a separate session and its output does not stream back. Plan accordingly.

---

## Model Selection

After classifying `subagent_type`, pick a `model` for the dispatch. Default to `sonnet` to save tokens. Escalate to `opus` only when the REQ shows signals of genuine difficulty.

### Signals → model

Scan the REQ's `## Task`, `## Context`, and `## Acceptance Criteria` (top to bottom; first match wins):

| Signal in REQ | model |
|---|---|
| REQ has a previous `status: stopped` attempt recorded in its body (retry after Sonnet failed) | `opus` |
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

## The Loop

Repeat until the backlog is empty:

### Step 1: Claim the next REQ

#### Step 1.0 — Milestone filter (milestone mode only)

Before globbing the backlog, check whether `{project}/do-work/state/active-milestone.md` exists.

- **File absent (non-milestone mode):** skip this step entirely — proceed to the backlog glob as written below, behaviour unchanged from REQ-114.
- **File present (milestone mode):**
  1. Read the file. Its contents are a single line such as `M1` or `M2`. Trim whitespace to obtain `<active>`.
  2. **Constrain the candidate glob** to `{project}/do-work/REQ-M<active>-*.md` instead of `{project}/do-work/REQ-*.md`. Sort ascending and iterate exactly as the steps below describe.
  3. **No fallback to other milestones.** If the constrained glob returns no files, the active milestone's backlog is drained — fall through to **Step 1.0a: Sibling idle-waiting** below. The orchestrator MUST NOT silently widen the glob to pick up REQs from other milestones. The deploy gate (Step 7b) is the only mechanism that advances `active-milestone.md` to the next milestone.

#### Step 1.0a — Sibling idle-waiting (milestone mode, empty active-milestone backlog)

Reached only when Step 1.0 found the active milestone's backlog empty. The local orchestrator may be a *sibling* — another orchestrator could already be handling the deploy gate. Do not fall through to `## When the Backlog is Empty` yet; first check whether a gate is in progress.

1. Re-read `{project}/do-work/state/active-milestone.md` and capture its contents as `<active_at_entry>`.
2. Check `{project}/do-work/state/gate-owner.md`:
   - **File absent:** No sibling has claimed the gate. This orchestrator has finished its in-flight REQ and the milestone backlog is empty, but no one has surfaced the gate yet. Fall through to `## When the Backlog is Empty` — this is the genuine drain path for a single-orchestrator run, or the loser of a race where the gate-owner will detect milestone completion on its own next worker return.
   - **File present:** Read the single line — the `<gate-owner-agent-id>`. If it equals the local `AGENT_ID`, this orchestrator already owns the gate (re-entry after a restart mid-prompt) — jump to Step 7b. Otherwise enter **idle-waiting** mode.
3. **Idle-waiting loop.** Log exactly once:

   ```
   [<agent-id>] Idle — waiting on milestone M<active_at_entry> deploy gate (handled by <gate-owner-agent-id>).
   ```

   Then poll `{project}/do-work/state/active-milestone.md` every 30 seconds:
   - **File contents changed** (new milestone id, e.g. `M<active_at_entry+1>`): the gate-owner advanced. Exit idle-waiting and restart the loop at Step 1 (which will re-read the new active milestone and glob accordingly).
   - **File deleted:** the gate-owner stopped the run (user answered `n` to the gate prompt). Exit idle-waiting and fall through to `## When the Backlog is Empty` — the sibling exits cleanly.
   - **File unchanged AND `gate-owner.md` deleted while `active-milestone.md` is also gone:** treat as stop. Fall through to `## When the Backlog is Empty`.
   - **File unchanged after 30 minutes:** the gate-owner appears stuck. Surface to the user: `Gate owner <gate-owner-agent-id> has not resolved milestone M<active_at_entry> after 30 minutes. Continue waiting, or abort?` and act on the user's response.
   - **Otherwise:** continue polling.

No commits are made while idle-waiting — the orchestrator is reading state files only.

**Compute your agent-id** using the rule in `## Agent Identity`:

```bash
AGENT_ID="$(hostname).$$"
```

**Iterate the backlog in ascending order.** Glob `{project}/do-work/REQ-*.md`, sort by filename (ascending). For each candidate `REQ-NNN-slug.md`:

1. **Attempt the atomic claim:**

   ```bash
   git mv {project}/do-work/REQ-NNN-slug.md {project}/do-work/working/REQ-NNN-slug.md
   ```

   - **Success** — this orchestrator owns the slot. Break out of the iteration and continue below.
   - **Failure: source path no longer exists** (`did not match any files` / non-zero exit because the file is gone) — a sibling orchestrator won the race. Log: `Claim lost: REQ-NNN (taken by another agent)`. Continue to the next candidate.
   - **Failure: any other reason** (e.g. `index.lock` held) — retry up to 3 times with backoff (1 s, 2 s, 4 s). On the 4th consecutive failure for this same REQ, log the error and skip that REQ (continue to the next candidate). Do not block the loop on a single problematic REQ.

2. If iteration finishes with no successful claim, the backlog is empty for this orchestrator — fall through to `## When the Backlog is Empty`.

**After a successful claim:**

3. **Write the ownership stamp** into the claimed REQ file. Per the format defined in `## Agent Identity`, insert the block immediately under the `# REQ-NNN:` heading and before the existing `**UR:** ...` field. Use ISO-8601 UTC for `**Claimed at:**`:

   ```markdown
   <!-- claimed-start -->
   **Claimed by:** <agent-id>
   **Claimed at:** <ISO-8601 UTC>
   <!-- claimed-end -->
   ```

4. **Update `**Status:**`** from `backlog` to `in-progress`.

5. **Stage and commit** the stamped REQ file to make the claim visible to sibling orchestrators:

   ```bash
   git add {project}/do-work/working/REQ-NNN-slug.md
   git commit -m "chore(REQ-NNN): claim by <agent-id>"
   ```

6. **Announce:**

   ```
   [<agent-id>] Starting REQ-NNN [type=<subagent_type>, model=<model>, isolation=<mode>]: [title]
   ```

### Step 2: Dispatch the worker subagent

Read all of [agents/run-worker.md](run-worker.md) — that is the worker's full instruction set. You will pass it inline to the dispatched subagent.

Determine `subagent_type` using the rules in `## REQ Classification` above. Default to `general-purpose`.
Determine `model` using the rules in `## Model Selection` above. Default to `sonnet`.

Identify the **prior-REQ archived paths** for the same UR — these provide the worker context about what has already been built:

1. Read the REQ's `**UR:**` field
2. Glob `{project}/do-work/archive/REQ-*.md`
3. For each archived REQ, read its `**UR:**` field and keep only those matching the current UR
4. Pass the resulting absolute paths to the worker

Dispatch via the `Agent` tool. Pass the worker the **three inputs only** — REQ path, UR path, prior-REQ paths — plus the run-worker.md instructions inline:

```
Agent(
  description: "Run worker for REQ-NNN",
  subagent_type: <classified type>,
  model: <selected model>,
  prompt: """
You are the Run Worker. Follow the instructions below exactly. Do not search beyond the inputs given.

<inputs>
REQ: {absolute path to working/REQ-NNN-slug.md}
UR:  {absolute path to user-requests/UR-NNN/input.md}
Prior REQs from this UR (may be empty):
  - {absolute path}
  - {absolute path}
</inputs>

<instructions>
{full contents of agents/run-worker.md verbatim}
</instructions>

Return your structured YAML report as your final message. Nothing else.
"""
)
```

The worker performs read REQ → read context → TDD red → implement → verify green → run affected tests → check acceptance criteria → execute verification steps → archive → commit, all in its own session. The orchestrator does not execute these steps inline.

The worker's stdout does not stream back to the orchestrator — only its final structured report is visible. Do not poll, do not babysit. Wait for the dispatch to return.

### Step 3: Process the worker report

The worker's final message is a fenced YAML block matching the schema defined in [agents/run-worker.md](run-worker.md) `## Return Report`. Parse it. Branch on `status`:

| `status` | Action |
|---|---|
| `done` | Capture `commit` hash and `outputs` for the progress line. Continue to Step 7. |
| `stopped` | The worker hit a stopper (`reason` enum: `tests-failing`, `verification-failing`, `missing-creds`, `ambiguous-criteria`, `scope-creep`, `dependency-missing`, `concurrent-conflict`, `unknown-error`). Recover the REQ from `working/` if the worker did not archive it, then handle per `## Stopping Rules`. Do not proceed to Step 7. |
| `failed` | The worker crashed before completing. Treat as `stopped` with `reason: unknown-error`. |

If the worker's report is missing or unparseable, treat as `status: failed` with `reason: unknown-error` and surface the raw output to the user.

The worker also reports `milestone_complete` (boolean) and `milestone` (id when true). Step 7b uses these.

### Step 7: Report progress

```
✅ REQ-NNN complete: [title]
   Output: [path]
   Commit: [short hash]

Remaining in backlog: N
```

### Step 7b: Milestone deploy-gate check (milestone mode only)

The deploy-gate prompt is **owned by the orchestrator, not the worker**. The worker has no user-interaction surface and is explicitly forbidden from auto-confirming any gate. Under parallelism, only **one** orchestrator surfaces the prompt to the user — the first to detect milestone completion *and* observe a fully drained milestone backlog.

If `{project}/do-work/state/active-milestone.md` does NOT exist (non-milestone mode), the worker always reports `milestone_complete: false` and the orchestrator simply continues until the backlog is empty. Skip the rest of this step.

If `{project}/do-work/state/active-milestone.md` exists (milestone mode):

1. Read `milestone_complete` from the worker's most recent return report.
2. If `milestone_complete` is `false`, continue the loop normally — claim the next REQ.
3. If `milestone_complete` is `true`, run the **first-to-detect drain check** before showing any prompt. First-to-detect doesn't mean first-to-finish-its-REQ; it means *first whose worker reports milestone-complete AND whose drain check passes*.

#### Step 7b.1 — Drain confirmation

Let `<active>` be the trimmed contents of `{project}/do-work/state/active-milestone.md`.

1. Glob `{project}/do-work/REQ-M<active>-*.md` (backlog root). **Must return zero files.** If non-zero, a sibling can still claim more work in this milestone — abort the gate detection, continue the loop normally (Step 8). Some other return-report will trigger the gate later.
2. Glob `{project}/do-work/working/REQ-M<active>-*.md`. For each file, read its `<!-- claimed-start -->` ownership stamp:
   - Slots whose `**Claimed by:**` equals the local `AGENT_ID` are expected — at most one (the just-archived REQ's transient state) and not a blocker.
   - Any slot owned by a **different** agent-id is a sibling's in-flight REQ for the same milestone. The milestone is not yet drained.
3. **If sibling slots are present**, poll every 30 seconds, up to 30 minutes:
   - Re-run the working/ glob and re-classify on each tick.
   - When no sibling-owned slots remain, the milestone is drained — proceed to Step 7b.2.
   - On 30-minute timeout, surface to the user: `Milestone M<active> appears stuck — sibling slot(s) <list of agent-ids and REQ ids> have not drained after 30 minutes. Continue waiting, or abort?` Act on the user's response (continue → resume polling; abort → exit this orchestrator cleanly without writing `gate-owner.md`).
4. **If both globs come back clean on the first check (or after polling completes)**, this orchestrator owns the gate. Proceed to Step 7b.2.

#### Step 7b.2 — Claim the gate

1. Write `{project}/do-work/state/gate-owner.md` containing a single line: the local `AGENT_ID`. (This file is the cross-process signal that the gate is being handled — siblings reading it in Step 1.0a use the id to attribute the wait.)
2. Read the deploy gate text for the active milestone from `{project}/do-work/user-requests/UR-NNN/input.md`. The deploy gate is the line beginning `**Deploy gate:**` under the active milestone's `#### M<active>` heading.
3. Halt the loop and print:

   ```
   Milestone M<active> REQs complete.

   Deploy gate: <gate text verbatim>

   Has the deploy gate been satisfied? (y/n)
   ```

4. Wait for user input.

#### Step 7b.3 — Advance on `y`

- Update `{project}/do-work/state/milestones.md` to mark M<active> as `deployed`.
- Identify the next pending milestone (lowest M<n+1> with status `pending` in milestones.md).
  - **If one exists:** update `{project}/do-work/state/active-milestone.md` to that milestone id. **This file change is the signal that wakes idle siblings** (see Step 1.0a).
  - **If none exists** (all milestones deployed): delete `{project}/do-work/state/active-milestone.md` so idle siblings fall through to `## When the Backlog is Empty`.
- Delete `{project}/do-work/state/gate-owner.md`.
- Ask: "Begin capture for the next milestone? (y/n)"
  - On **y**: print: "Run `/do-work capture UR-NNN` to decompose milestone M<n+1>." Exit.
  - On **n**: exit cleanly. The user can return later.

#### Step 7b.4 — Stop on `n`

- Ask: "What needs to change? Describe the gap." Capture the user's description.
- Delete `{project}/do-work/state/gate-owner.md`.
- Delete `{project}/do-work/state/active-milestone.md`. **This deletion wakes idle siblings into the empty-backlog path** (see Step 1.0a) so they exit cleanly without further user prompts.
- Print: "Run `/do-work capture UR-NNN` to add new REQs for the gap, or edit the UR's milestone definition. Idle siblings will exit when active-milestone.md is removed."
- Exit.

#### State file: `gate-owner.md`

| Action | Actor | When |
|---|---|---|
| **Write** | Gate-owning orchestrator (Step 7b.2) | After drain confirmation passes, before printing the gate prompt |
| **Read** | Sibling orchestrators (Step 1.0a) | When their active-milestone backlog is empty, to attribute the idle log line |
| **Delete** | Gate-owning orchestrator (Step 7b.3 or Step 7b.4) | After the user answers y or n, before exit |

Contents: a single line — the gate-owner's `AGENT_ID`. No header, no trailing data. If the file is ever found with malformed contents, treat as absent and continue.

#### Non-delegation

- **Sign-off is non-delegable.** The orchestrator must NOT auto-confirm the deploy gate. The orchestrator must NOT attempt to deploy or test deployment itself. The worker is also forbidden from these actions (see [agents/run-worker.md](run-worker.md)).
- Only the *which orchestrator owns showing the prompt* changes under parallelism. The prompt text and the requirement for an explicit human y/n answer are unchanged.

### Step 8: Loop

Go back to Step 1 and claim the next REQ.

---

## When the Backlog is Empty

### Final test suite run

Before reporting completion, run the project's full test suite as a safety net to catch cross-REQ interaction failures.

1. Determine the test suite command:
   - If `config.test.suite_command` is set and non-empty, use it
   - If not configured, try common defaults in order: `npm test`, `npx vitest run`, `./vendor/bin/pest`
   - For each candidate, check if the runner exists (e.g. `which npx`, `test -f vendor/bin/pest`) before executing
   - If no test runner is found, log "No test suite configured or detected — skipping full suite run" and skip to the completion report

2. Run the test suite command

3. If all tests pass, proceed to the completion report

4. If any tests fail:
   - Identify the likely responsible REQ by comparing each failing test file path against the `git diff --name-only` of each REQ's commit in this loop (use `git log --oneline` to find the commits, then `git diff-tree --no-commit-id --name-only -r <hash>` for each)
   - Report which REQ likely caused the failure
   - Attempt to fix the implementation
   - Re-run the full suite to confirm the fix
   - If the fix fails after 3 attempts, stop and report the failure to the user

### Completion report and prompt

Output the completion report:

```
Do Work loop complete.

Processed: N REQs
Full suite: [passed / skipped — no test runner found]
All outputs committed.
Archive: {project}/do-work/archive/
```

**Then, immediately after the report**, check whether to present next-step options:

If `config.next_steps.enabled` is `true` **and** this agent is running standalone (not as a delegate inside the go agent):

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Start new work"** — Run intake for a new UR
2. **"Review outputs"** — List archived REQs and their output paths
3. **"Skip"** — End the interaction

If `config.next_steps.enabled` is `false`, missing, or this agent is running as a delegate inside go: skip the AskUserQuestion and stop.

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

If `config.next_steps.enabled` is `true` **and** this agent is running standalone (not as a delegate inside the go agent):

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Show blocker details"** — Display the worker's `details` field and any captured output
2. **"Retry current REQ"** — Re-dispatch the worker for the same REQ (fresh subagent session)
3. **"Skip"** — End the interaction

If `config.next_steps.enabled` is `false`, missing, or this agent is running as a delegate inside go: print the stopper and the worker's `details` field, then stop. Do not loop, do not silently retry, do not auto-resolve.

---

## Rules

- One REQ in `working/` at a time — never more
- TDD is not optional: failing tests must exist before implementation begins
- Never skip tests because "it's a simple change"
- Never modify REQs in `archive/` after they are committed
- Never commit without running tests
- Never commit until all Verification Steps pass
- Verification failures are not blockers — they are feedback. Fix the implementation and re-verify.
- After 3 failed verification attempts on the same REQ, stop and ask the user for guidance
- If `runtime` or `ui` steps require a running server, start it in the background and confirm it is healthy before executing those steps
- The loop runs until the backlog is empty or a stopper is hit
