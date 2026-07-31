# Linear path-milestone mode sequences (reference)

One hop from [`agents/tracker/linear.md`](../agents/tracker/linear.md). Load for deploy-gate / M1–Mn delivery mode only.

## Disambiguation (read first)

| | **Milestone-as-UR** | **Path-milestone mode (M1/M2)** |
|--|---------------------|--------------------------------|
| Purpose | Hierarchy: the UR itself | Delivery bridges *within* one UR |
| Linear entity | **Project Milestone** named via `ur_milestone_name_pattern` | Not a separate UR entity |
| Cursor | n/a (the milestone *is* the UR) | `<!-- do-work-milestone -->` block on the **UR Project Milestone description** |
| Issues | All REQs for the UR attach to the UR milestone | Additionally tagged `M1` / `**Milestone:** M1` for listing |
| Gate | n/a | Local `state/gate-owner.md` only |

**Never** invent Initiative-as-UR. **Never** put gate ownership in Linear.

---

## Milestone mode (design §11 — REQ-298 path; REQ-299 ops)

### Trigger (unchanged)

Identical to markdown capture / run:

1. UR brief frontmatter or body contains `source: /saas-thesis handoff`.
2. Body contains a `### Milestones` heading with at least one `#### M1` (or higher) subheading.

Both required → **milestone mode**. Neither Linear labels nor Project cursor alone turn milestone mode on. Brief load under Linear: **`read_ur`** (`## Brief` / machine sections); do not invent a different trigger.

### Project description cursor block (marker format)

Authoritative work-item cursor under `backend: linear`. Lives on the **UR Project Milestone** description (Milestone-as-UR entity on `product_project`), not a separate per-UR Project and not local `active-milestone.md`.

```markdown
<!-- do-work-milestone -->
**Active:** M1

# Milestones

- [x] M1 — <name> — captured
- [ ] M2 — <name> — pending
- [ ] M3 — <name> — pending
```

| Field | Rules |
|-------|--------|
| `<!-- do-work-milestone -->` | Required first line of the machine block. Absent on Project ⇒ **not** in milestone mode (same as missing `active-milestone.md`). |
| `**Active:**` | Single token `M<n>` (e.g. `M1`) or empty / `none` when cursor cleared after all deployed or gate stop. |
| `# Milestones` checklist | One line per bridge milestone. Status suffix: `pending` \| `captured` \| `running` \| `deployed` (parity with markdown `milestones.md`). Checked box when status is `captured` or later; agents may keep `[x]` only for `deployed` if they prefer — **status word is authoritative**. |

**Statuses (same vocabulary as markdown capture):**

| Status | Meaning |
|--------|---------|
| `pending` | Not yet captured |
| `captured` | REQs written for this M |
| `running` | Run loop active for this M (optional stamp) |
| `deployed` | Deploy gate passed for this M |

#### Parse algorithm (REQ-299)

Given Project description text `D`:

1. Locate the first line that is exactly (or trims to) `<!-- do-work-milestone -->`.
2. **If not found** → marker absent → return `{ active: null, checklist: [] }` — **does not invent a milestone id**.
3. Collect the machine block from that marker through the end of the `# Milestones` checklist (until blank line before next top-level machine marker, next `<!-- … -->` that is not checklist content, or EOF).
4. Within the block, find the first line matching `**Active:**\s*(.*)$`. Trim the capture group:
   - empty, missing, or case-insensitive `none` → `active: null` (still **does not invent a milestone id**).
   - else require token shape `M` + digits (e.g. `M1`, `M12`); malformed → treat as `active: null` (do not invent / coerce).
5. Parse checklist lines under `# Milestones` matching `- [ |x|X] M<n> — … — <status>` into `{ id, name, status, checked }` rows (best-effort; active id does not require checklist parse success).
6. Return `{ active, checklist }`. Never read local `state/active-milestone.md` as the store under Linear.

### Issue milestone markers (for `list_milestone_reqs`)

When capture creates Issues under milestone mode, mark membership so listing does not depend on markdown `REQ-M1-NNN` filenames:

