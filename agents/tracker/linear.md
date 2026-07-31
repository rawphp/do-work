# Tracker backend: linear (opt-in)

Implements the tracker port (`agents/tracker/port.md`) with **Linear as the sole work-item store** when `tracker.backend: linear`. Agent steps invoke the Linear skill / MCP; there is **no** Linear-aware bash in v1 and **no** dual-write to local UR/REQ markdown.

**This is not the default.** When `tracker.backend` is missing, empty, or `markdown`, agents load `markdown.md` instead — Linear tools are not required.

---

## Path: Linear MCP capability spike (REQ-288)

| | |
|---|---|
| **Entry point** | Operator sets a **sandbox** Linear team (`tracker.linear.team_id` / `team_key`); agent rediscovers MCP tools live before any full CRUD wiring |
| **Terminal state** | Capability matrix present; live probe records **available**/**missing**/**partial** **or** documents **matrix unavailable** + hard-stop when MCP is down; **no production work-item migration** on this path; CRUD REQs unblocked only after a future MCP-connected fill marks required cells |

This path answers design risk §17 #1 (**MCP thin / offline tools**) and the clarification **spike first, then implement**. Full port op sequences, templates, claim, and migration live in later path-units — **not** here.

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Live tool rediscovery on sandbox team | `search_tool` → `use_tool` probes; fill matrix cells from **observed** tools only | REQ-289 ran — **matrix unavailable** (no Linear MCP) |
| Hard-stop / setup copy | Verbatim operator instructions when MCP missing (this file + Linear skill) | REQ-288 skeleton → REQ-289 confirmed |
| `status_map` vs real team states | Document defaults + hard-fail; validate names on sandbox workflow | Defaults documented; live names **not validated** (MCP missing) |
| Full op sequences / templates / claim | Deferred — other path-units after matrix is known | REQ-290 documents UR/REQ CRUD sequences (still `search_tool` live; claim/run later) |

**Do not** invent Linear tool names as if proven. Until a **later** live probe (post-REQ-289, with Linear MCP connected) records a row as **available**, treat tool names as **unknown**. CRUD sequences below still call `search_tool` first and hard-stop if undiscoverable — they do **not** treat skill “typical tools” tables as proven.

---

## Path: Linear UR/REQ CRUD (REQ-290)

| | |
|---|---|
| **Entry point** | `/do-work` intake or start with `tracker.backend: linear` and valid team config (Load Config step 7) |
| **Terminal state** | Initiative + Project `do-work/{UR-id}` + Issues/sub-issues exist with §9 templates; `create_ur` / `create_req` / `update_req` / `read_req` / `list_reqs_for_ur` (+ `read_ur` / `list_urs`) sequences are documented as agent steps that rediscover tools live |

This path-unit wires **work-item create/read/update/list** only (design §6 hierarchy, §9 templates). Claim/heartbeat, pick, archive, non-ticket Docs, milestone, and migration remain later path-units.

**Hard rules for every CRUD op in this path:**

1. **Rediscover, never invent** — each op begins with `search_tool` for the needed Linear surface; call `use_tool` only with a qualified name + `input_schema` from that search.
2. **Hard-stop if undiscoverable** — if Linear MCP tools are missing, unauthenticated, or the needed capability has no discovered tool, **stop** with the setup block in this file. Do not invent issues/initiatives; do not write local UR/REQ markdown as a substitute store.
3. **No dual-write** — Linear is the sole work-item store while `backend: linear`. No parallel `.do-work/user-requests/` or `.do-work/REQ-*` as source of truth.
4. **Linear issue ids only** — REQs are identified by Linear identifiers (e.g. `ENG-123`). **No** parallel `REQ-NNN` allocation in Linear mode. `UR-NNN` remains a Project/Initiative slug only.
5. **Atomic `create_ur`** — never leave an Initiative without its Project + link. If Project create or link fails after Initiative create, hard-stop with recovery notes (delete/orphan cleanup instructions); do not continue intake as if the UR exists.

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| UR create/read/list sequences | Initiative + Project `do-work/{UR-id}` + InitiativeToProject (or discovered equivalent) | REQ-290 (this section) |
| REQ create/update/read/list | Issues in that Project; §9.2 body; path-unit `parentId` sub-issues | REQ-290 (this section) |
| Templates + append/deps/footprint ops | §9 field semantics; `append_ideate` / `append_clarifications` / `set_blocked_by` / `set_files` | REQ-291 |
| Claim / heartbeat / pick / archive | Deferred | later REQs |
| Non-ticket homes / migrate | Deferred | later REQs |

