# Linear port op sequences (reference)

One hop from [`agents/tracker/linear.md`](../agents/tracker/linear.md). Load when executing a named port op under `tracker.backend: linear`. Hard-stop template + status_map + hierarchy lock stay in the agent file.

**Shared agent protocol for every sequence:**

```text
1. search_tool "<linear-scoped query for this need>"
2. If zero Linear tools / no matching capability → HARD STOP (linear.md setup block; no dual-write)
3. use_tool with qualified name + exact input_schema from search
4. On tool error / team unresolved → HARD STOP; do not invent data
```

**Search query hints (not proven tool names):** `"linear team"`, `"linear project"`, `"linear milestone"`, `"linear create issue"`, `"linear list issues"`, `"linear update issue"`, `"linear label"`, `"linear status"`, `"linear comments"`, `"linear document"`.

## Hierarchy (apply to every op)

```
Team (config)
└── Project product_project  — one shared product Project per local product (not per UR)
    ├── Project Milestone (UR)  — §9.1 <!-- do-work-ur -->; brief, ideate, verify, close
    └── Issue (REQ)             — on product Project, attached to UR milestone
        └── Sub-issue (layer child)
```

**Product Project naming:** `tracker.linear.product_project` defaults to **empty** (not skill name `do-work`). Resolve order is documented under `ensure_product_container` / `agents/config.md` Load Config step 8. Example for the do-work skill repo itself may still use name `do-work`.

**No Initiative-as-UR.** Path-milestone mode (M1/M2) is a *cursor + Issue markers* on the UR milestone — see [linear-path-milestones.md](linear-path-milestones.md).

---

## Templates (design §9)

Bodies are **markdown conventions** in Linear description fields — not custom Linear fields. Prefer description appends; fall back to UR Project Milestone/Issue **comments** if description size limits require it (record a one-line pointer in the section when spilling).

**Machine markers (required):**

| Entity | Marker (first non-empty line of structured body) | Op consumers |
|--------|--------------------------------------------------|--------------|
| UR Project Milestone | `<!-- do-work-ur -->` | `create_ur`, `read_ur`, `list_urs`, `append_ideate`, `append_clarifications`, verify/close writers |
| Issue (REQ) | `<!-- do-work-req -->` | `create_req`, `update_req`, `read_req`, `set_files`, `set_blocked_by`, `claim_req` / `heartbeat_req` / `unblock_req` / `set_req_status`, archive later |

On **read/update**: if the marker is missing, treat as template parse failure → **stop the op**; do not invent headers or rewrite the body into template form without an explicit migrate path.

### §9.1 UR Project Milestone description template

```markdown
<!-- do-work-ur -->
**UR-id:** UR-007
**Class:** feature
**Created:** YYYY-MM-DD
**Product-project:** do-work
**Product-project-id:** {linear-project-uuid}
**Milestone-id:** {linear-milestone-uuid}

## Brief
{verbatim intake}

## Clarifications

## Ideate

## Open gaps

## Capture summary

## Verify

## Closure
```

#### §9.1 field semantics

| Field / section | Write rules | Readers |
|-----------------|-------------|---------|
| `<!-- do-work-ur -->` | Must be present at create; never strip | All UR ops |
| `**UR-id:**` | Sequential `UR-NNN` slug only (not a Linear entity id) | Resolve UR; `list_urs` |
| `**Class:**` | Intake classification (feature / …) | Capture, status |
| `**Created:**` | ISO date `YYYY-MM-DD` at create | Display |
| `**Product-project:**` | Shared product Project **display name** after ensure (from bound Project; not a hard-coded skill default) | Display; prefer id for resolve |
| `**Product-project-id:**` / `**Milestone-id:**` | Linear UUIDs after ensure + milestone create | Prefer ids over names |

| `## Brief` | **Verbatim** intake — never overwrite on ideate/question | `read_ur` |
| `## Clarifications` | `append_clarifications` appends Q&A; does not create REQs | Question, capture |
| `## Ideate` | `append_ideate` writes/appends ideate body | Ideate, capture |
| `## Open gaps` / `## Capture summary` | Capture phase | Capture, verify |
| `## Verify` / `## Closure` | `write_verify_report` / `write_close_report` (REQ-296) | Verify, close, go |

### §9.2 Issue (REQ) description template

```markdown
<!-- do-work-req -->
**UR:** UR-007
**Layer:** agents | none | …
**Parent:** ENG-100 | none
**Entry point:** …          # path-unit parents only
**Terminal state:** …       # path-unit parents only
**Milestone:** M1           # milestone mode only; omit or `none` otherwise
**Files:** path1 path2
**Depends on:** ENG-101 ENG-102
**Size:** S|M|L
**Priority:** 1-3
**Criteria approved:** agent-drafted
**Closure proof:**
**Suite:**

## Task

## Acceptance Criteria
- [ ] …

## Verification Steps
1. …

## Integration

## Manual checks (advisory)
- [ ] …

## Outputs
```

#### §9.2 field semantics

| Field / section | Write rules | Readers |
|-----------------|-------------|---------|
| `<!-- do-work-req -->` | Required at create; never strip | All REQ ops |
| `**UR:**` | Owning UR slug | `list_reqs_for_ur` cross-check; display |
| `**Layer:**` | Layer name or `none`; also label `Layer/{name}` when labels available | Capture, footprint |
| `**Parent:**` | Parent **Linear issue id** or `none`; children also set native `parentId` | Path-units |
| `**Entry point:**` / `**Terminal state:**` | Path-unit **parents only**; leave empty on leaves | Capture path-units |
| `**Milestone:**` | Milestone mode only: `M<n>` (e.g. `M1`); omit or `none` otherwise; also label `M<n>` when labels available (REQ-298) | `list_milestone_reqs` |
| `**Files:**` | Space-separated paths/globs; sole write intent of `set_files` | Footprint / pick |
| `**Depends on:**` | Space-separated **Linear issue ids** — **mirror only**; authoritative graph is native `blocks` relations via `set_blocked_by` | Display; eligibility uses relations when present |
| `**Size:**` | `S` \| `M` \| `L`; also label `Size/{S\|M\|L}` when labels available | Capture; optional estimate map |
| `**Priority:**` | `1`–`3` (or empty) | Capture / pick display |
| `**Criteria approved:**` | Provenance only (`agent-drafted` / human…) | Workers |
| `**Closure proof:**` / `**Suite:**` | Set by archive/orchestrator path | Archive integrity |
| `## Task` … `## Outputs` | Capture / worker sections; preserve unknown sections on update | Workers, review |

### Labels (`tracker.linear.labels.*`)

When label tools are discoverable (create/list/attach), agents **must** keep labels aligned with body headers on create/update:

| Config key | Default | Applied as | When |
|------------|---------|------------|------|
| `labels.layer_prefix` | `Layer/` | `Layer/{name}` e.g. `Layer/agents` | Every Issue with a non-empty `**Layer:**` (skip or omit for `none` if team convention prefers no label) |
| `labels.size_prefix` | `Size/` | `Size/S`, `Size/M`, `Size/L` | Every Issue with `**Size:**` set |
| `labels.path_unit` | `path-unit` | Exact label name `path-unit` | Path-unit **parent** Issues only (not layer children) |

**Rules:**

1. Resolve or create labels via live tools only; never invent label UUIDs.
2. Body headers remain the parse source if labels are missing tools — still write headers.
3. `ensure_product_container` may pre-create common labels when create-label tools exist.
4. Estimate: if the team uses T-shirt estimates and tools allow, map Size → estimate **after** body/label write; estimate is optional display, not the footprint source.

### States (`tracker.linear.status_map`)

| do-work status | Config key | Default Linear state name |
|----------------|------------|---------------------------|
| backlog | `status_map.backlog` | `Todo` |
| in_progress | `status_map.in_progress` | `In Progress` |
| stopped | `status_map.stopped` | `Canceled` |
| done | `status_map.done` | `Done` |

**Hard-fail validation (when `backend: linear`):**

1. At preflight (before first CRUD op in a session), list team workflow states via discovered tools.
2. For **every** key in `status_map` (defaults filled if omitted), the Linear state **name** must exist on the team.
3. If any mapped name is missing → **hard-stop** with rename-or-override instructions (setup block). **Never** invent states; **never** pick a “close enough” name; **never** fall back to markdown.
4. Create/update ops that set status use the **validated** state id for the mapped name only.

### Deps dual-write (template + relations)

| Concern | Rule |
|---------|------|
| Authoritative graph | Native Linear **`blocks` relations** (this issue is blocked by dependency issues) |
| Body mirror | `**Depends on:** ENG-101 ENG-102` (Linear issue ids only — never markdown `REQ-NNN`) |
| Writer | Prefer `set_blocked_by` for sole intent; `create_req` may set deps at create the same way |
| Diverge | Relations win for `list_claimable_reqs` / deps checks |
| Relations tools missing | Body-only deps + **one-time** warning; still no markdown dual-store; document GraphQL fallback if spike later marks relations **missing** |

