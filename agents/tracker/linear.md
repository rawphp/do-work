# Tracker backend: linear (opt-in)

Implements the tracker port (`agents/tracker/port.md`) with **Linear as the sole work-item store** when `tracker.backend: linear`. Agent steps invoke the Linear skill / MCP; there is **no** Linear-aware bash in v1 and **no** dual-write to local UR/REQ markdown.

**This is not the default.** When `tracker.backend` is missing, empty, or `markdown`, agents load `markdown.md` instead — Linear tools are not required.

---

## When to load

After config load and backend resolution (`port.md` load path + `agents/config.md` Load Config step 7):

1. Effective backend is **`linear`**.
2. Linear validation passes (team resolvable, MCP discoverable, every `status_map` state exists on the team) — or agent **hard-stops** (see below).
3. Read `agents/tracker/port.md`.
4. Read this file (index + hard rules).
5. When executing a named op sequence, read the one-hop reference listed in the **Port op index** below.

**Exception — idle migration:** `/do-work upgrade migrate` / `migrate_markdown_to_linear` loads while backend is still **`markdown`**. Sequence: [references/linear-paths.md](../../references/linear-paths.md) (migration path section).

Do **not** load this file for ordinary work-item ops when backend is `markdown` (except the migration path).

---

## Hierarchy (authoritative)

```
Team (config)
└── Project product_project (default "do-work")   — shared for all URs
    ├── Project Milestone (UR)   — §9.1 <!-- do-work-ur -->
    └── Issue (REQ)              — attached to that UR milestone
        └── Sub-issue (layer child)
```

| Entity | Naming / config |
|--------|-----------------|
| Product Project | `tracker.linear.product_project` (default `do-work`) — **shared** |
| UR | **Project Milestone** on that project; name `ur_milestone_name_pattern` (default `{ur_id}: {title}`) |
| REQ | **Linear issue id only** (e.g. `ENG-123`) — no parallel `REQ-NNN` |
| Issue scope | product Project + UR Project Milestone membership |

### Hard rules (hierarchy)

1. **No Initiative-as-UR** — MCP has no reliable Initiative create path; URs are Project Milestones.
2. **`product_project` is shared** — do not create `do-work/{UR-id}` Projects per UR as the UR container.
3. **Atomic `create_ur`** — product Project ensure + milestone create; no partial UR; hard-stop on failure.
4. **Rediscover, never invent** — every op begins with `search_tool`; hard-stop if tools missing.
5. **No dual-write** — Linear is sole work-item store while `backend: linear`.

### Disambiguation: Milestone-as-UR vs path-milestone mode (M1/M2)

| | **Milestone-as-UR** | **Path-milestone mode (M1/M2)** |
|--|---------------------|--------------------------------|
| What | The UR *entity* | Optional delivery mode *inside* one UR |
| Trigger | Every Linear UR | Brief has `source: /saas-thesis handoff` **and** `### Milestones` with `#### M1`+ |
| Store | Linear Project Milestone | Cursor `<!-- do-work-milestone -->` on that **same** UR milestone description; Issues marked `M1`/`M2` |
| Ops | `create_ur` / `read_ur` / `list_urs` | `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` |
| Detail | This section + [linear-ops.md](../../references/linear-ops.md) | [linear-path-milestones.md](../../references/linear-path-milestones.md) |

---

## Tool rediscovery (hard rule)

1. Call **`search_tool`** scoped to Linear.
2. Call **`use_tool`** only with a **qualified** name + **`input_schema`** from that search.
3. Never hard-code tool names; never fabricate issues/milestones when MCP is down; never silent-fallback to markdown.

Official remote MCP: `https://mcp.linear.app/mcp`. Setup: Linear skill `SKILL.md`.

---

## Port op index

Read the pointed reference **when executing that op** (one hop only — no references→references chains for further sequences).

| Port op / surface | When to load | Reference |
|-------------------|--------------|-----------|
| `ensure_product_container` | Before first CRUD in session; intake | [linear-ops.md](../../references/linear-ops.md) § ensure_product_container |
| **`create_ur`** | Intake / start | [linear-ops.md](../../references/linear-ops.md) § create_ur |
| `read_ur` / `list_urs` | Any phase needing brief / UR list | [linear-ops.md](../../references/linear-ops.md) |
| `create_req` / `update_req` / `read_req` / `list_reqs_for_ur` | Capture / workers | [linear-ops.md](../../references/linear-ops.md) |
| `append_ideate` / `append_clarifications` | Ideate / question | [linear-ops.md](../../references/linear-ops.md) |
| `set_blocked_by` / `set_files` | Deps / footprint writers | [linear-ops.md](../../references/linear-ops.md) |
| `list_claimable_reqs` / `claim_req` / `heartbeat_req` | Run pick/claim | [linear-ops.md](../../references/linear-ops.md) |
| `set_req_status` / `unblock_req` / Resume / Status | Stop / unblock / resume / status | [linear-ops.md](../../references/linear-ops.md) |
| **`archive_req`** / `append_run_note` | Post-worker integrate | [linear-ops.md](../../references/linear-ops.md) |
| `append_decision` / calibration Doc | Capture / retro | [linear-ops.md](../../references/linear-ops.md) |
| `write_verify_report` / `write_close_report` | Verify / close | [linear-ops.md](../../references/linear-ops.md) |
| `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` / `write_gate_state` | Path-milestone mode only | [linear-path-milestones.md](../../references/linear-path-milestones.md) |
| §9 templates / labels / path-units | Creating or parsing bodies | [linear-ops.md](../../references/linear-ops.md) § Templates |
| Commits / branch sanitize (§6.5) | Worker / merge under Linear | [linear-path-milestones.md](../../references/linear-path-milestones.md) (commits section) or [linear-ops.md](../../references/linear-ops.md) |
| Path narratives / capability matrix / migration | Spike fill, upgrade migrate | [linear-paths.md](../../references/linear-paths.md) |

