# Design: Do-work multi-tracker (markdown + Linear)

**Date:** 2026-07-31  
**Status:** approved for implementation planning  
**Source:** `.scratch/do-work-multi-tracker/` wayfinder + brainstorming session  

## 1. Problem

do-work stores work items (URs, REQs, decisions, verify/close reports) only as local markdown under `.do-work/`. Operators who want Linear as the system of record cannot run the full do-work loop without dual-maintaining tickets. The skill needs a second backend without rewriting product philosophy (TDD-per-REQ, worktrees, review gate, multi-agent claim/deps/footprint).

## 2. Goals

1. **Markdown remains the default backend** — current UR/REQ files and `lib/*.sh` behavior stay the happy path when `tracker.backend` is unset or `markdown`.
2. **Linear is a full second backend** — with `tracker.backend: linear`, work items live **only** in Linear (no dual-write, no local UR/REQ markdown as source of truth).
3. **Tracker port** — one conceptual op catalog; backends plug in. GitHub Issues / Jira can follow later as new backend files (not built in this effort).
4. **v1 ship surface = full map destination** — core loop (intake → ideate → capture → verify → run claim/deps/footprint → status/close), **milestone mode**, Linear homes for ledger notes / decisions / verify / close / calibration, and **idle one-shot markdown→Linear migration**.

### Done when

- Default/markdown: behavior matches today (regression).
- Linear configured: an agent can complete intake → ideate → capture → verify → run (claim / deps / footprint) → status / close against Linear via the Linear skill/MCP, preserving multi-agent safety semantics.
- Milestone deploy gates work under Linear mode.
- Non-ticket artifacts have fixed Linear homes; agents do not invent ad-hoc locations.
- Idle migration moves a markdown project to Linear without dual-write.

## 3. Non-goals

- Implementing GitHub Issues or Jira backends (pattern only).
- Dual-write or markdown mirror while on Linear.
- Changing TDD-per-REQ, worktree isolation, or post-build review philosophy — only the **store** for work items changes.
- Requiring Linear for all users.
- True distributed locks on Linear (optimistic claim only).

## 4. Decisions (locked)

| Decision | Choice |
|----------|--------|
| Architecture | Tracker port docs: `agents/tracker/{port,markdown,linear}.md` |
| Hierarchy | **UR = Project Milestone** on a shared product Project (`tracker.linear.product_project`); REQs = Issues in that Project with `milestone` = UR milestone. *(2026-07-31: supersedes Initiative + per-UR Project — Linear MCP has no Initiative create tools.)* |
| Product container | Team + config — **not** one long-lived product Project for all URs |
| Linear IDs | Linear mode uses Linear issue identifiers only (e.g. `ENG-123`). No parallel `REQ-NNN` allocation |
| UR naming slug | Sequential `UR-NNN` still used as Project name / Initiative metadata slug only |
| Path-units | Parent Issue + layer children as sub-issues (`parentId`) |
| Deps | Native Linear relation type `blocks` (+ mirrored `**Depends on:**` line in body) |
| Footprint | Structured `**Files:**` (and related header fields) in Issue description — no custom fields |
| Claim | Human operator remains Linear **assignee**; agents claim via workflow status + heartbeat **comment** protocol |
| Claim atomicity | Optimistic re-read before write; loser → concurrent-conflict / stop; resume allowed |
| Linear unusable | Hard stop — never silent fallback to markdown |
| Migration | One-shot when idle (`working/` empty); then Linear-only |
| Non-ticket park | Decisions + calibration = team Docs; verify/close = Initiative; run notes = Issue comments (+ optional Project update) |
| Runtime/git | Stay local: worktrees, merges, `state/*` locks, events, config.yml |

## 5. Architecture

### 5.1 File layout

```
agents/tracker/port.md       # shared contract: op names, preconditions, agent-callable surface
agents/tracker/markdown.md   # file + lib/*.sh implementation of those ops
agents/tracker/linear.md     # Linear skill/MCP sequences for the same ops
# later: agents/tracker/github.md, jira.md
```

### 5.2 Load path

Every phase agent that touches work items:

1. Load config (`agents/config.md`)
2. Resolve `tracker.backend` (default `markdown` if missing/empty)
3. Read `agents/tracker/port.md`
4. Read `agents/tracker/<backend>.md`
5. For work-item storage, call **only** named port ops (never raw `.do-work/REQ-*` paths or raw Linear tools outside the backend file)

Phase agents keep product logic (TDD, review, decomposition). They do not re-implement store details.

### 5.3 Bash vs agent steps

| Backend | Work-item ops | Runtime |
|---------|---------------|---------|
| **markdown** | Existing `lib/*.sh` + file paths, documented in `markdown.md` | worktrees, git, events, state locks — unchanged |
| **linear** | Agent steps invoking Linear skill/MCP, documented in `linear.md`. No Linear-aware bash required for v1 | same local runtime/git |

