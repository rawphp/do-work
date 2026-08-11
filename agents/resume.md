# Resume Agent

You are the Resume agent in the Do Work system. Your job is to re-dispatch a fresh worker for a REQ that previously hit a `stopped` status — without sending it back through the backlog → reclaim → restart round-trip.

This is the primary recovery path for `concurrent-conflict`, transient `unknown-error`, and other non-judgment stoppers where the existing claim is still valid and the work just needs another swing.

You preserve the existing claim — `**Claimed by:**` and `**Claimed at:**` stay intact. The original agent retains ownership; resume only refreshes the heartbeat and flips status back to `in-progress`.

---

## When Invoked

You will be given:

1. A project do-work path: `{project}/.do-work/`
2. A REQ id to resume: `REQ-NNN`

Invoked via `/do-work resume REQ-NNN`.

---

## Steps

### 0. Load Config

Read and follow the **Load Config** section of [config.md](config.md).

### 0a. Tracker load path

Work-item storage (URs, REQs, decisions, verify/close reports, run notes) goes **only** through named tracker port ops after config is loaded:

1. Resolve effective `tracker.backend` (missing/empty/whitespace → `markdown`).
2. Read `agents/tracker/port.md` (shared op catalog + rules).
3. Read `agents/tracker/<backend>.md` (e.g. `markdown.md` or `linear.md`).
4. For work-item storage, call **only** named port ops from that backend file — never raw `.do-work/REQ-*` paths or raw Linear tools outside the backend doc.

**Hard rules:**
- **No silent fallback** from `linear` to `markdown`. If backend is `linear`, do not substitute UR/REQ markdown as the store.
- If backend resolves to **`linear`** but `agents/tracker/linear.md` is **missing or unreadable**, **hard-stop** with setup instructions (restore the Linear backend doc / connect Linear skill). Never fall through to markdown paths.
- Markdown backend: ops map — **invoke** coordination scripts as `bash {skill-root}/lib/...` after Load Config step 8 resolves `$SKILL_ROOT`; **catalog identity** remains `lib/*.sh` in `markdown.md` — use those ops; do not re-implement store details here.

**Branch on effective backend** after load path:

| Backend | Work-item resume |
|---------|------------------|
| **`markdown`** | Steps **1–6** below (working/ stamp + `heartbeat.sh`) |
| **`linear`** | Steps **L1–L5** — linear.md **Resume** (compose **`set_req_status`** + **`heartbeat_req`**). Id is a **Linear issue id**. Assignee and claim ownership preserved. |
| **`sqlite`** | **1S** — `get-req` / `set-status in_progress` / `heartbeat` by **REQ slug** via `lib/dw-db.sh` only. Do not glob `working/REQ`. |

Invocation under Linear may be `/do-work resume ENG-123`. Under sqlite: `/do-work resume REQ-NNN` (slug). Worktree/branch isolation stays **local** regardless of backend.

### When backend is sqlite (1S)

1. `bash {skill-root}/lib/dw-db.sh get-req {project} REQ-NNN` — must be `stopped` (or eligible) with an active claim for this agent when required
2. `set-status` → `in_progress`; `heartbeat` for agent
3. Do **not** require or create `working/REQ-*.md`
4. Hard-stop if dw-db fails — never markdown fallback

---

## Linear backend (Resume compose)

Resume is **not** a separate port op name. Follow **Resume (Linear — `agents/resume.md` consumer)** in `agents/tracker/linear.md`.

### L1. Locate issue and confirm stopped

1. Get issue by Linear id (rediscover tools; hard-stop if MCP unusable).
2. Workflow must map to `status_map.stopped`. If not stopped → refuse (same as markdown).
3. Latest claim must be `status: active` (**Helper: read active claim**). If `released` or missing → refuse; operator should use run/claim or `/do-work unblock`, not resume.
4. Record prior stopper context from run notes / comments when present for the announce line.

### L2. Detect worktree mode (local)

Same as markdown Step 2, using branch `req/<issue-id>` (sanitize for git ref rules) when Linear ids are used:

- Do **not** delete the existing feature branch.
- Do **not** clear the Linear claim.
- Fresh worker continues on the existing worktree/branch when present.

### L3. Refresh status and heartbeat (port ops)

1. **`set_req_status`** → `in_progress` (workflow `status_map.in_progress`). **Do not** change human assignee. **Do not** strip claim comments.
2. **`heartbeat_req`** — refresh `heartbeat` now; preserve `agent_id` and `claimed_at` on the active claim protocol (`agent_claim_marker` / `<!-- do-work-claim -->`).
3. If either op fails (MCP down mid-flight) → **leave claimed** (port mid-flight rule); hard-stop with setup/resume-later instructions. Do not invent markdown working/ cleanup.

### L4. Dispatch a fresh worker

Same as markdown Step 4 / [run.md](run.md) classification + model selection + dispatch. Pass the Linear issue id and prior context instead of a `.do-work/working/` path when the worker load path is Linear. Escalation for prior-stopped still applies.

Announce:

```
[<agent-id>] Resuming <ISSUE-ID> [type=<subagent_type>, model=<model>, prior reason=<reason>]: [title]
```

### L5. Process the worker report / stop

Same as markdown Steps 5–6 ([run.md](run.md) report processing). Single-issue operation; do not auto-loop.

---

## Markdown backend

### 1. Locate the REQ and confirm `stopped`

Check whether `{project}/.do-work/working/REQ-NNN-*.md` exists.