### Templates (pointers only)

| Entity | Marker | Full template |
|--------|--------|---------------|
| UR Project Milestone | `<!-- do-work-ur -->` | [linear-ops.md](../../references/linear-ops.md) §9.1 |
| Issue (REQ) | `<!-- do-work-req -->` | [linear-ops.md](../../references/linear-ops.md) §9.2 |

On read/update: missing marker → **stop the op**; do not invent headers.

### Non-ticket artifact homes (summary)

| Artifact | Home | Op |
|----------|------|-----|
| Decisions | Team Doc `decisions_doc_title` | `append_decision` |
| Calibration | Team Doc `calibration_doc_title` | Write/read calibration |
| Run notes | Issue comment `<!-- do-work-run-note -->` | `append_run_note` |
| Verify / close | UR Project Milestone `## Verify` / `## Closure` + comment | `write_verify_report` / `write_close_report` |
| Path-milestone cursor | UR Project Milestone description `<!-- do-work-milestone -->` | milestone ops |
| Gate locks | **Local** `state/gate-owner.md` only | `write_gate_state` |

Full sequences: [linear-ops.md](../../references/linear-ops.md).

---

## status_map

| do-work status | Config key | Default Linear state name |
|----------------|------------|---------------------------|
| `backlog` | `status_map.backlog` | `Todo` |
| `in_progress` | `status_map.in_progress` | `In Progress` |
| `stopped` | `status_map.stopped` | `Canceled` |
| `done` | `status_map.done` | `Done` |

**Hard-fail:** when `backend: linear`, every mapped state **name** must exist on the team workflow. Missing → hard-stop (rename team state or override map). **Never** invent states; **never** pick “close enough”; **never** fall back to markdown.

Live sandbox validation (when MCP was missing) and matrix notes: [linear-paths.md](../../references/linear-paths.md).

---

## Hard-stop when Linear MCP is missing or unusable

When `tracker.backend` is **`linear`**, failure is a **hard stop**. **Never** silent-fallback to markdown work-item ops, invent tickets, or write substitute UR/REQ files under `.do-work/`.

### Operator-facing message (use as template)

```text
HARD STOP: Linear tracker backend is configured but Linear MCP is not usable.

do-work will not fall back to markdown work-item storage while tracker.backend is "linear".
No issues, Initiative-as-UR entities, or local REQ/UR substitutes were invented.

What failed: <MCP missing | unauthenticated | tools undiscoverable | team unresolved | status_map state missing | product_project unresolved>

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
   - Set tracker.linear.product_project (default name `do-work`) when the shared project is not yet resolved
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
| `product_project` unresolved / uncreatable | Hard stop |
| Any `status_map` value missing on team workflow | Hard stop + rename / override instructions |
| Milestone / issue create tools missing for `create_ur` / `create_req` | Hard stop; **no** Initiative-as-UR substitute; **no** markdown dual-write |
| Relation tools missing after spike documents **missing** | Prefer body-only deps + one-time warning — still no markdown fallback |

### Claim / mid-flight (summary)

| Event | Behavior |
|-------|----------|
| Fresh foreign active claim | `concurrent-conflict`; resume for owner |
| MCP dies after successful `claim_req` | **Leave claimed**; stop for resume/unblock; never silent-release; never markdown fallback |
| Human assignee | Sacred — agents never steal Linear assignee for claim |

Full claim/archive sequences: [linear-ops.md](../../references/linear-ops.md).

---

## Run-loop rules (pointers)

| Concern | Rule | Detail |
|---------|------|--------|
| Deps | Native **`blocks`** relations authoritative; body `**Depends on:**` mirror | [linear-ops.md](../../references/linear-ops.md) |
| Footprint | Issue `**Files:**` vs in-flight claims; empty = free | [linear-ops.md](../../references/linear-ops.md) |
| Pick order | Priority DESC (missing→2) → created_at ASC → id ASC | `list_claimable_reqs` |
| Archive | Only via **`archive_req`** after evidence + review gates | [linear-ops.md](../../references/linear-ops.md) |
| Commits | `feat(ENG-123):` + `Issue:` footer; branch `req/<sanitized-id>` | [linear-path-milestones.md](../../references/linear-path-milestones.md) |
| No Linear bash in `lib/` (v1) | Sequences are agent/MCP only | — |

---

## References

- [references/linear-ops.md](../../references/linear-ops.md) — CRUD, claim, archive, artifacts, templates
- [references/linear-path-milestones.md](../../references/linear-path-milestones.md) — path-milestone (M1/M2) ops + commits/branch sanitize
- [references/linear-paths.md](../../references/linear-paths.md) — path narratives, capability matrix, migration
- `agents/tracker/port.md` — shared ops + hard-stop / leave-claimed
- `agents/config.md` — `tracker.*` schema
- `agents/intake.md` / phase agents — Milestone-as-UR consumers (ORI-9)
- Design: `docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md`