Shared **rules** (when to claim, what “deps satisfied” means, footprint overlap) live in `port.md`. Shared **shell** only for the file store.

### 5.4 Operation catalog

Coarse lifecycle (~12–25 ops). Names freeze intent; exact set may grow slightly when templates land:

| Op | Intent |
|----|--------|
| `ensure_product_container` | Team/product labeling ready; no single product Project required |
| `create_ur` | Record intake brief |
| `read_ur` | Load brief (+ ideate if present) |
| `list_urs` | Enumerate URs for prompts/status |
| `append_ideate` | Write ideate onto UR |
| `append_clarifications` | Question phase Q&A |
| `create_req` | Create one REQ in backlog |
| `update_req` | Edit REQ body/fields |
| `read_req` | Load full REQ |
| `list_reqs_for_ur` | All REQs for a UR (any status) |
| `list_claimable_reqs` | Backlog, deps ok, footprint ok, unclaimed — pick order |
| `claim_req` | Optimistic claim + in-progress |
| `heartbeat_req` | Refresh liveness |
| `set_req_status` | stopped / in-progress / etc. |
| `set_blocked_by` | Deps graph |
| `set_files` | Footprint list |
| `archive_req` | Done + closure proof / outputs |
| `unblock_req` | Return to backlog, clear claim |
| `append_decision` | Standing decisions memory |
| `write_verify_report` | Verify output for a UR |
| `write_close_report` | Close output for a UR |
| `append_run_note` | Ledger-ish / cost note for a REQ or run |
| `read_active_milestone` | Milestone cursor |
| `set_active_milestone` | Advance / set milestone |
| `list_milestone_reqs` | REQs for active milestone |
| `write_gate_state` | Deploy-gate coordination (local lock still allowed) |

Markdown may implement several ops by composing existing scripts. Linear maps each to skill/MCP sequences.

### 5.5 Work-item vs runtime split

From storage inventory (~88 ops): **work-item** data moves to Linear in Linear mode; **runtime/git/config** stay local.

**Must map to Linear:** UR create/read/update; REQ create/edit; status transitions; deps/footprint fields; archive (done + proof + outputs); decisions; close/verify reports; ideate/clarifications; run cost notes; calibration; milestone cursor content.

**Stay local:** claim stamp equivalent is comments (not files) but **local** still includes worktrees, branches, merges, PRs, `state/events.jsonl`, gate-owner, final-suite locks, feedback.lock, context-pack, retry-counters, config.yml, conformance/install.

## 6. Linear hierarchy and identifiers

### 6.1 Hierarchy

**(Updated 2026-07-31.)** UR home is a **Project Milestone**, not an Initiative — Linear MCP exposes milestone CRUD but not Initiative create/list.

```
Team (config)
└── Product Project (tracker.linear.product_project, e.g. do-work)
    ├── Project Milestone (UR) — brief, ideate, verify, close
    │   └── Issue (path-unit parent)  [milestone = UR]
    │       └── Sub-issue (layer child)
    └── Project Milestone (next UR)
        └── Issue …
```

### 6.2 Naming

| Entity | Naming |
|--------|--------|
| Product Project | `tracker.linear.product_project` (default `do-work`) — shared; not one Project per UR |
| UR Milestone (human-facing) | `ur_milestone_name_pattern` (default `{ur_id}: {title}`); body has `**UR-id:** UR-NNN` |
| Issue | Linear identifier only (`ENG-123`). Titles short and actionable; body holds do-work schema |

### 6.3 List / scope

| Need | How |
|------|-----|
| `list_reqs_for_ur` | `list_issues` filtered by **product Project** + **UR milestone** |
| `list_claimable_reqs` | Same project filter + status + deps + footprint + unclaimed |
| `status` for a UR | Issues for that milestone + claim comments |
| `read_ur` | UR milestone description (and comments if needed) |
| Product-wide backlog | All issues in product Project (optionally all milestones) |

### 6.4 Intake create sequence (Linear)

1. Ensure product Project exists (`product_project`).
2. Allocate next `UR-NNN` slug (scan existing Project Milestones for `**UR-id:**` / name).
3. Create **Project Milestone** (name from pattern; description = §9.1 template with verbatim brief).
4. Capture creates Issues (and sub-issues) on the product Project with `milestone` set to that UR milestone.

### 6.5 Commits and PRs (Linear mode)

Commit / PR messages reference the Linear issue id:

```
feat(ENG-123): short title

Issue: ENG-123
UR: UR-007
Output: path/to/primary/output
```

No `.do-work/archive/REQ-…` path required. Worktree branch naming may use `req/ENG-123` (sanitize for git ref rules).