1. **Prefer** Linear Project **milestone entity** / issue–milestone link when live `search_tool` finds such tools — attach the issue to milestone `M<n>` (or the entity named `M<n>` / matching title).
2. **Else (v1 default):** apply a **label** whose name is exactly the milestone id (`M1`, `M2`, …) when label tools exist, **and** set body header `**Milestone:** M1` (same id) next to other `<!-- do-work-req -->` headers.
3. **Parse order for filters:** (entity attachment if present) → label `M<n>` → body `**Milestone:** M<n>`. Any one match includes the issue. Missing all three → issue is **not** in that milestone (do not invent).

Path-unit parents and layer children for the same unit share the same milestone marker.

### `read_active_milestone`

| | |
|---|---|
| **Intent** | Read the active milestone cursor (if any). |
| ****Home** | UR Project Milestone description block `<!-- do-work-milestone -->` (path-milestone mode cursor — not the UR entity itself). |
| **Preconditions** | None beyond readable Project; missing / empty block ⇒ not in milestone mode. |
| **Returns** | `{ active: "M1" \| null, checklist: [...] }` — `active` null when marker missing, `**Active:**` empty/`none`/malformed, or Project unresolved. **Does not invent a milestone id.** |

**Agent sequence:**

1. **Rediscover** Project get/list tools (`search_tool` → `use_tool`).
2. **Resolve Project** — name `do-work/{UR-id}` (or Project id from `read_ur` / `**Project-id:**`). Caller may pass Project id or UR id.
3. **Read description.** Apply **Parse algorithm** above.
4. **Return** structured result. Do **not** read local `state/active-milestone.md` as the store. Do **not** default missing cursor to `M1` inside this op. Do **not** confuse path-milestone cursor with the UR Project Milestone entity.

| Failure | Behavior |
|---------|----------|
| Milestone tools missing | Hard-stop — Linear setup; do **not** fall back to local `active-milestone.md` as work-item store |
| UR Project Milestone missing | Hard-stop (UR not provisioned) |
| Marker missing | Return `active: null` (not-in-milestone) — **does not invent a milestone id**; not an error |
| `**Active:**` empty / `none` / malformed | Return `active: null` — **does not invent a milestone id** |

**Caller defaults (not part of this op):** capture Step 1b may use `M1` as the first-decompose target when `active` is null and the brief trigger is true. That policy lives in `agents/capture.md` and must call **`set_active_milestone`** to persist — it is not a fabricated return from `read_active_milestone`.

### `set_active_milestone`

| | |
|---|---|
| **Intent** | Set, advance, or clear the active milestone cursor; maintain checklist status. |
| **Home** | Same Project description block as `read_active_milestone`. |
| **Preconditions** | Milestone mode applicable (trigger was true at capture, or block already exists); target id is `M<n>` or clear. |
| **Does not** | Own the deploy-gate y/n prompt; write `gate-owner.md` (use **`write_gate_state`**); create Issues. |

**Agent sequence:**

1. ****Rediscover** Project Milestone get/update tools.
2. **Resolve UR Project Milestone** for the UR.
3. **Read** current description + existing path-milestone cursor block (create block if capture is writing first cursor).
4. **Apply caller intent:**
   - **Set / advance** to `M<n>`: set `**Active:** M<n>`; update checklist line for prior M to `deployed` (or caller-supplied status); set target line to `captured` / `running` / as requested.
   - **Capture stamp:** after capture writes REQs for `M<n>`, set `**Active:** M<n>` and mark that line `captured` (create full checklist from brief `### Milestones` on first write).
   - **Clear** (all deployed, or gate `n` stop): set `**Active:**` empty or remove the active value; mark remaining lines per caller; or strip the whole block when the run stops with no next M. Prefer leaving checklist history with `deployed` marks when useful for humans.
5. ****Write** UR Project Milestone description — replace **only** the `<!-- do-work-milestone -->` path-milestone machine block; preserve §9.1 sections outside the block.
6. **Return** new `active` value (or null if cleared).

| Failure | Behavior |
|---------|----------|
| Milestone tools missing / update fails | Hard-stop; do **not** write local `active-milestone.md` as substitute store |
| Invalid target id | Hard-stop / refuse |

**Deploy-gate consumers (run Step 7b):** on human **y**, call `set_active_milestone` with next pending id (or clear if none). On human **n**, clear active. Gate file lifecycle stays on **`write_gate_state`**.