---

## Path: Linear templates + append/deps/footprint (REQ-291)

| | |
|---|---|
| **Entry point** | Any phase that writes UR sections (ideate/question) or REQ deps/footprint under `tracker.backend: linear` |
| **Terminal state** | §9.1 / §9.2 templates (machine markers `<!-- do-work-ur -->` / `<!-- do-work-req -->`), labels (`Layer/*`, `Size/*`, `path-unit`), `status_map` hard-fail rules, and full agent sequences for `append_ideate`, `append_clarifications`, `set_blocked_by` (blocks relations + `**Depends on:**` mirror), and `set_files` are documented with live rediscovery |

This path-unit **extends** REQ-290 CRUD: templates become the field contract, and the remaining create/update surface for intake→capture without claim is complete.

**Hard rules (in addition to REQ-290 CRUD rules):**

1. **Machine markers are mandatory** on every Initiative description (`<!-- do-work-ur -->`) and Issue description (`<!-- do-work-req -->`). Parse/stop if missing on read/update — do not invent fields.
2. **`set_blocked_by` dual-write** — when relation tools exist: native `blocks` relations **and** body `**Depends on:**` mirror in one op. Relations are authoritative for eligibility (port rule).
3. **Labels from config prefixes** — `tracker.linear.labels.layer_prefix` (default `Layer/`), `size_prefix` (default `Size/`), `path_unit` (default `path-unit`). Apply on create/update when label tools are discoverable; body headers still hold the same values for parse.
4. **`status_map` hard-fail** — every mapped workflow state name must exist on the team; missing → hard-stop (never invent a close-enough state).
5. **Prefer section append** on Initiative for ideate/clarifications; never overwrite `## Brief` verbatim intake.

---

## When to load

After config load and backend resolution (`port.md` load path + `agents/config.md` Load Config step 7):

1. Effective backend is **`linear`**.
2. Linear validation passes (team resolvable, MCP discoverable, every `status_map` state exists on the team) — or agent **hard-stops** (see below).
3. Read `agents/tracker/port.md`.
4. Read this file.
5. Perform work-item ops only via port ops mapped here (**UR/REQ CRUD sequences**, including templates §9 and append/deps/footprint ops).

Do **not** load this file when backend is `markdown` (including unset/empty).

---

## Tool rediscovery (hard rule)

Linear MCP schemas evolve. **Every** Linear action in this backend follows the Linear skill protocol:

1. Call **`search_tool`** with a query scoped to Linear (e.g. `"linear issues"`, `"linear initiative"`, `"linear document"`).
2. Call **`use_tool`** only with a **qualified** name returned by search (typically `linear__<tool>`).
3. Match **`input_schema`** exactly — never guess parameter names.

| Forbidden | Required |
|-----------|----------|
| Hard-coding tool names from memory as “the” API | Rediscover in the current session |
| Fabricating issues / initiatives / ids when MCP is down | Hard-stop with setup instructions |
| Silent fallback to `markdown` ops | Stay on Linear backend rules or stop |
| Treating skill “typical tools” tables as proven | Mark **unknown** until live `search_tool` hit |

Official remote MCP: `https://mcp.linear.app/mcp` (read-only variant: `…/mcp/readonly`). Skill source of truth for setup: Linear skill `SKILL.md` (hub / project install of `linear`).

---

## Capability matrix (spike)

**Status legend**

| Status | Meaning |
|--------|---------|
| **unknown** | Not proven in a live session; do not wire production ops on this cell |
| **available** | Live `search_tool` / `use_tool` confirmed (record qualified name + date in Notes) |
| **missing** | Live probe ran; no tool for this need — document fallback or hard gap |
| **partial** | Related tools exist but not full create/link/read needed by port |

### Matrix availability (REQ-289 live probe)