### Path-units

- **Parent Issue:** §9.2 with `**Entry point:**` / `**Terminal state:**`; label `path-unit` when available; no required `parentId`.
- **Layer children:** Linear `parentId` (or schema field from live create-issue tool) = parent Linear id; body `**Parent:**` = same id; layer label when available; leave entry/terminal empty.

---

## UR/REQ CRUD sequences

**Shared agent protocol for every step below:**

```text
1. search_tool "<linear-scoped query for this need>"
2. If zero Linear tools / no matching capability → HARD STOP (setup block; no dual-write)
3. use_tool with qualified name + exact input_schema from search
4. On tool error / team unresolved → HARD STOP; do not invent data
```

**Search query hints (not proven tool names):** use queries such as `"linear team"`, `"linear initiative"`, `"linear project"`, `"linear create issue"`, `"linear list issues"`, `"linear update issue"`, `"linear label"`, `"linear status"`. Map hits to the step’s need. Skill “typical tools” tables are **candidates to search for**, never hard-coded as proven.

**Id rules:**

| Entity | Id form |
|--------|---------|
| UR slug | Sequential `UR-NNN` (UR Project Milestone metadata only) |
| REQ | **Linear issue identifier only** (e.g. `ENG-123`) — never allocate `REQ-NNN` under Linear backend |
| Product Project | `tracker.linear.product_project` — shared for all URs on this local product; **name or UUID**; empty default; resolve chain + ensure persist UUID (never invent skill name `do-work`) |
| UR milestone name | `tracker.linear.ur_milestone_name_pattern` (default `{ur_id}: {title}`) |


### Preflight (before first CRUD op in a session)

1. Config effective backend is `linear` (else do not use this file).
2. `search_tool "linear"` (or `"linear team"`) — must return Linear MCP tools; else hard-stop.
3. Resolve team: config `tracker.linear.team_id` and/or `team_key` via discovered team list/get tools. Unresolved → hard-stop (do not guess).
4. Validate every `status_map` value exists on the team workflow (discovered status-list tool). Missing name → hard-stop with rename/override instructions.
5. Cache team id, status ids for mapped states, and (optionally) label ids for the session.

### `ensure_product_container`

| | |
|---|---|
| **Intent** | Team resolvable; ensure the shared **product Project** for this local product (not per UR); optional labels ready. Create/bind when missing; **always persist** Project UUID to `tracker.linear.product_project`. |
| **Preconditions** | Preflight steps 2–4 done (MCP tools, team resolved, `status_map` validated). Config loaded (`agents/config.md`). |
| **Failure** | Hard-stop on empty-name, multi-match, tool missing, create/get failure. **Never** create markdown `.do-work/` as substitute product container. **Never** invent Initiatives as UR containers. **Never** fall through to skill name `do-work` for empty `product_project`. |

**Agent sequence (executable):**

1. **Resolve target name/id (lookup key)** — same chain as `agents/config.md` Load Config step 8; do **not** invent a different order:
   1. Let `pp` = `tracker.linear.product_project` (missing / null / whitespace-only → empty).
   2. If `pp` is **non-empty** (name **or** UUID) → **lookup key = `pp`**. Explicit config wins; do not replace with `project.name`, basename, or skill name `do-work`.
   3. If `pp` is **empty** → lookup key = `project.name` when non-empty; else **git-root directory basename**.
   4. If the final lookup key is still empty/whitespace → **hard-stop** (**empty-name**): instruct operator to set `project.name` or `tracker.linear.product_project` in `{project}/.do-work/config.yml`. Do **not** invent a name. Do **not** markdown-fallback.
2. **Rediscover project tools** — `search_tool` for Linear project surfaces (`"linear project"`, `"linear list projects"`, `"linear save project"` / create-project). Map hits to list/get/create. If list/get (and, for name create path, create/`save_project`) tools are undiscoverable → **hard-stop** (setup block). Never hard-code tool names; use qualified names + `input_schema` from search.
3. **Resolve or create on the team**
   - **UUID path** (lookup key is already a Project UUID / id form): `use_tool` get-project (or list filtered by id). Found → use that Project. Not found → **hard-stop** (do not invent; do not create a Project whose name is the UUID string).
   - **Name path** (lookup key is a display name):
     1. `use_tool` list-projects scoped to the **resolved team** (team id/key from preflight). Prefer `query` / name filter when the schema supports it; otherwise list and filter client-side.
     2. Keep **exact name matches** (case-sensitive unless the live tool documents otherwise) on that team.
     3. **Match count:**
        - **0** → **create** via rediscovered create/save-project surface (`save_project` when discovered): `name` = lookup key; attach team with `addTeams` **or** `setTeams` = resolved team (schema requires at least one team). Capture returned Project UUID.
        - **1** → **use** that Project (id + name).
        - **>1** → **hard-stop** (**multi-match**): list matching ids/names; require operator to set `tracker.linear.product_project` to the desired **UUID**. Do not pick “first”; do not invent; no markdown fallback.
4. **Persist UUID** — **always** write the resolved Project **UUID** to `tracker.linear.product_project` in `{project}/.do-work/config.yml` and in-memory config. If the file already stores that same UUID, skip the write (idempotent). Prefer UUID over name for all subsequent ops in the session.
5. **Optional labels** — when create/list label tools exist, pre-create common labels (`labels.layer_prefix`, `size_prefix`, `path_unit`) for the team. Label failure is non-fatal for container ensure (body headers remain source of truth); project ensure itself must already have succeeded.
6. **Return** product Project **id (UUID)** + **name**. Cache for the session.

**Does not:** create a UR or REQ; create a per-UR Linear Project; create Initiatives; write local UR/REQ markdown as the store.

### `create_ur`

| | |
|---|---|
| **Intent** | Record intake brief as a **UR Project Milestone** on the shared **product Project**. Does **not** create REQs. **Not** Initiative-as-UR. **Not** a new Linear Project per UR. |
| **Preconditions** | Preflight passed; `ensure_product_container` done; next `UR-NNN` slug allocatable. |
| **Atomicity** | Product Project resolvable + Project Milestone create must succeed as one logical unit. **No partial UR.** |

**Agent sequence:**

1. **Ensure product Project** — call **`ensure_product_container`** first (resolve chain + list/create/bind + persist UUID). Do **not** restate a hard-coded product name here; do **not** create a per-UR Project.
2. **Allocate next `UR-NNN` slug**
   - `search_tool` for project milestones list tools (`"linear milestones"`, `"linear project milestones"`).
   - List milestones on the product Project; scan names / descriptions for `UR-*` / `**UR-id:** UR-*` / `<!-- do-work-ur -->`.
   - Pick next free sequential `UR-NNN`.
3. **Build body**
   - Milestone name: apply `tracker.linear.ur_milestone_name_pattern` (default `{ur_id}: {title}`, e.g. `UR-007: Add SSO`).
   - Description: §9.1 template with verbatim brief; `**Product-project:**` + product project name; `**Product-project-id:**` from ensure; leave `**Milestone-id:**` empty until create returns it.
4. **Create Project Milestone** on the product Project
   - `search_tool "linear milestone"` / create-milestone surface.
   - If **no** milestone create tool is discovered → **hard-stop** (do **not** invent Initiative-as-UR; do **not** create a per-UR Project as a fake UR).
   - `use_tool` create with discovered schema (project id + name + description as required).
   - Record milestone id; patch `**Milestone-id:**` if update tools allow.
5. **Return** UR slug, product project id/name, milestone id/name. **Do not** write `.do-work/user-requests/UR-NNN/`. **Do not** create Linear Initiatives. **Do not** create a Linear Project per UR.

### `read_ur`

| | |
|---|---|
| **Intent** | Load brief + attached sections (ideate, clarifications, verify, closure if present). |
| **Sequence** | 1) Resolve product Project (`product_project`). 2) List Project Milestones; match `UR-NNN` via name pattern / `**UR-id:**` / marker. 3) Get/read milestone description (and comments if sections spilled). 4) Parse §9.1 markers. |
| **Failure** | Unknown UR → error to caller; MCP missing → hard-stop. |

### `list_urs`

| | |
|---|---|
| **Intent** | Enumerate URs (ids + titles) for prompts/status. |
| **Sequence** | `search_tool` → list Project Milestones on product Project; keep those with `<!-- do-work-ur -->` / `**UR-id:**` / matching `ur_milestone_name_pattern`. Return `UR-NNN` + title; use `read_ur` for full body. |
| **Failure** | MCP missing → hard-stop. |

### `create_req`