## 7. Config schema

```yaml
tracker:
  backend: markdown          # markdown | linear
  linear:
    team_id: ""              # required when backend=linear (or resolve via team_key)
    team_key: ""             # optional alternate resolve
    default_assignee_id: ""  # human operator; set on issue create when configured
    project_name_pattern: "do-work/{ur_id}"
    initiative_title_pattern: "{ur_id}: {title}"
    status_map:
      backlog: "Todo"
      in_progress: "In Progress"
      stopped: "Canceled"    # override if team has a dedicated Stopped state
      done: "Done"
    labels:
      layer_prefix: "Layer/"
      path_unit: "path-unit"
      size_prefix: "Size/"
    agent_claim_marker: "<!-- do-work-claim -->"
    heartbeat_max_age_seconds: null  # null → use parallel.stale_threshold_seconds
    decisions_doc_title: "do-work/decisions"
    calibration_doc_title: "do-work/calibration"
```

**Validation when `backend: linear`:** hard fail if team cannot be resolved or Linear MCP tools are undiscoverable. Message must tell the operator how to connect Linear (skill setup), not invent data.

**Interaction with existing keys:** `ledger`, `parallel`, `delivery`, `review`, `layers` remain valid. In Linear mode, **authoritative** run/cost notes are Linear Issue comments via `append_run_note`. If `ledger.enabled: true`, the orchestrator may **also** append local `.do-work/runs/RUN-NNN.yml` for offline retro tooling — that local file is telemetry only, not a second work-item store. Retro prefers Linear run notes when `backend: linear`, falling back to local runs if comments are unavailable.

## 8. Claim protocol (Linear)

Human always owns **assignee** (config `default_assignee_id` on create; agents do not steal assignee for claim).

| Concept | Rule |
|---------|------|
| Unclaimed | Workflow state maps to backlog **and** no active claim comment (or last claim is `released` / unblocked) |
| Claim | Re-read issue; if another agent has active claim and fresh heartbeat → fail; else set state → in_progress; post comment with `agent_claim_marker`, `agent_id`, `claimed_at`, `heartbeat`, optional `session`, `status: active` |
| Heartbeat | New claim-protocol comment (or append) with updated `heartbeat` ISO timestamp; consumers take the latest active claim block |
| Stale | Latest active heartbeat older than `heartbeat_max_age_seconds` or `parallel.stale_threshold_seconds` |
| Unblock | State → backlog; claim comment `status: released` |
| Resume | stopped → in_progress; refresh heartbeat; assignee unchanged |
| Concurrent conflict | Same stopper semantics as markdown multi-agent mode |

**Atomicity story:** MCP has no filesystem atomic rename. Good enough = re-read + comment protocol + timestamp. Document as intentional.

### Example claim comment

```markdown
<!-- do-work-claim -->
agent_id: hostname.pid
claimed_at: 2026-07-31T12:00:00Z
heartbeat: 2026-07-31T12:05:00Z
session: optional-uuid
status: active
```

## 9. Templates

### 9.1 Initiative (UR)

Machine-stable sections in Initiative description:

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

Prefer description appends; fall back to Initiative comments if size limits require it.

### 9.2 Issue (REQ)

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

**Labels:** `Layer/{name}`, `Size/{S|M|L}`, `path-unit` on parents.  
**Estimate:** map Size to team T-shirt when enabled.  
**States:** via `status_map`.  
**Deps:** create `blocks` relations and mirror ids in `**Depends on:**`.  
**Path-units:** parent Issue + sub-issues; children set Linear `parentId` and `**Parent:**`.

## 10. Non-ticket artifact homes

| Artifact | Linear home | Format | Writers / readers |
|----------|-------------|--------|-------------------|
| Decisions | Team Doc `do-work/decisions` (create-if-missing) | One line per decision (same as today) | capture write; capture/ideate/question/worker read |
| Run / cost notes | Comment on Issue after attempt; optional Project update for run rollup | YAML fenced block (ledger fields) | run |
| Verify report | Initiative `## Verify` + Initiative comment | Full report markdown | verify, go |
| Close report | Initiative `## Closure` + comment | Per path-unit results | close |
| Calibration | Team Doc `do-work/calibration` | Full calibration body | retro write; capture read |
| Milestone cursor | Project description `<!-- do-work-milestone -->` | active M + checklist | capture, run |
| Gate locks | **Local** `state/gate-owner.md`, `final-suite-*.md` | unchanged | run |

## 11. Milestone mode (Linear)

- Trigger unchanged (UR shape with `source: /saas-thesis handoff` + `### Milestones`).
- REQs for a milestone are Issues in the UR Project, filterable by milestone marker (Project milestone entity when MCP supports it, else label `M1` / section metadata).
- Active milestone cursor on Project description marker.
- Deploy gate: first orchestrator owns gate via **local** `state/gate-owner.md`; human y/n advances cursor; siblings idle as today.