| | |
|---|---|
| **Probe date** | 2026-07-31 |
| **Protocol** | `search_tool` queries: `"linear"`, `"linear issues initiative project document"`, `"server:linear mcp.linear"` |
| **Result** | **Matrix unavailable** — Linear MCP server not connected; zero `linear__*` tools discovered |
| **Connected MCP servers observed** | `github`, `gmail`, `google_calendar`, `google_drive`, `notion`, `skill-seekers`, `tasks` (no `linear`) |
| **use_tool probes** | **Not run** — no qualified Linear tool names returned; inventing calls is forbidden |
| **Sandbox team** | Not reachable (no team list/get tools); `tracker.linear.team_id` / `team_key` not validated this session |
| **Operator action** | Hard-stop applies when `tracker.backend: linear` — follow setup block below (API key / OAuth / `mcp.linear.app`), restart agent, re-run discovery, then fill rows as **available** / **missing** / **partial** from live tools only |
| **Secrets** | None used or recorded |

**Session note (REQ-288 path skeleton, 2026-07-31):** earlier worker also lacked Linear MCP; all rows left **unknown**.

**Session note (REQ-289 live rediscovery, 2026-07-31):** re-ran `search_tool` for Linear. Confirmed **no Linear MCP handshake** in this session — semantic hits only mentioned Linear as a Notion connected source or GitHub project tools, not a `linear` MCP server. Capability matrix remains **unavailable**; every design-need row stays **unknown**. Do **not** treat skill “typical tools” tables as proven. No secrets in this file.

### Required capabilities vs port needs

| Capability (design need) | Port / design use | Live status | Qualified tool name(s) | Notes / fallback |
|--------------------------|-------------------|-------------|------------------------|------------------|
| **Team resolve** | `ensure_product_container`; config validation | unknown | — | REQ-289: MCP missing — unproven |
| **Workflow states** | `status_map` validation; claim/status/archive | unknown | — | REQ-289: cannot list team states without MCP |
| **Initiatives** (UR) | `create_ur`, `read_ur`, `list_urs`, verify/close homes | unknown | — | REQ-289: **unproven** (MCP missing); hierarchy still design-locked |
| **Projects** (`do-work/{UR-id}`) | Intake project; `list_reqs_for_ur` scope | unknown | — | REQ-289: unproven |
| **Initiative ↔ Project link** (`InitiativeToProject`) | Intake link Project → Initiative | unknown | — | REQ-289: **critical cell unproven**; if later **missing**, document GraphQL/API fallback before wiring intake |
| **Issues** (REQ) | `create_req`, `read_req`, `update_req`, list | unknown | — | REQ-289: unproven; Linear issue ids only once available |
| **Sub-issues / parent** | Path-unit parent + layer children (`parentId`) | unknown | — | REQ-289: unproven |
| **Issue relations `blocks`** | `set_blocked_by`; deps **authoritative** | unknown | — | REQ-289: **unproven**; if later **missing** → description-only deps + one-time warning (port rule) or GraphQL fallback |
| **Comments** | Claim/heartbeat protocol; `append_run_note` | unknown | — | REQ-289: unproven |
| **Team Docs** | `append_decision`, calibration | unknown | — | REQ-289: **unproven** (MCP missing); titles stay config-driven when proven |
| **Labels** | Layer / Size / path-unit | unknown | — | REQ-289: unproven |
| **Assignee** | Human `default_assignee_id` on create | unknown | — | REQ-289: unproven |

### Port op readiness

| Port op | Depends on capability rows | Sequence status |
|---------|----------------------------|-----------------|
| `ensure_product_container` | Team resolve, labels (optional) | Documented (CRUD preflight) |
| `create_ur` / `read_ur` / `list_urs` | Initiatives, Projects, Initiative↔Project link | **Documented** (REQ-290) — live `search_tool` required; hard-stop if undiscoverable |
| `append_ideate` / `append_clarifications` | Initiatives (description/comments) | **Documented** (REQ-291) — section append under §9.1; rediscover update tools |
| `create_req` / `update_req` / `read_req` | Issues, Projects, labels, statuses | **Documented** (REQ-290) |
| `list_reqs_for_ur` | Issues by Project | **Documented** (REQ-290) |
| `list_claimable_reqs` | Issues + relations + comments + statuses | TBD after claim path |
| `claim_req` / `heartbeat_req` / `unblock_req` | Issues status + comments | TBD after claim path |
| `set_req_status` / `archive_req` | Workflow states, issues | TBD after claim path |
| `set_blocked_by` | Issue relations `blocks` (+ body mirror) | **Documented** (REQ-291) — dual-write; if relations **missing** → body-only + one-time warning (port rule) |
| `set_files` | Issue description headers | **Documented** (REQ-291) — updates `**Files:**` only; no claim side-effect |
| `append_decision` / calibration | Team Docs | TBD after spike Docs row |
| `write_verify_report` / `write_close_report` | Initiative sections/comments | TBD |
| `append_run_note` | Issue comments (+ optional project update) | TBD |
| Milestone ops | Project description / labels / milestone entity if any | TBD |
| `write_gate_state` | **Local** `state/gate-owner.md` (not Linear) | Local only |