### `list_milestone_reqs`

| | |
|---|---|
| **Intent** | List REQs (Linear Issues) belonging to the active or named milestone. |
| **Preconditions** | Milestone id known (`M<n>`) or active cursor set via `read_active_milestone`. |
| ****Scope** | Issues on product Project attached to this UR Project Milestone only. |

**Agent sequence:**

1. **Resolve milestone id** — argument `M<n>`, else `read_active_milestone` → if `active` null, return empty list (not milestone mode). **Do not invent** an id to list against.
2. **Rediscover** issue list tools; optionally milestone-entity tools.
3. **`list_reqs_for_ur`** (or equivalent Project-scoped issue list) for the UR Project.
4. **Filter** to issues whose milestone marker matches `M<n>` (entity / label / `**Milestone:**` — see above).
5. **Optional status filter** (caller):
   - `backlog` — workflow maps to `status_map.backlog` (claimable candidates for this M).
   - `in_flight` — `in_progress` or `stopped` with active claim.
   - `done` — `status_map.done`.
   - `any` (default) — all membership matches.
6. **Return** ordered list of Linear issue ids (+ optional titles/status). Sort: Priority DESC (missing→2), created_at ASC, id ASC (same as `list_claimable_reqs` when used for pick).

**Used by:**

| Consumer | How |
|----------|-----|
| Run Step 1.0 | Constrain claim pool to active M (`list_milestone_reqs` ∩ `list_claimable_reqs`, or pass milestone scope into claimable walk) |
| Run Step 7b drain | Backlog for M must be empty; no foreign in-flight claims for M |
| Worker milestone_complete | No remaining non-done issues for active M in Project (or no backlog + no foreign in-flight) |
| Capture numbering | Count existing issues for M when assigning sequence metadata (Linear ids remain authoritative identifiers) |

| Failure | Behavior |
|---------|----------|
| Issue list tools missing | Hard-stop |
| Active unknown and no id arg | Empty list |

**No fallback to other milestones** — same rule as markdown: empty list means this M is drained for that filter; do not widen to M2 while active is M1.

### `write_gate_state`

| | |
|---|---|
| **Intent** | Coordinate deploy-gate ownership / final-suite locks. |
| **Home** | **Local only** — `{project}/.do-work/state/gate-owner.md` (and related `state/final-suite-*.md` locks). **Never** Linear Docs, Issues, Project description, or Initiative fields. **Remains local-allowed** under Linear backend (REQ-299). |
| **Preconditions** | Milestone / gate flow active; project filesystem writable. |

**Agent sequence (backend-agnostic; same under markdown and linear):**

1. Ensure `{project}/.do-work/state/` exists (`mkdir -p`).
2. To **claim gate ownership** (concurrent serialize — REQ-299):
   - **Read** `gate-owner.md` if present.
   - If present and content (trimmed) is a **different** `AGENT_ID` → **do not overwrite**; return `{ owned: false, owner: <other> }` so the caller enters sibling idle-wait (run Step 1.0a). Concurrent gate ownership serializes via this **local** file even when milestone cursor content is remote.
   - If absent, or content is self / malformed-as-absent: write single-line local `AGENT_ID`.
   - **Re-read** after write. If contents ≠ local `AGENT_ID` → lost race; return `{ owned: false, owner: <other> }` (do not show the deploy-gate prompt).
   - If contents = local `AGENT_ID` → return `{ owned: true, owner: <self> }`.
3. To **release**: delete `gate-owner.md` when the gate resolves (y or n).
4. Final-suite coordination files under `state/` follow existing run-agent rules.
5. **Return** path written/deleted and ownership result.

| Failure | Behavior |
|---------|----------|
| Cannot write `state/` | Hard-stop gate coordination; do not invent a Linear lock substitute |
| Foreign owner already present | Yield — do not clobber; siblings idle |

This op is **not** a dual-write of work items — it is the intentional local runtime lock allowed by design §5.5 / §10 / §11 / port.md. Under Linear milestone mode, **cursor** changes go through `set_active_milestone` (Project description); **gate ownership** always goes through this local file. **Siblings idle on deploy gate the same as markdown mode** (run Step 1.0a): foreign `gate-owner.md` → poll `read_active_milestone` + local gate file until cursor advances or clears.

