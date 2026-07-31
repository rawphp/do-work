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
| Full op sequences / templates / claim | Deferred — other path-units after matrix is known | REQ-290+ (blocked until MCP-connected fill) |

**Do not** invent Linear tool names as if proven. Until a **later** live probe (post-REQ-289, with Linear MCP connected) records a row as **available**, treat tool names as **unknown**.

---

## When to load

After config load and backend resolution (`port.md` load path + `agents/config.md` Load Config step 7):

1. Effective backend is **`linear`**.
2. Linear validation passes (team resolvable, MCP discoverable, every `status_map` state exists on the team) — or agent **hard-stops** (see below).
3. Read `agents/tracker/port.md`.
4. Read this file.
5. Perform work-item ops only via port ops mapped here (sequences expand after the spike).

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

### Port op readiness (scaffolding — sequences after spike)

Until the matrix row for each dependency is **available**, op sequences stay **blocked / TBD**. Do not invent MCP call chains.

| Port op | Depends on capability rows | Sequence status |
|---------|----------------------------|-----------------|
| `ensure_product_container` | Team resolve, labels (optional) | TBD after spike |
| `create_ur` / `read_ur` / `list_urs` | Initiatives, Projects, Initiative↔Project link | TBD after spike |
| `append_ideate` / `append_clarifications` | Initiatives (description/comments) | TBD after spike |
| `create_req` / `update_req` / `read_req` | Issues, Projects, labels, statuses | TBD after spike |
| `list_reqs_for_ur` / `list_claimable_reqs` | Issues by project, relations, comments, statuses | TBD after spike |
| `claim_req` / `heartbeat_req` / `unblock_req` | Issues status + comments | TBD after spike |
| `set_req_status` / `archive_req` | Workflow states, issues | TBD after spike |
| `set_blocked_by` | Issue relations `blocks` (+ body mirror) | TBD after spike; if relations **missing** → description-only + one-time warning (port rule) |
| `set_files` | Issue description headers | TBD after spike |
| `append_decision` / calibration | Team Docs | TBD after spike |
| `write_verify_report` / `write_close_report` | Initiative sections/comments | TBD after spike |
| `append_run_note` | Issue comments (+ optional project update) | TBD after spike |
| Milestone ops | Project description / labels / milestone entity if any | TBD after spike |
| `write_gate_state` | **Local** `state/gate-owner.md` (not Linear) | Local only |

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

**Implication for CRUD REQs:** treat all port op sequences as **still blocked** until a later session with Linear MCP connected rewrites matrix rows from observed tools. Hard-stop copy in this file is the operator path.

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

Native **`blocks` relations** are authoritative for `list_claimable_reqs` / deps checks. Issue body `**Depends on:**` is a **mirror**. `set_blocked_by` updates both when relation tools exist. If the spike marks relations **missing**, document GraphQL/other fallback here or fall back to description-only + one-time warning (port rule) — still never markdown dual-store.

---

## Out of scope for this path-unit file state

- Full step-by-step MCP sequences for every port op → post-spike REQs (CRUD, claim, run, artifacts, milestone, migrate).
- Production migration of existing `.do-work/` work items → REQ-300 path.
- Dual-write or treating local REQ files as source of truth while `backend: linear`.
- Inventing tool names not returned by live `search_tool`.

---

## References

- `agents/tracker/port.md` — shared ops and hard-stop / leave-claimed / relations-authoritative rules
- `agents/config.md` — `tracker.*` schema and Load Config step 7
- Design: `docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md` (§6 hierarchy, §7 config, §8 claim, §10 homes, §14 errors, §17 risks)
- Linear skill: MCP-first, rediscover tools live (`search_tool` → `use_tool`)