---

## Templates (design §9)

Bodies are **markdown conventions** in Linear description fields — not custom Linear fields. Prefer description appends; fall back to Initiative/Issue **comments** if description size limits require it (record a one-line pointer in the section when spilling).

**Machine markers (required):**

| Entity | Marker (first non-empty line of structured body) | Op consumers |
|--------|--------------------------------------------------|--------------|
| Initiative (UR) | `<!-- do-work-ur -->` | `create_ur`, `read_ur`, `list_urs`, `append_ideate`, `append_clarifications`, verify/close writers |
| Issue (REQ) | `<!-- do-work-req -->` | `create_req`, `update_req`, `read_req`, `set_files`, `set_blocked_by`, claim/archive later |

On **read/update**: if the marker is missing, treat as template parse failure → **stop the op**; do not invent headers or rewrite the body into template form without an explicit migrate path.

### §9.1 Initiative (UR) description template

```markdown
<!-- do-work-ur -->
**UR-id:** UR-007
**Class:** feature
**Created:** YYYY-MM-DD
**Project:** do-work/UR-007
**Project-id:** {linear-project-uuid}

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
| `**Project:**` | Machine name `do-work/{UR-id}` (config `project_name_pattern`) | Resolve Project |
| `**Project-id:**` | Linear project UUID after Project create + link | Prefer id over name when both present |
| `## Brief` | **Verbatim** intake — never overwrite on ideate/question | `read_ur` |
| `## Clarifications` | `append_clarifications` appends Q&A; does not create REQs | Question, capture |
| `## Ideate` | `append_ideate` writes/appends ideate body | Ideate, capture |
| `## Open gaps` / `## Capture summary` | Capture phase | Capture, verify |
| `## Verify` / `## Closure` | Later path-units (`write_verify_report` / `write_close_report`) | Verify, close, go |

### §9.2 Issue (REQ) description template