| | |
|---|---|
| **Intent** | Create one backlog REQ (Issue) on the product Project, attached to the UR Project Milestone. Optional path-unit parent + layer children as sub-issues. |
| **Preconditions** | UR Project Milestone exists on product Project (from `create_ur` or resolve); preflight passed. |
| **Id rule** | Resulting id is the **Linear issue id only** (e.g. `ENG-123`). **Never** allocate `REQ-NNN`. |

**Agent sequence:**

1. Resolve **product Project id** + **UR Project Milestone id** (`search_tool` + list/get). Missing either → hard-stop or fail create (UR incomplete).
2. Resolve **backlog** workflow state id from `status_map.backlog` (default `"Todo"`) via discovered status tools.
3. Build Issue **description** from §9.2 with capture fields (`**UR:**`, layer, files, depends-on Linear ids, size, priority, task, AC, verification, …). Titles short and actionable.
4. **Path-unit parent** (if this REQ is a path-unit):
   - Create parent Issue first: team + project + title + §9.2 body (`**Entry point:**` / `**Terminal state:**` filled); labels include `path-unit` when label tools exist.
   - For each layer child: create Issue with `parentId` (or schema field returned by live create-issue tool) set to parent Linear id; body `**Parent:** ENG-…`; layer label when available.
5. **Standalone / leaf REQ:**
   - `search_tool "linear create issue"` (or `"linear issues"`).
   - If create-issue undiscoverable → **hard-stop** (no markdown dual-write).
   - `use_tool` create: team, project=product Project, milestone=UR Project Milestone, title, description, state=backlog map, optional assignee=`default_assignee_id`, labels, `parentId` when child.
6. **Deps at create (optional):** if dependency Linear ids are known, run the same dual-write as **`set_blocked_by`** (native `blocks` relations when tools exist **and** body `**Depends on:**` mirror). If relations missing → body-only + one-time warning (port rule).
7. **Labels:** attach `Layer/{name}`, `Size/{S|M|L}`, and `path-unit` (parents only) per **Labels** table when label tools exist.
8. **State:** create in `status_map.backlog` only (validated id from preflight) — never invent a state name.
9. Return Linear issue id(s). Human assignee only from config — agents do not steal assignee for claim (see **Claim protocol**).

### `update_req`

| | |
|---|---|
| **Intent** | Edit Issue body/fields without claim/archive lifecycle. Prefer dedicated ops for status, deps, footprint, claim when those are the sole intent. |
| **Sequence** | 1) `search_tool` + get issue by Linear id. 2) Require `<!-- do-work-req -->`; merge structured header / section edits into §9.2 description (preserve unknown sections). 3) `search_tool` + update issue with only changed fields (title, description, labels, project, parent). 4) **Deps sole intent → use `set_blocked_by`** (do not half-update relations). 5) **Footprint sole intent → use `set_files`**. 6) If a broader body edit also changes deps/files, after description update run the same dual-write / header rules as those ops. |
| **Failure** | Issue missing → error; missing machine marker / unparsable required fields → stop op (do not invent); MCP missing → hard-stop. |

### `read_req`

| | |
|---|---|
| **Intent** | Load full REQ (headers + body sections). |
| **Sequence** | `search_tool` → get issue by Linear id (e.g. `ENG-123`). Parse `<!-- do-work-req -->` headers and sections. Optionally list children if path-unit parent. Map Linear workflow state name back through `status_map` for do-work status display. |
| **Failure** | Unknown id → error; MCP missing → hard-stop. |

### `list_reqs_for_ur`

| | |
|---|---|
| **Intent** | All REQs for a UR, any status — Issues on product Project with that UR Project Milestone. |
| **Sequence** | 1) Resolve product Project + UR Project Milestone. 2) `search_tool "linear list issues"`. 3) List Issues filtered by **product project** and **UR milestone** (not global team backlog alone). 4) Return Linear ids + titles + states (+ parentId if present). |
| **Notes** | UR Project Milestone membership is the scope. Do not scan local `.do-work/REQ-*`. |
| **Failure** | UR milestone missing → empty or error; MCP missing → hard-stop. |

### `append_ideate`

| | |
|---|---|
| **Intent** | Append or write ideate content onto an existing UR Project Milestone — **without** overwriting `## Brief`. |
| **Preconditions** | Preflight passed; UR exists (Project Milestone with §9.1 marker + `**UR-id:**`). |
| **Does not** | Create REQs, Projects, or local `ideate.md` files. |

**Agent sequence:**

1. **Rediscover** — `search_tool "linear milestone"` / `"linear project milestones"` (and/or get/update milestone). Zero tools → hard-stop (setup block).
2. **Resolve Initiative** for `UR-NNN` (same as `read_ur`: scan Initiatives for `**UR-id:**` / Project `do-work/{UR-id}` → linked initiative).
3. **Read** current description (and comments if sections spilled). Require `<!-- do-work-ur -->`.
4. **Locate `## Ideate`** section:
   - If present and empty → replace section body with ideate markdown.
   - If present and non-empty → **append** new ideate content (prefer dated subheading or clear separator); do not delete prior ideate unless the phase explicitly replaces.
   - If missing → insert `## Ideate` after `## Clarifications` (or after `## Brief` if clarifications absent), preserving order of other §9.1 sections.
5. **Never** modify `## Brief` verbatim intake.
6. **Write** — `use_tool` update milestone description with the merged markdown. If description hits size limits → post overflow as Initiative comment titled/tagged for ideate and leave a one-line pointer under `## Ideate`.
7. ****Return** UR slug + milestone id + product project id. No `.do-work/user-requests/` write.

| Failure | Behavior |
|---------|----------|
| UR / milestone not found | Error to caller |
| Marker missing / unparsable | Stop op; do not invent template |
| MCP / update tool missing | Hard-stop |

### `append_clarifications`

| | |
|---|---|
| **Intent** | Append question-phase Q&A onto the UR under `## Clarifications`. Does **not** create REQs. |
| **Preconditions** | Preflight passed; UR exists. |
| **Does not** | Overwrite `## Brief`; replace prior Q&A wholesale (append only). |

**Agent sequence:**

1. **Rediscover** — `search_tool` for milestone get/update (same surface as `append_ideate`).
2. ****Resolve + read** UR Project Milestone; require `<!-- do-work-ur -->`.
3. **Locate `## Clarifications`**:
   - Append each Q&A as:

     ```markdown
     **Q:** {question}
     **A:** {answer}
     ```

   - Keep prior entries. If section missing, insert after `## Brief` before `## Ideate`.
4. **Write** updated description via discovered update tool (comment spill same as ideate if needed).
5. ****Return** UR slug + milestone id.

| Failure | Behavior |
|---------|----------|
| UR missing | Error to caller |
| Marker missing | Stop op |
| MCP missing | Hard-stop |

### `set_blocked_by`

| | |
|---|---|
| **Intent** | Write the depends-on graph for a REQ: **authoritative** native `blocks` relations **and** body `**Depends on:**` mirror. |
| **Preconditions** | Preflight passed; target Issue exists; dependency ids are Linear issue ids (or empty list to clear). |
| **Ids** | Linear identifiers only (e.g. `ENG-101`). **Never** markdown `REQ-NNN`. |
| **Authority** | Relations win on diverge (port **Deps authority**). Eligibility consumers use relations when present. |

**Agent sequence:**

1. **Rediscover** — `search_tool` for: get/update issue; issue **relations** create/list/delete (queries such as `"linear issue relations"`, `"linear blocks"`, `"linear dependencies"`). Map hits to create/remove `blocks` edges only with **observed** tool names + schemas.
2. **Read issue** by Linear id. Require `<!-- do-work-req -->`. Parse current `**Depends on:**` and existing relations if list tools exist.
3. **Normalize target set** — caller supplies ordered/unordered list of blocker issue ids (issues that **block** this issue / this issue depends on). Empty list = clear all deps.
4. **Relations path (when create/list/delete relation tools discovered):**
   - List existing `blocks` relations involving this issue (schema-dependent: type `blocks` / blockedBy — use fields from live schema).
   - **Remove** relations whose other end is not in the target set (only deps edges this op owns; do not delete unrelated relation types).
   - **Add** `blocks` relations for each target id missing an edge. Direction: dependency **blocks** the current issue (current issue is blocked by deps) — match Linear’s relation model from live schema docs on the tool; if ambiguous after schema read, hard-stop with gap note rather than guessing both directions.
   - On partial relation write failure → hard-stop; do not leave body claiming success without relations if tools were supposed to run.
5. **Body mirror (always when description is writable):**
   - Set header `**Depends on:**` to space-separated target Linear ids (or empty / omit value when cleared).
   - Preserve all other §9.2 headers and sections.
   - `search_tool` + update issue description.
6. **Relations tools missing after live probe:**
   - Write body mirror only.
   - Emit **one-time warning** to the caller/session: relations unavailable; body is sole store until tools appear; eligibility must treat body as fallback (port rule). Still **no** markdown dual-write.
   - Prefer documenting GraphQL/API fallback in this file when spike marks the cell **missing** (not **unknown**).
