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

### 1. Locate the REQ and confirm `stopped`

Check whether `{project}/.do-work/working/REQ-NNN-*.md` exists.

- If **no match**: the REQ is not an in-flight working slot — check whether it is instead in `.do-work/pending/`:
  - **Found in `pending/`**: refuse with:
    ```
    REQ-NNN is in pending-validation state — it cannot be resumed.
    The code is already merged; only human sign-off remains.
    Outstanding checklist items: <count items in ## Post-merge validation, or "none listed">
    To close: /do-work approve REQ-NNN
    To return to backlog: /do-work reject REQ-NNN <note>
    ```
    Stop. Do not dispatch a worker, do not modify the REQ, do not stamp a heartbeat.
  - **Not in `pending/` either**: report `"REQ-NNN is not in working/ — nothing to resume."` and stop.
- If **multiple matches** in `working/`: report the ambiguity and stop. Do not guess.
- If **exactly one match** in `working/`: record the absolute path as `REQ_PATH` and continue.

Read `REQ_PATH` and inspect `**Status:**`.

- If `**Status:**` is `pending-validation`: refuse with the same guidance as above (the REQ was moved to `pending/` but a stale `working/` reference should not be resumed). Report the pending state, direct the user to `/do-work approve REQ-NNN` or `/do-work reject REQ-NNN`, and stop.
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

- **Never resume a pending-validation REQ.** A REQ in `.do-work/pending/` (or carrying `**Status:** pending-validation`) has already had its code merged and its worktree torn down — there is no worker to re-dispatch. The correct verb is `/do-work approve REQ-NNN` (to close) or `/do-work reject REQ-NNN` (to return to backlog with a note). Resume must refuse with that guidance and stop without touching claim stamps, heartbeats, or the REQ file.
- Refuse to resume a REQ whose `**Status:**` is not `stopped`. Backlog REQs reclaim through `run.md`; archived REQs are done; `in-progress` REQs are either live or already abandoned (use `/do-work unblock` for those).
- Preserve `**Claimed by:**` and `**Claimed at:**` exactly. Only `**Heartbeat:**` is refreshed.
- For worktree-mode REQs, never delete or reset the `req/REQ-NNN` branch — the fresh worker continues on it.
- Do not duplicate classification, model selection, or dispatch logic — refer to [run.md](run.md). When that file changes, resume inherits the change for free.
- Single REQ per invocation. No batching.
- No `AskUserQuestion` next-step prompt unless triggered by the worker-report branch in Step 5.