```markdown
<!-- do-work-req -->
**UR:** UR-007
**Layer:** agents | none | …
**Parent:** ENG-100 | none
**Entry point:** …          # path-unit parents only
**Terminal state:** …       # path-unit parents only
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
| UR slug | Sequential `UR-NNN` (Project name / Initiative metadata only) |
| REQ | **Linear issue identifier only** (e.g. `ENG-123`) — never allocate `REQ-NNN` under Linear backend |
| Project name | `do-work/{UR-id}` from `tracker.linear.project_name_pattern` (default `do-work/{ur_id}`) |
| Initiative title | `tracker.linear.initiative_title_pattern` (default `{ur_id}: {title}`) |

### Preflight (before first CRUD op in a session)

1. Config effective backend is `linear` (else do not use this file).
2. `search_tool "linear"` (or `"linear team"`) — must return Linear MCP tools; else hard-stop.
3. Resolve team: config `tracker.linear.team_id` and/or `team_key` via discovered team list/get tools. Unresolved → hard-stop (do not guess).
4. Validate every `status_map` value exists on the team workflow (discovered status-list tool). Missing name → hard-stop with rename/override instructions.
5. Cache team id, status ids for mapped states, and (optionally) label ids for the session.

### `ensure_product_container`

| | |
|---|---|
| **Intent** | Team resolvable; optional labels ready. **No** single long-lived product Project for all URs. |
| **Sequence** | Preflight steps 2–4. Optionally `search_tool` for labels; create missing `Layer/*`, `Size/*`, `path-unit` labels only if create-label tools are discovered and config requires them. |
| **Failure** | Hard-stop; never create markdown `.do-work/` as substitute product container. |

### `create_ur`

| | |
|---|---|
| **Intent** | Record intake brief as Initiative + linked Project `do-work/{UR-id}`. Does **not** create REQs. |
| **Preconditions** | Preflight passed; next `UR-NNN` slug allocatable. |
| **Atomicity** | Initiative + Project + link must succeed as one logical unit. **No partial Initiative without Project.** |

**Agent sequence:**

1. **Allocate next `UR-NNN` slug**
   - `search_tool` for projects and/or initiatives list tools.
   - List Initiatives/Projects for the team; scan for names matching `do-work/UR-*` and Initiative metadata `**UR-id:** UR-*`.
   - Pick next free sequential `UR-NNN` (also accept an id-cache if a later path adds one — v1 may scan live only).
2. **Build bodies**
   - Initiative title: apply `initiative_title_pattern` (e.g. `UR-007: Add SSO`).
   - Initiative description: §9.1 template with verbatim brief; `**Project:** do-work/{UR-id}`; leave `**Project-id:**` empty until step 4.
3. **Create Initiative**
   - `search_tool "linear initiative"` (or broader Linear search if empty).
   - If **no** initiative create tool is discovered → **hard-stop** (capability unknown/missing; do not invent). Do **not** create Project alone as a fake UR.
   - `use_tool` create with discovered schema (title + description + team as required).
   - Record initiative id.
4. **Create Project** named `do-work/{UR-id}` on configured team
   - `search_tool "linear project"`.
   - If create-project tool missing → **hard-stop**. Prefer **rolling back** the Initiative if a delete tool was discovered; otherwise leave operator recovery notes (orphan Initiative id) and stop. **Never** proceed to capture Issues.
   - `use_tool` create project; record project uuid.
5. **Link Project → Initiative** (`InitiativeToProject` or discovered equivalent)
   - `search_tool` for link / initiative-project relation.
   - If link tool **missing** after live probe → hard-stop with gap note (design critical cell); do not treat Project-only as a complete UR. Prefer rollback guidance over dual-write.
   - On success, update Initiative description `**Project-id:**` with project uuid (discovered update tool).
6. **Return** UR slug, initiative id, project id/name. **Do not** write `.do-work/user-requests/UR-NNN/`.

### `read_ur`

| | |
|---|---|
| **Intent** | Load brief + attached sections (ideate, clarifications, verify, closure if present). |
| **Sequence** | 1) Resolve Initiative by `UR-id` (list/search initiatives or Project name `do-work/{UR-id}` then linked initiative). 2) `search_tool` + get/read initiative (and comments if sections spilled). 3) Parse §9.1 markers. |
| **Failure** | Unknown UR → error to caller; MCP missing → hard-stop. |

### `list_urs`

| | |
|---|---|
| **Intent** | Enumerate URs (ids + titles) for prompts/status. |
| **Sequence** | `search_tool` → list Projects matching `do-work/UR-*` on the team **or** list Initiatives with `<!-- do-work-ur -->` / `**UR-id:**`. Return `UR-NNN` + title; use `read_ur` for full body. |
| **Failure** | MCP missing → hard-stop. |

### `create_req`

| | |
|---|---|
| **Intent** | Create one backlog REQ (Issue) in the UR’s Project. Optional path-unit parent + layer children as sub-issues. |
| **Preconditions** | UR Project exists (`do-work/{UR-id}` / project id from `create_ur` or resolve); preflight passed. |
| **Id rule** | Resulting id is the **Linear issue id only** (e.g. `ENG-123`). **Never** allocate `REQ-NNN`. |

**Agent sequence:**

1. Resolve **Project id** for `do-work/{UR-id}` (`search_tool` + list/get project). Missing project → hard-stop or fail create (UR incomplete).
2. Resolve **backlog** workflow state id from `status_map.backlog` (default `"Todo"`) via discovered status tools.
3. Build Issue **description** from §9.2 with capture fields (`**UR:**`, layer, files, depends-on Linear ids, size, priority, task, AC, verification, …). Titles short and actionable.
4. **Path-unit parent** (if this REQ is a path-unit):
   - Create parent Issue first: team + project + title + §9.2 body (`**Entry point:**` / `**Terminal state:**` filled); labels include `path-unit` when label tools exist.
   - For each layer child: create Issue with `parentId` (or schema field returned by live create-issue tool) set to parent Linear id; body `**Parent:** ENG-…`; layer label when available.
5. **Standalone / leaf REQ:**
   - `search_tool "linear create issue"` (or `"linear issues"`).
   - If create-issue undiscoverable → **hard-stop** (no markdown dual-write).
   - `use_tool` create: team, project, title, description, state=backlog map, optional assignee=`default_assignee_id`, labels, `parentId` when child.
6. **Deps at create (optional):** if dependency Linear ids are known, run the same dual-write as **`set_blocked_by`** (native `blocks` relations when tools exist **and** body `**Depends on:**` mirror). If relations missing → body-only + one-time warning (port rule).
7. **Labels:** attach `Layer/{name}`, `Size/{S|M|L}`, and `path-unit` (parents only) per **Labels** table when label tools exist.
8. **State:** create in `status_map.backlog` only (validated id from preflight) — never invent a state name.
9. Return Linear issue id(s). Human assignee only from config — agents do not steal assignee for claim (claim is later path).

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
| **Intent** | All REQs for a UR, any status — scoped to that UR’s **Project**. |
| **Sequence** | 1) Resolve Project id for `do-work/{UR-id}`. 2) `search_tool "linear list issues"` (or issues filter by project). 3) `use_tool` list filtered by **project id** (not global team backlog alone). 4) Return Linear ids + titles + states (+ parentId if present). |
| **Notes** | Design §6.3: project filter is the scope. Do not scan local `.do-work/REQ-*`. |
| **Failure** | Project missing → empty or error; MCP missing → hard-stop. |

### `append_ideate`

| | |
|---|---|
| **Intent** | Append or write ideate content onto an existing UR Initiative — **without** overwriting `## Brief`. |
| **Preconditions** | Preflight passed; UR exists (Initiative with §9.1 marker + `**UR-id:**`). |
| **Does not** | Create REQs, Projects, or local `ideate.md` files. |

**Agent sequence:**

1. **Rediscover** — `search_tool "linear initiative"` (and/or get/update initiative). Zero tools → hard-stop (setup block).
2. **Resolve Initiative** for `UR-NNN` (same as `read_ur`: scan Initiatives for `**UR-id:**` / Project `do-work/{UR-id}` → linked initiative).
3. **Read** current description (and comments if sections spilled). Require `<!-- do-work-ur -->`.
4. **Locate `## Ideate`** section:
   - If present and empty → replace section body with ideate markdown.
   - If present and non-empty → **append** new ideate content (prefer dated subheading or clear separator); do not delete prior ideate unless the phase explicitly replaces.
   - If missing → insert `## Ideate` after `## Clarifications` (or after `## Brief` if clarifications absent), preserving order of other §9.1 sections.
5. **Never** modify `## Brief` verbatim intake.
6. **Write** — `use_tool` update initiative description with the merged markdown. If description hits size limits → post overflow as Initiative comment titled/tagged for ideate and leave a one-line pointer under `## Ideate`.
7. **Return** UR slug + initiative id. No `.do-work/user-requests/` write.

| Failure | Behavior |
|---------|----------|
| UR / Initiative not found | Error to caller |
| Marker missing / unparsable | Stop op; do not invent template |
| MCP / update tool missing | Hard-stop |

### `append_clarifications`

| | |
|---|---|
| **Intent** | Append question-phase Q&A onto the UR under `## Clarifications`. Does **not** create REQs. |
| **Preconditions** | Preflight passed; UR exists. |
| **Does not** | Overwrite `## Brief`; replace prior Q&A wholesale (append only). |

**Agent sequence:**

1. **Rediscover** — `search_tool` for initiative get/update (same surface as `append_ideate`).
2. **Resolve + read** Initiative; require `<!-- do-work-ur -->`.
3. **Locate `## Clarifications`**:
   - Append each Q&A as:

     ```markdown
     **Q:** {question}
     **A:** {answer}
     ```

   - Keep prior entries. If section missing, insert after `## Brief` before `## Ideate`.
4. **Write** updated description via discovered update tool (comment spill same as ideate if needed).
5. **Return** UR slug + initiative id.

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
| Linear MCP tools undiscoverable at `create_ur` / `create_req` / append / `set_*` | Hard-stop + setup instructions; **no** Initiative-only, **no** Issue invent, **no** markdown dual-write |
| `team_id` / `team_key` unresolved | Hard-stop; do not guess |
| Initiative create ok, Project/link fail | Hard-stop; no partial UR; operator recovery for orphan Initiative if rollback tools missing |
| Create-issue tools missing | Hard-stop; do not write `.do-work/REQ-*` |
| Template required fields unparsable on update/read | Stop the op; do not invent fields (port / design §14) |
| Missing `<!-- do-work-ur -->` / `<!-- do-work-req -->` on structured write | Stop the op; do not auto-rewrap without explicit migrate |
| Any `status_map` state name missing on team workflow | Hard-stop + rename/override instructions; never invent states |

---

## Hard-stop when Linear MCP is missing or unusable

When `tracker.backend` is **`linear`**, failure is a **hard stop**. **Never** silent-fallback to markdown work-item ops, invent tickets, or write substitute UR/REQ files under `.do-work/`.

### Operator-facing message (use as template)

```text
HARD STOP: Linear tracker backend is configured but Linear MCP is not usable.

do-work will not fall back to markdown work-item storage while tracker.backend is "linear".
No issues, initiatives, or local REQ/UR substitutes were invented.

What failed: <MCP missing | unauthenticated | tools undiscoverable | team unresolved | status_map state missing>

Fix — connect Linear MCP (from Linear skill setup):

1. Preferred (API key):
   - Create a Personal API key in Linear → Settings → Account → Security & access
   - Export in the shell that launches the agent (do not paste the key into chat):
       export LINEAR_API_KEY='lin_api_...'
   - Configure MCP server `linear` at https://mcp.linear.app/mcp with
       Authorization: Bearer ${LINEAR_API_KEY}
   - Restart the agent / refresh MCP (`/mcps` → r) and verify tools via search_tool "linear"

2. OAuth alternative (if your host supports it):
   - Add HTTP MCP server `linear` → https://mcp.linear.app/mcp
   - Authenticate in `/mcps` (or host equivalent)
   - If OAuth sticks on "authenticating", use the API key path instead

3. Grok CLI examples (host-specific):
   - grok mcp add --transport http linear https://mcp.linear.app/mcp
   - grok mcp enable linear
   - grok mcp doctor linear

4. Team config (when MCP works but team fails):
   - Set tracker.linear.team_id (UUID) and/or tracker.linear.team_key in .do-work/config.yml
   - Do not guess a team

5. status_map (when team loads but a workflow state name is missing):
   - Defaults: backlog→"Todo", in_progress→"In Progress", stopped→"Canceled", done→"Done"
   - Rename the team workflow state to match, OR override tracker.linear.status_map.<key>
     to an existing state name on that team
   - Missing states are never invented

Then re-run the phase. If a claim was already active when MCP died mid-flight, leave it;
use /do-work resume or unblock after MCP recovers (port: leave claimed).
```

### Conditions → stop (summary)

| Condition | Behavior |
|-----------|----------|
| `search_tool` returns no Linear tools | Hard stop + setup steps above |
| MCP offline / unauthenticated mid-session | Hard stop; if already claimed → leave claimed |
| Team id/key unresolved | Hard stop; do not guess |
| Any `status_map` value missing on team workflow | Hard stop + rename / override instructions |
| Relation tools missing after spike documents **missing** | Prefer fallback in this file; description-only deps + one-time warning — still no markdown fallback |

---

## status_map validation (documented for spike)

Config defaults (`agents/config.md` / design §7):

| do-work status | Default Linear state name |
|----------------|---------------------------|
| `backlog` | `Todo` |
| `in_progress` | `In Progress` |
| `stopped` | `Canceled` |
| `done` | `Done` |

**Rules (design clarification):**

1. Ship the defaults above.
2. When `backend: linear`, **validate every mapped state exists** on the resolved team’s workflow (live list statuses tool once discovered).
3. If any mapped name is missing → **hard-fail** with rename-or-override instructions (template above). Do not invent states; do not pick a “close enough” name.
4. Live sandbox validation results (actual state names on the spike team) are recorded after a successful MCP-connected probe — not invented.

**Sandbox findings (REQ-289, 2026-07-31):**

| Check | Result |
|-------|--------|
| Linear MCP discoverable via `search_tool` | **Failed** — no `linear` server; no `linear__*` tools |
| Authenticated session / sandbox team | **Not attempted** — blocked by missing MCP |
| Default `status_map` names present on team (`Todo`, `In Progress`, `Canceled`, `Done`) | **Not validated** — no workflow-states tool |
| Initiatives / InitiativeToProject / issue relations `blocks` / Team Docs | **Unavailable to classify** — matrix unavailable; remain **unknown** (not **missing**; missing requires a live empty probe) |

**Implication for CRUD REQs (REQ-290):** agent sequences for UR/REQ CRUD are **documented** and must still run live `search_tool` on every call. Until a session with Linear MCP connected rewrites matrix rows as **available**, runtime execution of those sequences **hard-stops** at rediscovery — that is correct, not a license to invent tools or dual-write. Hard-stop copy in this file is the operator path.

---

## Hierarchy (design lock — implementation after spike)

```
Team (config)
└── Initiative (UR) — brief, ideate, verify, close
    └── Project do-work/{UR-id}  — linked via InitiativeToProject (or discovered equivalent)
        └── Issue (path-unit parent)
            └── Sub-issue (layer child)
```

| Entity | Naming |
|--------|--------|
| Project | `do-work/{UR-id}` (e.g. `do-work/UR-007`) — machine-stable |
| Initiative | Human title; may include UR id for scanability |
| Issue | Linear identifier only |

---

## Non-ticket artifact homes (design §10)

| Artifact | Linear home | Notes |
|----------|-------------|-------|
| Decisions | Team Doc `tracker.linear.decisions_doc_title` (default `do-work/decisions`) | create-if-missing once Docs tools proven |
| Calibration | Team Doc `tracker.linear.calibration_doc_title` | same |
| Run / cost notes | Issue comments | optional Project update rollup |
| Verify / close | Initiative description sections + comments | |
| Milestone cursor | Project description marker | local gate locks stay local |
| Gate locks | **Local** `state/*` | not Linear |

---

## Claim protocol reminder (representation only)

Semantics: `port.md`. Linear representation (after spike confirms comment tools):

- Human owns **assignee** (`default_assignee_id`).
- Agents claim via workflow state → in_progress + claim **comment** with `agent_claim_marker`.
- Heartbeat = refreshed claim-protocol comment timestamp.
- Optimistic re-read before write; loser → concurrent-conflict / stop; resume allowed.
- Mid-flight MCP death: **leave claimed**; resume/unblock repairs.

Example claim comment body:

```markdown
<!-- do-work-claim -->
agent_id: hostname.pid
claimed_at: 2026-07-31T12:00:00Z
heartbeat: 2026-07-31T12:05:00Z
session: optional-uuid
status: active
```

---

## Deps authority (Linear)

Native **`blocks` relations** are authoritative for `list_claimable_reqs` / deps checks. Issue body `**Depends on:**` is a **mirror**. **`set_blocked_by`** (REQ-291 sequence) always:

1. Updates relations when relation tools are discoverable (add/remove to match the target set).
2. Updates the body mirror in the same op.
3. If relations tools are **missing** after live probe → body-only + one-time warning (port rule); never markdown dual-store.
4. If spike later marks relations **missing** (not merely **unknown**), document GraphQL/other fallback in this section before production claim depends on it.

Dependency ids are **Linear issue identifiers only**.

---

## Out of scope for this file state

- Claim / heartbeat / unblock / resume / `list_claimable_reqs` / `archive_req` / `set_req_status` full sequences → later REQs.
- Capture/ideate/question/verify **phase playbook** rewires that *call* these ops → later REQs (port op sequences for UR/REQ templates + append/deps/footprint are in this file as of REQ-291).
- Non-ticket Docs, run notes, calibration, milestone cursor, migration → later path-units.
- Production migration of existing `.do-work/` work items → REQ-300 path.
- Dual-write or treating local REQ files as source of truth while `backend: linear`.
- Inventing tool names not returned by live `search_tool` (including treating Linear skill typical-tool tables as proven).

---

## References

- `agents/tracker/port.md` — shared ops and hard-stop / leave-claimed / relations-authoritative rules
- `agents/config.md` — `tracker.*` schema and Load Config step 7
- Design: `docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md` (§6 hierarchy, §7 config, §8 claim, §9 templates, §10 homes, §14 errors, §17 risks)
- Linear skill: MCP-first, rediscover tools live (`search_tool` → `use_tool`)
- Prior: REQ-288 path + REQ-289 matrix (matrix unavailable without Linear MCP); REQ-290 UR/REQ CRUD path; REQ-291 templates + append/deps/footprint