7. **Return** issue id + final depends-on id list + whether relations were written.

| Failure | Behavior |
|---------|----------|
| Issue missing | Error to caller |
| Invalid / unresolvable dependency id | Error; do not write partial graph |
| Marker missing | Stop op |
| MCP missing | Hard-stop |
| Relation tool error mid-write | Hard-stop; operator may re-run op to reconcile |

### `set_files`

| | |
|---|---|
| **Intent** | Set the footprint list (`**Files:**`) on a REQ Issue. Does **not** claim, unclaim, or change workflow status. |
| **Preconditions** | Preflight passed; Issue exists. |
| **Notes** | Overlap vs other in-flight REQs is evaluated later by `list_claimable_reqs` / claim consumers — this op only writes the declaration. |

**Agent sequence:**

1. **Rediscover** — `search_tool "linear update issue"` / `"linear issues"`; get + update tools required.
2. **Read issue** by Linear id. Require `<!-- do-work-req -->`.
3. **Set header** `**Files:**` to the caller’s space-separated path list (empty clears footprint). Do not invent paths. Preserve all other headers/sections and the machine marker.
4. **Write** description via `use_tool` update. Labels/status/assignee unchanged unless a future combined op says otherwise.
5. **Return** issue id + files list.

| Failure | Behavior |
|---------|----------|
| Issue missing | Error to caller |
| Marker missing / unparsable | Stop op |
| MCP / update missing | Hard-stop |

### Hard-stop at create/update time (CRUD-specific)

| Condition | Behavior |
|-----------|----------|
| Linear MCP tools undiscoverable at `create_ur` / `create_req` / append / `set_*` | Hard-stop + setup instructions; **no** Initiative-as-UR, **no** Issue invent, **no** markdown dual-write |
| `team_id` / `team_key` unresolved | Hard-stop; do not guess |
| Product Project ok, milestone create fail | Hard-stop; no partial UR; operator recovery for orphan milestone if any |
| Create-issue tools missing | Hard-stop; do not write `.do-work/REQ-*` |
| Template required fields unparsable on update/read | Stop the op; do not invent fields (port / design §14) |
| Missing `<!-- do-work-ur -->` / `<!-- do-work-req -->` on structured write | Stop the op; do not auto-rewrap without explicit migrate |
| Any `status_map` state name missing on team workflow | Hard-stop + rename/override instructions; never invent states |

---



---

## Non-ticket artifact homes (design §10 — REQ-296)

Agents **must not invent** homes. Use only the rows below (plus local gate locks). Config titles are authoritative when set.

| Artifact | Linear home | Format | Writers / readers | Port op / sequence |
|----------|-------------|--------|-------------------|--------------------|
| Decisions | Team Doc title = `tracker.linear.decisions_doc_title` (default **`do-work/decisions`**) | One line per decision: `YYYY-MM-DD \| UR/REQ ref \| decision \| rationale` | capture write; capture / ideate / question / worker read | **`append_decision`**; **Read decisions** helper |
| Calibration | Team Doc title = `tracker.linear.calibration_doc_title` (default **`do-work/calibration`**) | Full calibration body (same shape as markdown `state/calibration.md`) | retro write (full replace); capture read | **Write / read calibration Doc** |
| Run / cost notes | Comment on Issue after attempt; optional Project update for run rollup | YAML fenced block + `<!-- do-work-run-note -->` | run | **`append_run_note`** (REQ-294) |
| Verify report | UR Project Milestone description `## Verify` + milestone comment | Full report markdown | verify, go | **`write_verify_report`** |
| Close report | UR Project Milestone description `## Closure` + milestone comment | Per path-unit results (closure schema) | close | **`write_close_report`** |
| Path-milestone cursor (M1/M2) | UR Project Milestone description `<!-- do-work-milestone -->` | active M + checklist | capture, run | **`read_active_milestone`** / **`set_active_milestone`** / **`list_milestone_reqs`** (REQ-298 path; **REQ-299** ops) |
| Gate locks | **Local** `{project}/.do-work/state/gate-owner.md`, `final-suite-*.md` | unchanged | run | **`write_gate_state`** (local only; REQ-299 concurrent serialize) |

**Create-if-missing (Team Docs):** on first write, if no Doc with the configured title exists for the configured team, create it (title exact match to config), then write. Readers: if missing, treat as empty (no decisions / no calibration) — never invent content.

**Hard-stop (REQ-296 / REQ-297):** if Docs tools (for decisions/calibration) or UR Project Milestone update/comment tools (for verify/close) are undiscoverable after `search_tool`, **or** Team Doc create/update fails (permission, size, MCP error), **or** milestone description append/update fails **and** the §10 milestone-comment path also fails — hard-stop that op with Linear setup / permission instructions. Do **not**:

- fall back to local `.do-work/decisions.md` / `state/calibration.md` / `closure.md` as the work-item store
- invent alternate Doc titles outside `decisions_doc_title` / `calibration_doc_title`
- invent ad-hoc Issue comments (or Project updates) as a substitute home for decisions, calibration, verify, or close reports

§10-allowed UR Project Milestone comment for the full verify/close body (with a section pointer) remains valid when description size alone fails.

---



---

## Claim protocol (design §8 — Linear representation)

Semantics: `port.md` **Claim / Mid-flight MCP failure**. Linear has **no** filesystem atomic rename — atomicity is **optimistic re-read + comment protocol + timestamps** (intentional; same multi-agent recovery story as markdown concurrent-conflict).

### Config keys (consumers)

| Key | Default | Role |
|-----|---------|------|
| `tracker.linear.agent_claim_marker` | `<!-- do-work-claim -->` | First line of every claim-protocol comment |
| `tracker.linear.heartbeat_max_age_seconds` | `null` | Max age of latest **active** heartbeat before stale; **`null` → use `parallel.stale_threshold_seconds`** |
| `parallel.stale_threshold_seconds` | `900` | Fallback stale threshold (seconds) |
| `tracker.linear.status_map.backlog` | `Todo` | Unclaimed / unblocked |
| `tracker.linear.status_map.in_progress` | `In Progress` | Claimed / running / resumed |
| `tracker.linear.status_map.stopped` | `Canceled` | Stopped (claim retained until unblock) |
| `tracker.linear.default_assignee_id` | `""` | Human operator; set on issue **create** only — claim ops never overwrite |

**Effective stale max age:**

```
stale_max = tracker.linear.heartbeat_max_age_seconds
if stale_max is null or missing:
  stale_max = parallel.stale_threshold_seconds   # default 900
```

A claim is **stale** when the latest **active** claim block’s `heartbeat` ISO timestamp is older than `stale_max` seconds relative to now (UTC).

### Human assignee vs agent claim

| Field | Owner | Rule |
|-------|-------|------|
| Linear **assignee** | Human operator | Set from `default_assignee_id` on `create_req` when configured. **Agents never change assignee** for claim, heartbeat, unblock, resume, or status. |
| Workflow **state** | Agent claim lifecycle | Maps via `status_map` (backlog / in_progress / stopped / done). |
| Claim **comment** | Agent | `agent_claim_marker` block with `agent_id`, timestamps, `status: active\|released`. |

Warn operators (status / docs): **do not clear agent claim comments while a run is live** — clearing them breaks multi-agent coordination the same way deleting a markdown claim stamp would.

### Claim comment body (canonical)

Marker text must equal config `agent_claim_marker` (default shown):

```markdown
<!-- do-work-claim -->
agent_id: hostname.pid
claimed_at: 2026-07-31T12:00:00Z
heartbeat: 2026-07-31T12:05:00Z
session: optional-uuid
status: active
```

| Field | Required | Notes |
|-------|----------|-------|
| marker line | yes | Exactly `tracker.linear.agent_claim_marker` |
| `agent_id` | yes | Stable per worker (e.g. `hostname.pid` or orchestrator session id) |
| `claimed_at` | yes on first claim | ISO-8601 UTC; preserve on heartbeat/resume |
| `heartbeat` | yes | ISO-8601 UTC; consumers take the **latest** active block |
| `session` | optional | UUID or run id for triage |
| `status` | yes | `active` (held) or `released` (unblocked / voluntarily dropped) |

**Parse rules:**

1. List issue comments (discovered tools). Consider only comments whose body **starts with** (or whose first non-empty line is) `agent_claim_marker`.
2. Parse key: value lines case-sensitively for keys above.
3. **Latest active claim** = among comments with `status: active` (or missing status treated as active only if `agent_id` + `heartbeat` present — prefer explicit `status:`), the one with the newest `heartbeat` (tie-break: newest comment created_at).
4. A claim with `status: released` is **not** active.
5. If multiple agents have concurrent `active` comments, the one with the newest **fresh** heartbeat wins for “who holds”; a second agent attempting claim while another is fresh → **concurrent-conflict**.