---

### Commits and PRs (Linear mode — design §6.5)

Runtime/git stay local. Message format uses the **Linear issue id**:

```
feat(ENG-123): short title

Issue: ENG-123
UR: UR-007
Output: path/to/primary/output
```

| Rule | Detail |
|------|--------|
| Subject scope | `feat(ENG-123):` / `fix(ENG-123):` / `chore(ENG-123):` — Linear identifier, not `REQ-NNN` |
| Footer | `Issue: ENG-123` (required); `UR: UR-NNN` when known; `Output:` primary path |
| Archive path | **No** `.do-work/archive/REQ-…` line required |
| Branch | **`req/<linear-id>`** after **Branch sanitize** (below) |
| Worktree dir | `{project}/.worktrees/req-<sanitized-lower>` (hard default lowercase; see sanitize) |
| PR title/body | Same id convention when `delivery.mode: pr` |
| Markdown backend | Unchanged: `feat(REQ-NNN):` + `REQ:` / `UR:` / `Output:` paths |

Workers and orchestrators under `backend: linear` use this convention for implementation commits and PR metadata. See `agents/run-worker.md` W2 / Step 8 and `agents/run.md` merge/archive/PR steps.

#### Branch sanitize (REQ-295)

Git refs disallow some characters. Derive branch and worktree names from the Linear issue id:

| Step | Rule | Example (`ENG-123`) |
|------|------|---------------------|
| 1. Start | Linear issue identifier as returned by Linear | `ENG-123` |
| 2. Allowed set | Keep `[A-Za-z0-9._-]` only | `ENG-123` |
| 3. Replace | Map every other character (spaces, `/`, `:`, etc.) to `-` | — |
| 4. Collapse | Collapse consecutive `-` / `.` runs; strip leading/trailing `-` and `.` | — |
| 5. Branch | `req/<sanitized-id>` (preserve identifier case as sanitized) | `req/ENG-123` |
| 6. Worktree path | **Hard default:** `{project}/.worktrees/req-<sanitized-lower>` — always lowercase the sanitized id for the directory name (FS consistency across case-sensitive/insensitive hosts). Do not keep mixed-case worktree dirs. | `.worktrees/req-eng-123` |
| 7. Empty guard | If sanitize yields empty, hard-stop (do not invent a branch name) | — |

Orchestrator merge / PR / teardown **must** use the same branch string the worker created (pass it through the worker report or reconstruct via the same sanitize function). Never mix `req/REQ-NNN` markdown naming with Linear issue ids on the same run.

---

### `unblock_req`

| | |
|---|---|
| **Intent** | Return a REQ to backlog and **release** the agent claim (markdown: strip stamp + move out of `working/`). |
| **Preconditions** | Issue is in-flight or stopped with a claim, or explicitly targeted by operator `/do-work unblock`. |
| **Does not** | Change human assignee; delete issue; auto-revert git commits (git recovery stays local/operator, same as `agents/unblock.md` judgment). |

**Agent sequence:**

1. **Rediscover** — get/update issue, list/create comments.
2. **Read** current state + active claim (for status report / audit).
3. **Release claim** — post claim-protocol comment:

   ```markdown
   <!-- do-work-claim -->
   agent_id: {prior_or_operator}
   claimed_at: {prior_claimed_at_or_now}
   heartbeat: {now_iso}
   session: {optional}
   status: released
   ```

   Prefer preserving prior `agent_id` / `claimed_at` when known so history remains readable. Latest block with `status: released` means **unclaimed**.
4. **State → backlog** — set workflow to `status_map.backlog`. **Assignee unchanged.**
5. **Do not** write local backlog files. Optional: `append_run_note` that unblock occurred.
6. **Return** issue id + released.

| Failure | Behavior |
|---------|----------|
| Issue missing | Error (“nothing to unblock”) |
| MCP missing after partial write | Hard-stop; operator re-runs unblock when healthy — do not silent-markdown |
| Comment posted but state update fails | Hard-stop with recovery: re-run unblock to set backlog |