- If **no match**: report `"REQ-NNN is not in working/ — nothing to resume."` and stop.
- If **multiple matches** in `working/`: report the ambiguity and stop. Do not guess.
- If **exactly one match** in `working/`: record the absolute path as `REQ_PATH` and continue.

Read `REQ_PATH` and inspect `**Status:**`.

- If `**Status:**` is **not** `stopped`: refuse — report `"REQ-NNN is <status>, not stopped — refusing to resume."` and stop. Resume is exclusively for stopped REQs. Running ones don't need resuming; backlog/archived ones aren't claimed.
- If `**Status:**` is `stopped`: read and record `**Reason:**` (e.g. `concurrent-conflict`, `unknown-error`) and any associated context for the announce line. Continue.

### 2. Detect worktree mode

Inspect the REQ for worktree-mode signals:

- `**Isolation:** worktree` field present in the REQ frontmatter, OR
- A local branch `req/REQ-NNN` exists: `git show-ref --verify --quiet refs/heads/req/REQ-NNN`

If either is true, treat this REQ as worktree-mode:

- **Do not delete** the existing `req/REQ-NNN` branch.
- **Do not move** the REQ out of `working/`.
- The new worker dispatched in Step 4 will check out the existing branch and continue on it. Resume does not re-create or reset the worktree.

If neither signal is present, treat as standard in-tree mode — no worktree-specific action needed.

### 3. Refresh status and heartbeat

Edit `REQ_PATH` in a single pass:

- Change `**Status:**` from `stopped` back to `in-progress`.
- Remove the `**Reason:**` line if present — the prior stopper context is no longer the current state. (The reason was captured in the announce line in Step 1; archived run logs in git history retain the full record.)
- Leave the `<!-- claimed-start --> ... <!-- claimed-end -->` block's `**Claimed by:**` and `**Claimed at:**` lines **untouched**.

Then refresh the heartbeat:

```bash
bash {skill-root}/lib/heartbeat.sh "$REQ_PATH"
```

If `heartbeat.sh` exits non-zero (missing claim stamp, malformed file), report the failure and stop. Do not dispatch a worker against a REQ with no live heartbeat.

**Refresh the `**Session:**` line.** Resume preserves the original claim ownership, but the *session* now handling the REQ is this one — the extension's REQ→session resume lookup must point at the live session. Use the shared stamp primitive (insert / replace / leave-untouched; never free-hand edit the claim block):

```bash
bash {skill-root}/lib/stamp-session.sh "$REQ_PATH"
```

`stamp-session.sh` re-resolves via `lib/resolve-session.sh` when the session-id argument is omitted, inserts or replaces `**Session:**` inside the claim stamp, and leaves any existing Session line untouched when resolve prints nothing. Filesystem-only — no git commit, same contract as the heartbeat refresh. If it exits non-zero (missing claim stamp, path outside working/), report the failure and stop.

### 4. Dispatch a fresh worker

Re-use the orchestrator dispatch path from [run.md](run.md). Do not duplicate the classification or model-selection rules here.

1. Classify `subagent_type` using the **REQ Classification** section of [run.md](run.md).
2. Select `model` using the **Model Selection** section of [run.md](run.md). Note: a stopped-then-resumed REQ matches signal #1 in the model table (`previous status: stopped attempt recorded`) and therefore escalates to `opus` by default.
3. Identify prior-REQ archived paths for the same UR using the same lookup described in [run.md](run.md) Step 2.
4. Dispatch via the `Agent` tool, passing the same inline-prompt shape used in [run.md](run.md) Step 2 — the three inputs (REQ path, UR path, prior-REQ paths) plus the full [run-worker.md](run-worker.md) instructions verbatim.

Announce before dispatch:

```
[<agent-id>] Resuming REQ-NNN [type=<subagent_type>, model=<model>, prior reason=<reason>]: [title]
```

### 5. Process the worker report

Parse the worker's structured YAML return report exactly as described in [run.md](run.md) **Step 3: Process the worker report**. Branch on `status`:

| `status` | Action |
|---|---|
| `done` | Capture `commit` hash and `outputs`. Print the same completion line [run.md](run.md) Step 7 emits. Resume is a single-REQ operation — stop, do not loop back to the backlog. |
| `stopped` | Surface the new stopper to the user using the same **Stopping Rules** path defined in [run.md](run.md). Do not auto-resume again — that would loop indefinitely on a real blocker. |
| `failed` | Treat as `stopped` with `reason: unknown-error` per [run.md](run.md) Step 3. |

If the report is missing or unparseable, surface the raw output and stop.

### 6. Stop

Resume is a one-shot. Do not claim another REQ, do not invoke run, do not prompt for next steps unless the **Stopping Rules** path in [run.md](run.md) directs otherwise.

---

## Rules

- Refuse to resume a work item that is not **stopped** with an **active** claim. Backlog reclaim through `run.md`; done/archived are finished; abandoned `in-progress` uses `/do-work unblock`.
- **Markdown:** Preserve `**Claimed by:**` and `**Claimed at:**` exactly. Only `**Heartbeat:**` is refreshed.
- **Linear:** Preserve claim `agent_id` / `claimed_at`; refresh via **`heartbeat_req`**; workflow via **`set_req_status`** → in_progress; never steal assignee.
- For worktree-mode REQs, never delete or reset the feature branch — the fresh worker continues on it.
- Do not duplicate classification, model selection, or dispatch logic — refer to [run.md](run.md). When that file changes, resume inherits the change for free.
- Single REQ / issue per invocation. No batching.
- No `AskUserQuestion` next-step prompt unless triggered by the worker-report branch.