> **Heartbeat intent (F5 / parity with sqlite).** `heartbeat_req` **patches the existing active claim comment in place**; it does not mint a new claim per heartbeat. The “latest active block” resolution in rules 3–5 exists so a stale or fallback comment never strands coordination — it is a safety net, not license to post a new comment each heartbeat. See `heartbeat_req` step 3 and field-lessons §2.

### Concept → Linear mapping

| Concept | Linear rule |
|---------|-------------|
| **Unclaimed** | Workflow maps to `status_map.backlog` **and** no **active** claim comment (or latest claim is `released`) |
| **Claim** | Re-read issue + comments; if another agent has active claim with **fresh** heartbeat → fail; else set state → `in_progress`; post claim comment (`status: active`) |
| **Heartbeat** | **Patch the existing active claim comment in place** (update-comment tool, e.g. `save_comment` with its id) — primary; refreshes `heartbeat` on the existing claim (parity with sqlite's heartbeat UPDATE). Post a new claim-protocol comment **only as a fallback** when the MCP surface exposes no update-comment tool. Consumers take the latest active block |
| **Stale** | Latest active `heartbeat` older than effective `stale_max` — eligible for takeover / reclaim under multi-agent rules |
| **Unblock** | State → `backlog`; post/update claim comment `status: released` (assignee unchanged) |
| **Resume** | `stopped` → `in_progress`; refresh heartbeat on **same** `agent_id` / claim ownership; assignee unchanged |
| **Concurrent conflict** | Same stopper as markdown multi-agent: stop with `concurrent-conflict`; `/do-work resume` allowed when claim still held |
| **Mid-flight MCP death** | **Leave claimed** — do not force backlog or invent cleanup; resume/unblock after MCP recovers |

### Helper: read active claim (shared)

Used by claim, heartbeat, list_claimable, status, unblock, resume:

1. `search_tool` for issue get + list comments (e.g. `"linear issue comments"`, `"linear comments"`).
2. Get issue by Linear id; read workflow state name → map through inverted `status_map`.
3. List comments; filter + parse claim blocks (above).
4. Return: `{ agent_id, claimed_at, heartbeat, session, status, fresh: bool, stale: bool }` for the latest active claim, or empty if none.
5. `fresh` = active and age(heartbeat) ≤ `stale_max`. `stale` = active and age > `stale_max`.

If comment tools are undiscoverable → **hard-stop** (claim protocol cannot run); never invent comments or fall back to markdown working/.

---

### `list_claimable_reqs`

| | |
|---|---|
| **Intent** | Return REQs that are backlog, deps-satisfied, footprint-free, and unclaimed (or stale-eligible) — in pick order. **Does not claim.** |
| **Preconditions** | Preflight passed; Product Project + optional UR milestone scope known (optional `UR-NNN` / milestone id). |
| **Authoritative deps** | Native **`blocks` relations** (port). Body `**Depends on:**` is mirror only. |
| **Ids** | Linear issue ids only. |
| **v1 lib** | Implemented as agent/MCP steps only — **not** `lib/pick-req.sh` (markdown). No Linear-aware bash required. |

**Pick order (REQ-295 — deterministic first-survivor):**

Sort candidates **before** filtering, then walk in order and return the first survivor (orchestrator typically takes head of the ordered claimable list). Tie-break ladder:

| Rank | Key | Direction | Source |
|------|-----|-----------|--------|
| 1 | `**Priority:**` | **descending** numeric (`3` most urgent before `1`); missing/empty/malformed → treat as **`2`** (same default as `lib/pick-req.sh` / capture) | Issue body header |
| 2 | `created_at` | ascending (older first) | Linear issue create timestamp |
| 3 | Linear identifier | ascending lexicographic (`ENG-12` before `ENG-100` only if string sort; prefer natural numeric suffix when practical) | e.g. `ENG-123` |

Milestone / scope filters (when caller passes them) apply **before** the walk: only issues on the scoped UR Project Milestone / path-milestone marker are candidates.

**Skip reasons (emit one line per rejected candidate — drain-classify parity):**

| Reason token | When | Run-loop mapping (`drain-classify` intent) |
|--------------|------|---------------------------------------------|
| `scope:<id>` | Caller scope (UR Project / milestone) excludes the issue | `scope-blocked` |
| `claim:<id>` | Active **fresh** foreign claim holds the issue (not reclaimable) | not claimable; re-pick later |
| `dep:<id>` | Authoritative **blocks** (or body fallback) has at least one undones dependency | `deps-blocked` |
| `overlap:<id>` | Footprint path set intersects an in-flight claim’s `**Files:**` | `overlap-blocked` |

When the ordered walk yields **zero** claimable issues, the orchestrator classifies from the skip multiset with precedence **`overlap-blocked` > `deps-blocked` > `scope-blocked` > `truly-empty`** (same as `lib/drain-classify.sh`). Empty candidate set with no skip lines → `truly-empty`.

**Footprint algorithm (REQ-295 — parity with `lib/check-footprint.sh` intent):**

1. Parse candidate Issue body `**Files:**` into a path/glob list (comma- and/or whitespace-separated tokens; trim each).
2. **Empty or missing `**Files:**`** → candidate is **footprint-free** against every peer (empty set intersects nothing). Do not invent paths.
3. Expand each token against the **local** project working tree (runtime stays local):
   - Simple globs (`*`, `?`) expand with **nullglob** semantics — patterns that match nothing contribute **no** paths (two unmatched globs do **not** collide with each other).
   - `**` (globstar) forms expand by walking descendants under the prefix (same intent as markdown `check-footprint.sh`).
   - Literal paths that exist are included as-is; missing literals contribute nothing (nullglob-equivalent).
4. Build the **in-flight peer set**: every other issue whose workflow maps to `in_progress` **or** `stopped` **and** whose latest claim is `status: active` (fresh **or** stale-but-not-yet-unblocked). **Exclude** `done` + `released` (post-`archive_req`) and pure backlog unclaimed issues.
5. For each peer, parse + expand `**Files:**` the same way. If the intersection of expanded path sets is non-empty → reject candidate with `overlap:<peer-id>` (optionally list intersecting paths in detail for status).
6. Do **not** call `lib/check-footprint.sh` as the Linear store — that script reads `.do-work/working/`. Reimplement the **semantics** here via Issue bodies + local path expansion.

**Agent sequence:**

1. **Rediscover** — `search_tool` for: list issues by project; get issue; list relations; list comments; list workflow states (already validated at load).
2. **Enumerate candidates** — issues on product Project (filtered by UR milestone when scoped) whose workflow state maps to **`status_map.backlog`**. Exclude `done` / `in_progress` / `stopped` unless a stale active claim is being recovered under explicit reclaim policy (default pick: **backlog + unclaimed only**). Apply scope filter; emit `scope:<id>` for excluded-by-scope backlog issues when useful for classify.
3. **Sort** candidates by the pick-order ladder above.
4. **For each candidate** in sorted order:
   - **Claim check** — run **Helper: read active claim**. Skip with `claim:<id>` if active claim is **fresh** (another agent holds it). If active claim is **stale**, treat as reclaimable (eligible) unless caller policy forbids takeover.
   - **Deps check** — list `blocks` relations (deps that block this issue). Every dependency issue must be in workflow state mapping to **`status_map.done`** (archived-equivalent). If any dep unsatisfied → `dep:<id>` and continue. If relations tools missing → fall back to body `**Depends on:**` with the one-time warning (port); still no markdown store.
   - **Footprint check** — apply the footprint algorithm above; on overlap → `overlap:<id>` and continue.
   - **Survivor** — append to claimable ordered list.
5. **Return** ordered list of claimable Linear issue ids (and optional titles) **plus** the skip-reason lines for rejected candidates. Empty claimable list is valid.

| Failure | Behavior |
|---------|----------|
| MCP / list tools missing | Hard-stop |
| Project missing | Empty list or error to caller |

---

### `claim_req`

| | |
|---|---|
| **Intent** | Optimistically claim a REQ and move it to in-progress. |
| **Preconditions** | Issue appears claimable under port rules at **re-read** time; caller supplies `agent_id`. |
| **Does not** | Change Linear **assignee**. Does not write local `.do-work/working/`. |

**Agent sequence:**

1. **Rediscover** — get issue, update issue (state), list/create comments, list relations (for optional re-check).
2. **Optimistic re-read** (mandatory before any write):
   - Get issue by Linear id.
   - Map workflow state. Prefer candidate still backlog-equivalent **or** stopped/in_progress only if latest active claim is **stale** and takeover is allowed.
   - Read active claim via helper.
   - If another `agent_id` holds an **active + fresh** claim → **stop** with reason **`concurrent-conflict`** (do not write). Resume of *that* claimer’s work is for the claim owner / operator, not this agent.
   - If **this** `agent_id` already holds active fresh claim → treat as idempotent success (refresh heartbeat optional) or no-op claim.
3. **Write claim** (only after re-read succeeds):
   - Set workflow state → `status_map.in_progress` (resolved state id from preflight). **Do not** modify assignee.
   - Post a new comment (preferred) with body:

     ```markdown
     <!-- do-work-claim -->
     agent_id: {agent_id}
     claimed_at: {now_iso}
     heartbeat: {now_iso}
     session: {optional}
     status: active
     ```

     Use config `agent_claim_marker` as the first line (default `<!-- do-work-claim -->`).
4. **Post-write re-read (recommended):** re-list claim comments; if another agent’s newer active claim appeared, treat as lost race → **`concurrent-conflict`**; do not fight by overwriting assignee or deleting their comment. Leave both comments; operator/status sees conflict; loser stops.
5. **Return** issue id + claim fields. On conflict: empty commit hash N/A; caller exits stopped with `concurrent-conflict`.

| Failure | Behavior |
|---------|----------|
| Fresh foreign claim | `concurrent-conflict` — stop; resume allowed later for owner |
| Issue missing | Error to caller |
| Comment or state tools missing | Hard-stop |
| MCP dies after state→in_progress but before comment | **Leave claimed** as far as written; operator resume/unblock; do not invent rollback that races siblings |
| MCP dies after full claim | **Leave claimed** (port mid-flight rule) |

---

### `heartbeat_req`

| | |
|---|---|
| **Intent** | Refresh liveness on an active claim so siblings do not treat the slot as stale. |
| **Preconditions** | Issue has an active claim owned by this `agent_id` (or orchestrator acting as claim owner). |
| **Does not** | Change workflow state, assignee, or body fields. **No git commit** — comment-only (parity with markdown FS-only heartbeat). |

**Agent sequence:**

1. **Rediscover** — get issue + list/create comments.
2. **Read active claim** — must be `status: active` and `agent_id` match (or explicit owner handoff policy). **If no active claim owned by this agent → HARD-STOP** ("nothing to heartbeat — do not create a new claim to recover; use `claim_req`"). This mirrors sqlite's `cmd_heartbeat`, which `die`s when its UPDATE affects 0 rows (no active claim owned by the caller) — absence means stop, not mint a new claim. If a foreign active fresh claim is present → HARD-STOP / `concurrent-conflict` (do not stamp over).
3. **Write heartbeat — PATCH IN PLACE (primary).** Update the EXISTING active claim comment via the update-comment tool (e.g. `save_comment` with that comment's id), setting:
   - same `agent_id`, same `claimed_at` (preserve original claim time)
   - `heartbeat: {now_iso}`
   - `status: active`
   - same `session` if known

   This is the Linear analog of sqlite's heartbeat UPDATE on the active claim row (`lib/dw-db.sh` `cmd_heartbeat`) — refresh the existing claim's liveness; do **not** mint a new claim entity each heartbeat. Posting a brand-new claim-protocol comment is a **FALLBACK ONLY**, used solely when the MCP surface genuinely exposes no update-comment tool (rediscover and confirm none exists before falling back). If you fall back, post one new comment with the fields above. Never default to posting a new comment when update-comment is available.
4. Consumers always take the **latest** active block by `heartbeat` timestamp — this is a safety net so a stale or fallback comment never strands coordination, **not** license to post a new comment each heartbeat (step 3 patches in place).
5. **Return** issue id + new heartbeat time.

| Failure | Behavior |
|---------|----------|
| Not claim owner / no active claim | **Hard-stop**; do not create a new claim to recover (use `claim_req`). Parity with sqlite's `die` on 0 changed rows |
| MCP missing mid-heartbeat | Hard-stop; **leave** prior claim/heartbeat as last written |

**Checkpoint usage (run-worker):** stamp at the same logical checkpoints as markdown (`heartbeat.sh`): after read REQ, after red, after each green cycle, after each verification step, immediately before commit — via this op against the Linear issue id.

---

### `set_req_status`

| | |
|---|---|
| **Intent** | Set workflow status (e.g. `stopped`, `in-progress`) **without** full archive and **without** clearing claim (unless target is backlog — then prefer `unblock_req`). |
| **Preconditions** | Issue exists; target status key is in `status_map` and validated on team. |
| **Does not** | Steal assignee; archive; strip claim when moving to `stopped`. |

**Agent sequence:**

1. **Rediscover** — get/update issue; resolve target Linear state id from `status_map.<key>`.
2. **Map intent:**
   - `stopped` — set state → `status_map.stopped`. **Keep** active claim comment (`status: active`); refresh heartbeat optional. Record stopper reason via `append_run_note` or issue comment (not by deleting claim).
   - `in_progress` — set state → `status_map.in_progress` (usually via `claim_req` or **resume**, not bare status).
   - `backlog` — **do not** use this op alone to clear a claim; call **`unblock_req`**.
   - `done` — **do not** use this op; call **`archive_req`** (this file, REQ-294).
3. **Write** state only (+ optional reason comment). Preserve assignee and claim comments.
4. **Return** issue id + new do-work status key.

| Failure | Behavior |
|---------|----------|
| Unknown status key / missing state on team | Hard-stop (status_map validation) |
| MCP missing | Hard-stop; if already claimed → leave claimed |

---

### `archive_req`

| | |
|---|---|
| **Intent** | Mark REQ **done** with closure proof and outputs; release the in-flight claim/footprint. Linear is the sole archive store. |
| **Preconditions** | Worker returned `status: done` with non-empty `closure_proof` and AC evidence; **when `review.required: true` (default), post-build review must have returned `status: passed`**; claim owned by the orchestrating flow (or operator-approved). |
| **Does not** | Steal assignee; delete the Issue; write local `.do-work/archive/REQ-*` as source of truth; auto-merge git (merge/PR stay local in `agents/run.md`); run after a failed review or failed acceptance-evidence gate. |

**Orchestrator gates (REQ-295 — must pass before this op is invoked):**

| Gate | On failure | Call `archive_req`? | Claim / workflow |
|------|------------|---------------------|------------------|
| Acceptance evidence (`check-acceptance-evidence` / report AC map) | `stopped` / `verification-failing` | **No** | Leave `in_progress` or set `stopped` via `set_req_status`; **claim stays active** |
| Policy blocked (`check-policy` exit 1) | `stopped` / policy-blocked path | **No** | Same — claim intact |
| Review (`agents/review.md`) when `review.required: true` | `stopped` / `review-failed` | **No** | Same — claim intact; optional `append_run_note` with `result: stopped:review-failed` |
| Review when `review.required: false` | Review may be skipped | Yes (if other gates pass) | — |
| Missing / empty `closure_proof` | Do not archive | **No** | Leave claimed |

Failed review or failed acceptance-evidence **never** transitions to `status_map.done` and **never** posts claim `status: released` via this op. Resume/unblock remain the recovery paths.

**Agent sequence:**

1. **Rediscover** — `search_tool` for: get/update issue; list/create comments; list workflow states (already validated at load). Map hits to **observed** tool names + schemas.
2. **Pre-archive re-read** — get issue by Linear id. Confirm:
   - Workflow is `in_progress` or `stopped` (not already `done` unless idempotent re-archive policy is explicit).
   - Latest claim is `status: active` (preferred) owned by this run, **or** operator override documented in the call.
   - Caller asserts review/evidence gates already passed (this op does not re-run review; it trusts the orchestrator).
   - If MCP fails here after a prior claim → **leave claimed**; stop; never silent-release and never markdown-archive.
3. **Write body fields** (update Issue description; preserve machine marker `<!-- do-work-req -->` and other headers):
   - Set / replace `**Closure proof:**` with the worker’s non-empty proof string (may cite checkpoint log + commit short hash).
   - Ensure `## Outputs` exists; replace or append the orchestrator’s outputs list from the worker YAML (`path` + one-line description per item). Prefer a full section rewrite from the report so the archived Issue matches the attempt.
   - Tick ACs already checked by the worker when the body still has `- [ ]` that the report marked passed — do not invent new AC text.
   - Optional: set `**Suite:** not-run` when the worker deferred with `category: suite-not-run` (parity with markdown archive header).
4. **State → done** — set workflow to `status_map.done` (resolved state id from preflight). **Assignee unchanged.**
5. **Release claim** — post claim-protocol comment with `status: released` (same shape as `unblock_req` release). Latest released block means the issue is no longer in-flight for footprint purposes. Prefer preserving prior `agent_id` / `claimed_at`.
6. **Optional** — `append_run_note` for the successful attempt (result `done`, cost, model, commit) if the orchestrator has not already written one for this attempt.
7. **Return** issue id + done confirmation. Do **not** create or move local REQ markdown files.

| Failure | Behavior |
|---------|----------|
| Missing / empty closure proof | Do not archive; leave in_progress/stopped + **leave claimed**; surface to orchestrator (parity with missing-closure-proof) |
| Review / acceptance gate failed | **Do not call** this op; issue stays claimed |
| MCP dies mid-archive (partial body or state write) | **Hard-stop; leave claimed** if claim not yet released; operator re-runs archive or resume after recovery — never silent markdown fallback |
| State tools / comment tools missing | Hard-stop |

**Parity with markdown `archive_req`:** done status + closure proof + outputs + footprint released. Representation differs (Issue body + workflow + claim comment vs `working/` → `archive/` move).

**Footprint after archive:** other agents’ `list_claimable_reqs` no longer treat this issue as in-flight (done + released claim), so its `**Files:**` no longer blocks siblings.

---

### `append_run_note`

| | |
|---|---|
| **Intent** | Append a ledger-ish / cost / run note for a REQ attempt. **Authoritative** work-item note in Linear mode. |
| **Preconditions** | Target Issue (Linear id) exists; attempt context known (agent, model, result, timestamps, optional cost). |
| **Does not** | Replace `archive_req`; change workflow state or assignee; require local `.do-work/runs/` as the store. |

**Agent sequence:**

1. **Rediscover** — `search_tool` for issue comments create (and optionally project updates for run rollup). Queries such as `"linear issue comments"`, `"linear create comment"`.
2. **Build note body** — Issue comment with a YAML fenced block carrying ledger fields (same conceptual fields as `lib/run-ledger.sh` / `RUN-NNN.yml`):

   ````markdown
   <!-- do-work-run-note -->
   ```yaml
   req: ENG-123
   agent: hostname.pid
   model: sonnet
   branch: req/ENG-123
   started: 2026-07-31T12:00:00Z
   ended: 2026-07-31T12:20:00Z
   result: done
   review: passed
   cost_estimate: ""
   commit: abcdef1
   pr_url: ""
   commands: []
   tests: []
   changed_files: []
   ```
   ````

   Adjust fields to what the orchestrator collected; `result` may be `done`, `stopped:<reason>`, or `failed`. Marker line `<!-- do-work-run-note -->` is stable for readers/retro.
3. **Post comment** on the Issue via discovered create-comment tool.
4. **Optional Project update** — if project-update tools exist and the caller wants a run rollup, post a short summary on product Project or UR milestone (non-authoritative) (non-authoritative convenience; Issue comment remains the home per design §10).
5. **Return** comment id / success.

| Failure | Behavior |
|---------|----------|
| Comment tools missing | Hard-stop for this op; do not invent a local markdown “note store” as work-item substitute |
| MCP dies after claim, during note | **Leave claimed**; stop; retry note later — never silent-release |

#### Local ledger telemetry (optional; not a second store)

When `ledger.enabled: true`, the orchestrator **may also** append `{project}/.do-work/runs/RUN-NNN.yml` via `lib/run-ledger.sh` for offline retro tooling (design §7).

| Store | Role when `backend: linear` |
|-------|------------------------------|
| **Issue comment via `append_run_note`** | **Authoritative** run/cost note |
| **Local `RUN-NNN.yml`** | **Telemetry only** — offline sum/budget/retro convenience |
| **Local UR/REQ markdown** | **Not** a work-item store; do not dual-write REQs |

Rules:

1. Local ledger **must not** become the system of record for work items or claim state.
2. Retro prefers Linear run notes when `backend: linear`; falls back to local runs if comments are unavailable.
3. If `ledger.enabled` is false, skip local file; still prefer `append_run_note` for Linear run history when the attempt warrants a note.
4. Budget gate may sum local telemetry when present; if only Linear notes exist, sum from those comments or skip numeric gate with an explicit note — never invent spend.

#### List run notes (helper — retro / budget; not a separate port op name)

Readers (primarily **`agents/retro.md`**, optionally budget/status) collect authoritative Linear run history when `backend: linear`:

1. **Rediscover** issue list/get + comment list tools (`search_tool`).
2. **Scope** — Issues under the product Project for the configured team (or a single UR milestone when scoped). Prefer Issues that have been attempted (in_progress / stopped / done), not pure backlog with zero comments.
3. **List comments** per Issue; keep bodies whose first marker line is `<!-- do-work-run-note -->` (same marker as `append_run_note`).
4. **Parse** the YAML fenced block (fields: `req`, `agent`, `model`, `result`, timestamps, cost, commit, …). Treat parse failures as skip-with-warning (do not invent stats).
5. **Prefer** these notes for retro interpretation when present. If comment tools fail or zero notes found → fall back to local `{project}/.do-work/runs/RUN-NNN.yml` telemetry (if any). Never dual-write a fabricated local ledger from partial Linear data.
6. Do **not** invent spend, stop rates, or shapes from narrative Issue comments that lack the run-note marker.

---

### `append_decision`

| | |
|---|---|
| **Intent** | Append one standing decision line to the team's decisions memory (append-only). |
| **Preconditions** | `tracker.backend: linear`; team resolvable; decisions Doc title from config known. |
| **Home** | Team Doc titled `tracker.linear.decisions_doc_title` (default **`do-work/decisions`**). **Never** invent a different title or a local `.do-work/decisions.md` store while backend is linear. |
| **Does not** | Rewrite prior lines; change Issues; write calibration. |

**Line format** — **identical** one-line grammar to markdown `.do-work/decisions.md` / SKILL.md § Decisions Memory (four pipe-separated fields; no paragraphs):

```
YYYY-MM-DD | UR/REQ ref | decision | rationale
```

| Field | Rule |
|-------|------|
| `YYYY-MM-DD` | UTC date the decision was recorded |
| `UR/REQ ref` | UR slug (`UR-035`) and/or Linear issue id (`ENG-123`) — same slot as markdown `REQ-NNN` |
| `decision` | Standing choice, stated as a constraint |
| `rationale` | One phrase explaining why |

**Discipline (parity with markdown):** append-only; never rewrite or delete a prior line; supersede with a new line that references the old; absent Doc on **read** = empty set (do not create on read).

**Agent sequence:**

1. **Rediscover** — `search_tool` for Linear **Team Docs** (list/get/create/update). Queries such as `"linear team docs"`, `"linear document"`, `"linear create document"`. Use only qualified names + schemas returned.
2. **Resolve title** — `title = tracker.linear.decisions_doc_title` if non-empty, else `do-work/decisions`. **Never** invent another title.
3. **Find or create** — list/search Docs on the configured team for exact title match.
   - If found → load body.
   - If missing → **create-if-missing** with that exact title and empty or header-only body (e.g. `# do-work decisions\n\n` plus append-only lines below).
4. **Append one line** — build `YYYY-MM-DD | <UR or issue ref> | <decision> | <rationale>` (UTC date). Append as a new trailing line; preserve all existing lines. Do not reorder or edit prior decisions.
5. **Update Doc** — write the full new body via discovered update tool.
6. **Return** Doc id + success. Do **not** also append to local `.do-work/decisions.md`.

| Failure | Behavior |
|---------|----------|
| Docs tools missing / unauthenticated | Hard-stop; Linear setup instructions; **no** local decisions file as substitute store |
| Team unresolved | Hard-stop |
| Create fails (permission / size / MCP) | Hard-stop; **do not** invent Issue comments, alternate Doc titles, or local `decisions.md` |
| Update fails (permission / size / MCP) | Hard-stop; leave Doc as-is; **do not** invent alternate homes; retry later |

#### Read decisions (helper — not a separate port op name)

Readers (**capture, ideate, question, run-worker** — REQ-297) load standing decisions as **constraints**:

1. Same rediscovery + title resolution as `append_decision` (`decisions_doc_title` / default `do-work/decisions`).
2. If Doc missing → empty set (continue; never create on read-only path).
3. If present → parse body lines matching the four-field decision grammar; hold in context. Same discipline as markdown `.do-work/decisions.md` readers (worker treats lines as hard constraints; ideate/question use them as evidence / contradiction flags).
4. Do **not** also read local `.do-work/decisions.md` when `backend: linear`.

---

### Write / read calibration Doc

Calibration is **not** a separate port op name in `port.md`; representation under Linear is fixed here so retro/capture do not invent homes. Full body shape matches markdown `state/calibration.md` (header + `## Capture guidance` bullets + `<!-- retro-meta ... -->`).

| | |
|---|---|
| **Intent** | Persist (retro) or load (capture) capture-facing calibration guidance. |
| **Home** | Team Doc titled `tracker.linear.calibration_doc_title` (default **`do-work/calibration`**). |
| **Write semantics** | **Full replace** every retro run (truncate-write equivalent) — never append-merge with prior bullets. |
| **Read semantics** | Advisory only; absence is silent no-op. |

**Write sequence (retro):**

1. **Rediscover** Team Docs tools (`search_tool`).
2. **Resolve title** — `tracker.linear.calibration_doc_title` or default `do-work/calibration`.
3. **Find or create-if-missing** Doc with that exact title on the configured team.
4. **Build body** — same markdown format as retro Step 5 (≤8 guidance bullets, retro-meta footer).
5. **Replace entire body** (not append).
6. **Return** Doc id. Do **not** also write `{project}/.do-work/state/calibration.md` as the store when `backend: linear`.

**Read sequence (capture):**

1. Rediscover + resolve title.
2. If Doc missing → continue without calibration.
3. If present → load body; keep guidance bullets as advisory input (brief always wins).

| Failure | Behavior |
|---------|----------|
| Docs tools missing on write | Hard-stop retro calibration write; do not invent local calibration store |
| Create/update fails (permission / size / MCP) | Hard-stop; **do not** invent alternate Doc titles, Issue comments, or local `state/calibration.md` |
| Docs tools missing on read | Treat as absent calibration (advisory path); do not hard-stop capture solely for missing Docs on read if the rest of capture can proceed without it — prefer hard-stop only when backend is linear **and** the agent was required to read remote work-items that also failed |

**Empty retro (`runs=0` and no Linear run notes to interpret):** do **not** create or replace the calibration Doc (parity with markdown: write no file).

---

### `write_verify_report`

| | |
|---|---|
| **Intent** | Persist verify-phase coverage report for a UR. |
| **Preconditions** | UR Project Milestone exists (`read_ur` / product Project + milestone); verify agent has produced the report body. |
| **Home** | UR Project Milestone description section **`## Verify`** + **milestone comment** with the full report. **Not** a local file under `user-requests/` as source of truth. |
| **Does not** | Create REQs; change claim state; invent alternate section names. |

**Agent sequence:**

1. **Rediscover** — tools to get/update Project Milestone description and create comments. Queries such as `"linear milestone"`, `"linear update milestone"`, `"linear create comment"`.
2. **Resolve UR** — load UR Project Milestone for `UR-NNN` (`read_ur`). Confirm `<!-- do-work-ur -->` body.
3. **Build report** — full markdown verify report (confidence score, coverage, gaps, issues, summary — same console shape as `agents/verify.md` Step 5c).
4. **Update `## Verify` section** — replace or insert content under `## Verify` in the UR Project Milestone description (prefer description append/replace of that section only; do not overwrite `## Brief`). Include at least: confidence score, recommendation, and a short summary. If the full report exceeds size limits, put a one-line pointer in `## Verify` (e.g. `Full report: see Initiative comment <timestamp>`) and put the **full** body in the comment.
5. **Post milestone comment** — full report body, optionally prefixed with `<!-- do-work-verify-report -->` for stable readers.
6. **Return** Initiative id + comment id / success. Do **not** write a durable local verify path as the work-item store.

| Failure | Behavior |
|---------|----------|
| Milestone tools missing | Hard-stop |
| UR / milestone not found | Hard-stop; do not invent Initiative |
| Size limit on description only | Section pointer + full **milestone** comment (required §10 path above) — **not** inventing a home |
| Description **and** Initiative comment both fail (permission / size / MCP) | Hard-stop; **do not** invent Issue comments, alternate Docs, or local verify files as the store |

**Markdown backend note:** `markdown.md` remains console-primary for verify (no fixed durable path). Linear makes verify durable via this op.

---

### `write_close_report`

| | |
|---|---|
| **Intent** | Persist close-phase path-unit closure report for a UR. |
| **Preconditions** | UR Project Milestone exists; close agent has produced the closure document (YAML front matter + per path-unit rows). |
| **Home** | UR Project Milestone description section **`## Closure`** + **milestone comment** with the full closure report. **Not** `{project}/.do-work/user-requests/UR-NNN/closure.md` as source of truth under Linear. |
| **Does not** | Edit REQs/source; reopen Issues; put gate locks in Linear. |

**Agent sequence:**

1. **Rediscover** milestone get/update + comment create tools.
2. **Resolve UR** — UR Project Milestone for `UR-NNN` via `read_ur`.
3. **Build report** — same schema as `agents/close.md` Step 5 (`ur`, `closed_at`, `branch`, `path_units`, `verdict_summary`, `overall`, plus per-path-unit rows). Empty path-unit case still writes a valid `overall: no-path-units` report.
4. **Update `## Closure` section** — replace/insert under `## Closure` only. Short summary in description is fine; full YAML+rows may live in the comment if size-constrained (pointer line in section required when spilling).
5. **Post milestone comment** — full closure markdown, optionally prefixed with `<!-- do-work-close-report -->`.
6. **Evidence artifacts** — screenshots / command captures remain **local** under a UR-scoped path only if the operator needs files on disk (optional); `evidence_ref` may point at local paths or inline snippets. Local evidence files are **not** a second work-item store for the report itself.
7. ****Return** milestone id + success. Do **not** dual-write authoritative `closure.md` under `user-requests/` when `backend: linear`.

| Failure | Behavior |
|---------|----------|
| Milestone tools missing | Hard-stop |
| UR missing | Hard-stop |
| Size limit on description only | Section pointer + full **milestone** comment (§10) |
| Description **and** Initiative comment both fail (permission / size / MCP) | Hard-stop; **do not** invent Issue comments, alternate Docs, or local `closure.md` as the store |

#### Close path-unit collection (Linear — REQ-297)

When `agents/close.md` walks a UR under `backend: linear`, path-units come from Linear Issues — not from local `archive/REQ-*.md`:

1. Resolve product Project + UR milestone and call **`list_reqs_for_ur`** (all Issues in that Project; include done/archived-equivalent).
2. For each Issue body, treat as a **path-unit** when `**Layer:**` is `none` **and** both `**Entry point:**` and `**Terminal state:**` are present and non-empty after trim.
3. Extract: `req` = **Linear issue identifier** (e.g. `ENG-123`); `entry_point` / `terminal_state` = verbatim header values.
4. Do **not** read `**Closure proof:**` (same cold-dispatch rule as markdown).
5. Walk still runs against the **merged local app** (git). Persist results only via **`write_close_report`**.
6. Closure row `req:` fields and report headings use Linear ids (`## ENG-123 — closed`), never parallel `REQ-NNN` allocation.

Brief load under Linear: **`read_ur`** (UR Project Milestone description `## Brief` / machine sections) — do not require local `user-requests/UR-NNN/input.md` as the store.

---



---

## Footprint and deps in the run loop (REQ-294 / REQ-295)

| Concern | Linear rule | Markdown parity |
|---------|-------------|-----------------|
| **Deps satisfied?** | Every issue on the authoritative **`blocks`** graph (deps that block this issue) is in `status_map.done` | `**Depends on:**` ids in `archive/` |
| **Deps diverge** | Relations **win**; body `**Depends on:**` is display/mirror | File header is the store |
| **Footprint free?** | Footprint algorithm under `list_claimable_reqs` (empty Files = free; nullglob; in-flight = active claim on in_progress/stopped) | `lib/check-footprint.sh` vs `working/` |
| **After `archive_req`** | Done + released claim → no longer in-flight; footprint frees for siblings | File left `working/` |
| **Pick order** | Priority **DESC** (3 before 1; missing→2) → created_at ASC → identifier ASC (REQ-295) | Priority DESC (missing→2) then numeric REQ id in `pick-req.sh` |
| **Skip reasons** | `dep:` / `overlap:` / `scope:` / `claim:` lines (REQ-295) | pick-req stderr `dep` / `overlap` / `scope` |

`list_claimable_reqs` (above) implements both checks. Run Step 1 must not re-implement with local REQ files while `backend: linear`.

---

## No Linear-aware bash in `lib/` (v1 — REQ-295)

| Surface | v1 home |
|---------|---------|
| Pick / claim / deps / footprint / heartbeat / unblock / archive integrity (Linear) | **Agent sequences in this file** via Linear MCP (`search_tool` → `use_tool`) |
| Markdown store of the same ops | Existing `lib/pick-req.sh`, `claim-req.sh`, `check-deps.sh`, `check-footprint.sh`, `heartbeat.sh`, `check-archive-integrity.sh`, … |
| Local runtime (both backends) | `provision-worktree.sh`, worktrees, merges, `state/*` locks, events, optional `run-ledger.sh` telemetry |

**Do not** add Linear API clients, tokens, or GraphQL shells under `lib/` for v1. If a future REQ introduces Linear-aware bash, it must be explicit and tested — out of scope here.

---

## Deps authority (Linear)

Native **`blocks` relations** are authoritative for `list_claimable_reqs` / deps checks. Issue body `**Depends on:**` is a **mirror**. **`set_blocked_by`** (REQ-291 sequence) always:

1. Updates relations when relation tools are discoverable (add/remove to match the target set).
2. Updates the body mirror in the same op.
3. If relations tools are **missing** after live probe → body-only + one-time warning (port rule); never markdown dual-store.
4. If spike later marks relations **missing** (not merely **unknown**), document GraphQL/other fallback in this section before production claim depends on it.

Dependency ids are **Linear issue identifiers only**.

---