**Parity with markdown `agents/unblock.md`:** claim cleared + status backlog + available for `list_claimable_reqs`. Git partial-commit judgment remains outside the tracker port (local).

---

### Resume (Linear — `agents/resume.md` consumer)

Resume is **not** a separate port op name; it composes `set_req_status` + `heartbeat_req` (and preserves claim ownership). Match markdown resume semantics:

| | |
|---|---|
| **Intent** | Re-dispatch work for a **stopped** REQ without unclaim / backlog round-trip. |
| **Preserves** | Active claim (`agent_id`, `claimed_at`); human assignee. |
| **Changes** | Workflow `stopped` → `in_progress`; heartbeat refreshed. |

**Agent sequence:**

1. **Rediscover** + get issue by Linear id (caller passes e.g. `ENG-123`).
2. **Confirm stopped** — workflow maps to `status_map.stopped`. If not stopped → refuse (same as markdown: only stopped REQs resume).
3. **Confirm claim** — latest claim is `status: active` (prefer same agent / operator-approved). If claim is `released` or missing → refuse; tell operator to use run/claim or unblock path, not resume.
4. **Set state** → `status_map.in_progress` (**assignee unchanged**).
5. **`heartbeat_req`** — refresh `heartbeat` now; keep `agent_id` / `claimed_at`.
6. **Return** issue id; orchestrator re-dispatches worker (worktree/branch rules stay local).

| Failure | Behavior |
|---------|----------|
| Not stopped | Refuse |
| No active claim | Refuse — not a resume candidate |
| Fresh foreign claim | `concurrent-conflict` / refuse |
| MCP missing | Hard-stop; **leave claimed** (still stopped or partial in_progress) |

---

### Status reporting (claimers / heartbeats)

**Consumer:** `agents/status.md` Step **1L** when `/do-work status` runs with `backend: linear`.

Do **not** glob `.do-work/working/` or run `lib/synth-status.sh` as the work-item store. Instead:

1. **Rediscover** list issues (scope: product Project + optional UR Project Milestone, or all UR milestones on the product Project). Prefer `list_reqs_for_ur` / list-by-project sequences already documented above.
2. For each issue with workflow in `in_progress` or `stopped` (and optionally recent `released` for audit):
   - Run **Helper: read active claim** — parse latest claim-protocol comment (`agent_claim_marker` / `<!-- do-work-claim -->`) → show **claimer** (`agent_id`), **claimed_at**, **heartbeat**, **fresh/stale** vs effective `stale_max`, claim `status`.
3. Surface **stale** active claims as warnings (parity with `lib/scan-stale.sh` / deadlock banner intent).
4. Surface **deps** from authoritative **`blocks` relations** when tools exist (body `**Depends on:**` is mirror only).
5. Never invent local REQ paths; identify rows by Linear issue id.
6. Read-only — status never posts claim comments or changes workflow state.

---

### Concurrent-conflict and mid-flight (summary)

| Event | Behavior |
|-------|----------|
| Claim re-read sees foreign **fresh** active claim | Stop `concurrent-conflict`; no assignee change; resume allowed for claim owner |
| Lost race on post-write re-read | Same stopper; do not delete the other agent’s comment |
| MCP dies after successful claim, before archive/unblock | **Leave claimed** (in_progress + active claim comment + last heartbeat); worker/orchestrator **stops**; resume or unblock after recovery |
| MCP dies mid-`archive_req` before claim release | **Leave claimed** if still active; re-run archive when healthy |
| MCP dies before claim completes | Hard-stop; no markdown substitute store |
| Silent-release or markdown fallback after claim | **Forbidden** — never auto-release claim; never switch to markdown work-item ops while `backend: linear` |
| Operator clears claim comments in Linear UI mid-run | Protocol broken — status should warn; treat as unclaimed/ambiguous and stop rather than invent state |

**Mid-flight policy (run path — REQ-294 / port):** after a successful `claim_req`, any Linear MCP failure leaves the Issue **claimed** (`status_map.in_progress` + latest claim `status: active`). The failing agent exits stopped (appropriate stopper reason). Operator recovers with `/do-work resume` or `/do-work unblock` once MCP is healthy. Same multi-agent recovery story as markdown concurrent-conflict / stale slots.

---