## 12. Migration (markdown → Linear)

One-shot, idle-only:

1. **Preflight:** no files in `working/`; no active claims; operator confirms.
2. Create/update Team Docs for decisions (and empty calibration if missing).
3. For each UR: create Initiative + Project `do-work/UR-NNN` + link; body from `input.md` / ideate / closure.
4. For each REQ in backlog + archive: create Issue in that Project; map status; relations; parent/sub-issues; preserve checkboxes. In-flight forbidden by preflight.
5. Set `tracker.backend: linear` and resolved team ids in config.
6. Leave `.do-work/user-requests/` and `archive/` as **read-only historical** trees (do not delete); work-item ops stop reading them.
7. No dual-write after cutover.

Surface via `/do-work upgrade` conformance/migrate path or an explicit migrate step documented in upgrade agent — implementation plan chooses the exact command UX without changing these rules.

## 13. Agents and libraries in scope

**Must load port and branch on backend:**  
intake, capture, ideate, question, audit, verify, run, run-worker, review, status, close, unblock, resume, start, go, upgrade, retro, log, help (docs pointers).

**lib/*.sh:** remain markdown-backend implementations. Linear reimplements pick/claim/deps/footprint/heartbeat/archive-integrity **semantics** in `linear.md` via MCP. No requirement for Linear-aware bash in v1.

**SKILL.md + config.md:** document `tracker.*`, load path, hard-stop rules, commit convention for Linear ids.

## 14. Error handling

| Failure | Behavior |
|---------|----------|
| Linear MCP missing / unauthenticated | Hard stop with setup instructions from Linear skill |
| Team id unresolved | Hard stop; do not guess |
| Claim race lost | Stop with concurrent-conflict; `/do-work resume` allowed |
| Relation tool missing | Prefer GraphQL/fallback documented in `linear.md`; if unavailable, description-only deps + one-time warning |
| Template parse failure | Stop REQ; do not invent fields |
| Budget reached | Same boundary as today; costs from Linear run notes |

## 15. Testing and proof

1. **Markdown regression:** existing `lib/tests` + conformance pass with `backend: markdown` (default).
2. **Port contract:** checklist that both backend docs implement every op name in `port.md`.
3. **Linear capability spike:** before full Linear CRUD, sandbox-team harness rediscovers tools live (`search_tool`) and commits a capability matrix in `agents/tracker/linear.md` (Initiatives, Projects, InitiativeToProject, `blocks` relations, Team Docs, comments, workflow/`status_map` states). Tool names stay **unknown** until proven; no secrets in repo; no production work-item migration during the spike.
4. **Linear integration:** sandbox team manual/agent harness after matrix fill; no secrets in repo.
5. **Migrate dry-run:** report planned creates without writing when flag set.

## 16. Implementation phasing (for writing-plans)

Suggested dependency order (single plan, multi-PR REQs):

1. Config schema + load path + `port.md` stub ops + `markdown.md` mapping existing behavior  
2. **Linear MCP capability spike** — `agents/tracker/linear.md` skeleton + live matrix (rediscover tools; hard-stop copy; `status_map` validation notes) **before** wiring full CRUD  
3. Initiative/Issue templates + `linear.md` CRUD for UR/REQ (only after spike cells for hierarchy/relations/Docs are known)  
4. Claim/heartbeat/unblock/resume + status  
5. Capture/ideate/question/verify against port  
6. Run loop pick/claim/deps/footprint/archive on Linear  
7. Close, decisions doc, run notes, calibration  
8. Milestone mode on Linear  
9. Migration one-shot + upgrade wiring  
10. Docs (SKILL.md, getting-started, troubleshooting)

## 17. Open risks

1. **Linear MCP offline / thin tools** — initiative link, issue relations may need GraphQL; agents must rediscover tools live. Mitigation: capability matrix + hard-stop copy in `agents/tracker/linear.md` (spike path before CRUD).
2. **No custom fields** — all structure is markdown conventions; parse discipline is mandatory.
3. **Optimistic claim** — weaker than FS rename; acceptable with documented conflict/resume.
4. **Linear IDs only** — breaks continuity with markdown `REQ-NNN` history after migrate (by design).
5. **Human assignee + agent claim comments** — humans can still edit Linear UI and break protocol; status/docs should warn “do not clear agent claim comments while run is live.”

## 18. References

- `.scratch/do-work-multi-tracker/map.md` and issues 01–10  
- `docs/superpowers/specs/2026-05-21-do-work-parallel-coordination-design.md`  
- `agents/config.md`, `SKILL.md`  
- Linear skill: MCP-first, rediscover tools live  
