# Linear path narratives + capability matrix (reference)

One hop from [`agents/tracker/linear.md`](../agents/tracker/linear.md). Load when implementing or auditing a path-unit (REQ-288…301) or re-filling the capability matrix. **Not** the day-to-day op index — sequences live in [linear-ops.md](linear-ops.md).

**Hierarchy lock (authoritative):** UR = **Project Milestone** on shared `product_project` (default `do-work`). **Not** Initiative-as-do-work-Issue. Path narratives below may still mention historical Initiative wording in child-work tables; prefer the lock + [linear-ops.md](linear-ops.md) sequences.

## Disambiguation: Milestone-as-Issue vs path-milestone mode (M1/M2)

| Concept | What it is | Where it lives |
|---------|------------|----------------|
| **Milestone-as-Issue** | The Linear **Project Milestone** entity that *is* the do-work Issue (`UR-NNN`) | On shared **product Project** (`product_project`) |
| **Path-milestone mode (M1/M2)** | Optional *delivery* mode inside one UR when the brief has `source: /saas-thesis handoff` + `### Milestones` | Cursor block `<!-- do-work-milestone -->` on the **Issue Project Milestone description**; Linear issues (REQs) tagged `M1`/`M2` |

Do **not** create Linear Initiatives for Issues. Do **not** treat M1/M2 path-milestones as separate Issues.

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
| Full op sequences / templates / claim | Deferred — other path-units after matrix is known | REQ-290 documents Issue/REQ CRUD sequences (still `search_tool` live; claim/run later) |

**Do not** invent Linear tool names as if proven. Until a **later** live probe (post-REQ-289, with Linear MCP connected) records a row as **available**, treat tool names as **unknown**. CRUD sequences below still call `search_tool` first and hard-stop if undiscoverable — they do **not** treat skill “typical tools” tables as proven.

---

## Path: Linear Issue/REQ CRUD (REQ-290)

| | |
|---|---|
| **Entry point** | `/do-work` intake or start with `tracker.backend: linear` and valid team config (Load Config step 7) |
| **Terminal state** | product Project + Issue Project Milestone + Linear issues (REQs) on that milestone exist with §9 templates; `create_ur` / `create_req` / `update_req` / `read_req` / `list_reqs_for_ur` (+ `read_ur` / `list_urs`) sequences are documented as agent steps that rediscover tools live |

This path-unit wires **work-item create/read/update/list** only (design §6 hierarchy, §9 templates). Claim/heartbeat/pick/status/unblock/resume are REQ-292; archive, non-ticket Docs, milestone, and migration remain later path-units.

**Hard rules for every CRUD op in this path:**

1. **Rediscover, never invent** — each op begins with `search_tool` for the needed Linear surface; call `use_tool` only with a qualified name + `input_schema` from that search.
2. **Hard-stop if undiscoverable** — if Linear MCP tools are missing, unauthenticated, or the needed capability has no discovered tool, **stop** with the setup block in this file. Do not invent issues/initiatives; do not write local Issue/REQ markdown as a substitute store.
3. **No dual-write** — Linear is the sole work-item store while `backend: linear`. No parallel `.do-work/user-requests/` or `.do-work/REQ-*` as source of truth.
4. **Linear issue ids only** — REQs are identified by Linear identifiers (e.g. `ENG-123`). **No** parallel `REQ-NNN` allocation in Linear mode. `UR-NNN` remains a Project/Initiative slug only.
5. **Atomic `create_ur`** — never leave do-work Issues without a resolvable product Project + Issue Project Milestone. If milestone create fails after product Project ensure, hard-stop; do not continue intake as if the do-work Issue exists.

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| UR create/read/list sequences | product Project (`product_project`) + Issue Project Milestone (`ur_milestone_name_pattern`) | REQ-290 (this section) |
| REQ create/update/read/list | Issues in that Project; §9.2 body; path-unit `parentId` sub-issues | REQ-290 (this section) |
| Templates + append/deps/footprint ops | §9 field semantics; `append_ideate` / `append_clarifications` / `set_blocked_by` / `set_files` | REQ-291 |
| Claim / heartbeat / pick / status / unblock / resume | Optimistic claim comment protocol (§8); human assignee preserved | REQ-292 |
| Archive / non-ticket homes | Deferred → REQ-294–297 | later REQs |
| Idle markdown→Linear migration | Deferred → **REQ-300** | upgrade + this file |

---

## Path: Linear templates + append/deps/footprint (REQ-291)

| | |
|---|---|
| **Entry point** | Any phase that writes UR sections (ideate/question) or REQ deps/footprint under `tracker.backend: linear` |
| **Terminal state** | §9.1 / §9.2 templates (machine markers `<!-- do-work-ur -->` / `<!-- do-work-req -->`), labels (`Layer/*`, `Size/*`, `path-unit`), `status_map` hard-fail rules, and full agent sequences for `append_ideate`, `append_clarifications`, `set_blocked_by` (blocks relations + `**Depends on:**` mirror), and `set_files` are documented with live rediscovery |

This path-unit **extends** REQ-290 CRUD: templates become the field contract, and the remaining create/update surface for intake→capture without claim is complete.

**Hard rules (in addition to REQ-290 CRUD rules):**

1. **Machine markers are mandatory** on every Issue Project Milestone description (`<!-- do-work-ur -->`) and Linear issue description (`<!-- do-work-req -->`). Parse/stop if missing on read/update — do not invent fields.
2. **`set_blocked_by` dual-write** — when relation tools exist: native `blocks` relations **and** body `**Depends on:**` mirror in one op. Relations are authoritative for eligibility (port rule).
3. **Labels from config prefixes** — `tracker.linear.labels.layer_prefix` (default `Layer/`), `size_prefix` (default `Size/`), `path_unit` (default `path-unit`). Apply on create/update when label tools are discoverable; body headers still hold the same values for parse.
4. **`status_map` hard-fail** — every mapped workflow state name must exist on the team; missing → hard-stop (never invent a close-enough state).
5. **Prefer section append** on Initiative for ideate/clarifications; never overwrite `## Brief` verbatim intake.

---

## Path: Linear claim / status / unblock / resume (REQ-292)

| | |
|---|---|
| **Entry point** | `/do-work run` \| `status` \| `unblock` \| `resume` with `tracker.backend: linear` |
| **Terminal state** | Optimistic claim comment protocol works; status reports claimers/heartbeats; unblock/resume match markdown semantics; mid-flight failure leaves claimed |

This path-unit implements design **§8 Claim protocol** as Linear agent sequences for `list_claimable_reqs`, `claim_req`, `heartbeat_req`, `set_req_status`, `unblock_req`, plus **resume** and **status** consumers. Semantics stay in `port.md`; representation is workflow state + claim **comments** (not a local claim stamp file).

**Hard rules (in addition to prior Linear path rules):**

1. **Human assignee is sacred** — `default_assignee_id` on create; agents **never** set/clear/steal Linear **assignee** for claim, heartbeat, unblock, or resume.
2. **Claim = comment + workflow**, not assignee — `status_map.in_progress` + comment starting with `tracker.linear.agent_claim_marker` (default `<!-- do-work-claim -->`).
3. **Optimistic re-read** — every `claim_req` re-reads issue + claim comments before write; race lost → `concurrent-conflict` stop; resume allowed.
4. **Stale age** — `tracker.linear.heartbeat_max_age_seconds` when set; else `parallel.stale_threshold_seconds` (default `900`).
5. **Mid-flight MCP death** — **leave claimed** (in_progress + last active claim/heartbeat); do not auto-release. Operator uses resume or unblock after MCP recovers.
6. **No dual-write** — no local `.do-work/working/` claim stamps while `backend: linear`.
7. **Rediscover tools** — comments, issue get/update, list issues, workflow states, relations — always `search_tool` first; invent nothing.

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Claim comment protocol + claim/heartbeat/unblock/resume/status/list_claimable | Full sequences in this section | REQ-292 |
| Phase playbooks that *call* these ops | `status` / `unblock` / `resume` / `run` Linear op callouts | REQ-293 |
| `archive_req` + `append_run_note` + run commit convention | Done + proof + outputs; run notes; §6.5 commits | REQ-294 |

---

## Path: Linear run coordination (REQ-294)

| | |
|---|---|
| **Entry point** | `/do-work run` with `tracker.backend: linear` (after claim path) |
| **Terminal state** | Worker/orchestrator can pick → claim → deps/footprint checks → archive a REQ using Linear as sole work-item store; worktrees/git remain local; commit messages use Linear issue ids; mid-flight MCP failure leaves the issue claimed |

This path-unit closes the **run loop** on Linear (design phasing step 5 + §5.5 runtime split + §6.5 commits + §7 ledger note + clarification leave-claimed). Claim/pick sequences are REQ-292/293; this path adds **`archive_req`**, **`append_run_note`**, commit/PR message convention, and the ledger telemetry rule.

**Hard rules (in addition to claim-path rules):**

1. **`archive_req` is the only done transition** — set `status_map.done`, write **`Closure proof:`** + **`## Outputs`** on the Issue, release claim (`status: released`). Do **not** use bare `set_req_status` for done. Do **not** write local `.do-work/archive/REQ-*` as the work-item store.
2. **Footprint overlap** — `list_claimable_reqs` / claim eligibility compare candidate `**Files:**` against `**Files:**` parsed from Issue bodies of **in-flight claims** (workflow `in_progress` or `stopped` with active claim). Same intent as `lib/check-footprint.sh`.
3. **Deps satisfaction** — authoritative graph is native Linear **`blocks` relations**. A dep is satisfied only when that issue’s workflow maps to `status_map.done`. Body `**Depends on:**` is mirror only.
4. **Commits/PRs (§6.5)** — messages reference the Linear issue id (`feat(ENG-123): …` + `Issue:` / `UR:` / `Output:` footer). No `.do-work/archive/REQ-…` path required. Branch may be `req/ENG-123` (sanitize for git refs).
5. **`append_run_note` is authoritative** for run/cost notes in Linear mode (Issue comment, YAML fenced). When `ledger.enabled: true`, orchestrator **may also** write local `.do-work/runs/RUN-NNN.yml` — **telemetry only**, not a second work-item store. Retro prefers Linear run notes; falls back to local runs if comments unavailable.
6. **Mid-flight MCP failure after claim** — **leave claimed** (active claim comment + `in_progress`); worker/orchestrator **stops** for resume/unblock. **Never** silent-release. **Never** fall back to markdown store.
7. **Runtime stays local** — worktrees, merges, PRs, `state/*` locks, events, config.yml unchanged (§5.5).

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| `archive_req` + `append_run_note` sequences + §6.5 + ledger telemetry rule | Documented in this file; run/run-worker callouts | REQ-294 (this section) |
| Deeper pick ordering / review-gate / branch sanitize wiring | Further run-agent refinements | REQ-295 |

---

## Path: Linear run pick ordering / footprint / review-gate / branch sanitize (REQ-295)

| | |
|---|---|
| **Entry point** | `/do-work run` with `tracker.backend: linear` after REQ-294 archive/notes/commits path |
| **Terminal state** | `list_claimable_reqs` has deterministic pick order + skip reasons + footprint algorithm parity; `archive_req` / `append_run_note` stay the only Linear archive/note ops; worktree branches use `req/<linear-id>` (sanitized); review gate still blocks archive when `review.required`; failed review/evidence never calls `archive_req`; claim loss → `concurrent-conflict` with resume; **no** Linear-aware bash in `lib/` for v1 |

This path-unit **refines** the REQ-294 run loop for production pick/integrate edge cases. It does **not** re-open claim protocol (REQ-292) or invent new port op names.

**Hard rules (REQ-295):**

1. **Pick order is deterministic** — Priority **descending** (3 most urgent before 1; missing/malformed defaults to **2**), then created_at ascending, then Linear identifier ascending. First survivor wins (parity with `lib/pick-req.sh` priority + first-survivor model).
2. **Skip reasons are emitted** for every rejected candidate (`dep:`, `overlap:`, `scope:`, `claim:`) so the run loop can map to `overlap-blocked` / `deps-blocked` / `scope-blocked` / `truly-empty` without calling `pick-req.sh`.
3. **Footprint algorithm** matches `lib/check-footprint.sh` intent: parse `**Files:**`, treat empty/missing as free (no overlap), expand globs with nullglob semantics (unmatched globs do not collide), compare expanded path sets against in-flight claims only.
4. **Review gate before archive** — when `review.required: true` (config default), orchestrator must pass post-build review **before** calling `archive_req`. Failed review or failed acceptance-evidence gate **must not** call `archive_req`; issue stays `in_progress`/`stopped` with claim protocol intact.
5. **Branch sanitize** — worktree branch may be `req/<linear-id>` after sanitizing for git ref rules (see **Branch sanitize** below). Worktree directory mirrors the sanitized slug under `.worktrees/`.
6. **Concurrent claim loss** — same stopper as markdown multi-agent: `concurrent-conflict`; `/do-work resume` allowed when the claim is still held by the owner. Never invent a different stopper enum value.
7. **No Linear-aware bash in `lib/` for v1** — pick/claim/deps/footprint/heartbeat/archive-integrity **semantics** for Linear live as agent sequences in this file (MCP). `lib/*.sh` remain markdown-backend implementations. Runtime helpers that are backend-agnostic (`provision-worktree.sh`, local locks, optional local ledger telemetry) stay local and do **not** call Linear APIs.

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Deeper `list_claimable_reqs` order + skip reasons + footprint algorithm | This file | REQ-295 (this section) |
| Review-gate / failed-gate → no `archive_req`; branch sanitize wiring | `agents/run.md`, `agents/run-worker.md`, `agents/review.md` + this file | REQ-295 |
| `archive_req` + `append_run_note` (YAML-fenced Issue comment) | Remain as REQ-294 sequences; preconditions tightened here | REQ-294/295 |

---

## Path: Linear non-ticket artifacts (REQ-296)

| | |
|---|---|
| **Entry point** | capture `append_decision`; verify/close write reports; retro calibration; run notes; gate coordination — with `tracker.backend: linear` |
| **Terminal state** | Artifacts live **only** in fixed Linear homes (design §10); agents never invent ad-hoc locations; gate locks stay local `state/*` |

This path-unit maps **non-ticket** work-item artifacts to Linear homes and documents write/read sequences. Ticket lifecycle (Issue/REQ/claim/archive) is prior path-units; this path freezes **where** decisions, calibration, verify, close, and run notes live.

**Hard rules (REQ-296):**

1. **Fixed homes only** — use the §10 table below. Do **not** invent alternate Docs titles, Initiative sections, comment markers, or local markdown dual-stores for these artifacts while `backend: linear`.
2. **Decisions + calibration = Team Docs** — titles from config: `tracker.linear.decisions_doc_title` (default `do-work/decisions`) and `tracker.linear.calibration_doc_title` (default `do-work/calibration`). **Create-if-missing** when Docs tools are discoverable.
3. **Verify / close = Issue Project Milestone** — `write_verify_report` → milestone description `## Verify` (+ comment with full report). `write_close_report` → milestone `## Closure` (+ comment). Prefer description section update; fall back to comment-only if size limits require it.
4. **Run notes = Issue comments** — `append_run_note` (REQ-294) remains authoritative; optional Project update is non-authoritative rollup only.
5. **Gate locks stay local** — `write_gate_state` writes/deletes `{project}/.do-work/state/gate-owner.md` (and final-suite locks under `state/*`). **Never** put gate ownership in Linear.
6. **No dual-write** — do not also write `.do-work/decisions.md`, `state/calibration.md`, or `user-requests/UR-NNN/closure.md` as the work-item store when `backend: linear`. Optional local ledger telemetry for run notes only when `ledger.enabled` (REQ-294).
7. **Rediscover Docs tools** — Team Docs are unproven until live MCP marks them available; each op still begins with `search_tool`. Missing Docs/milestone tools → hard-stop for that op (never invent a local substitute store).

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| §10 home map + `append_decision` / calibration Doc / `write_verify_report` / `write_close_report` / `write_gate_state` sequences | This file | REQ-296 (this section) |
| Phase agents call those homes | `agents/capture.md`, `agents/verify.md`, `agents/close.md`, `agents/retro.md` | REQ-296 |
| Full consumer wiring + hard-stop invent ban + close Linear path-unit walk + retro prefer run notes | This file + capture/ideate/question/verify/close/retro/run-worker | REQ-297 |
| `append_run_note` Issue comments | Remain as REQ-294 sequences | REQ-294 |

---

## Path: Linear artifact home consumers (REQ-297)

| | |
|---|---|
| **Entry point** | capture / ideate / question / verify / close / retro / run-worker after load path with `tracker.backend: linear` |
| **Terminal state** | All §10 readers and writers use port sequences in this file; Doc titles from config; decisions one-line grammar identical to markdown; close walks **Linear issue ids**; retro prefers Linear run notes; create/update failures hard-stop with **no invented homes** |

REQ-296 documented the homes and write sequences. **REQ-297** finishes the consumer surface:

| Consumer | Linear port ops / helpers (this file) |
|----------|----------------------------------------|
| `agents/capture.md` | **Read decisions**; **`append_decision`**; **Read calibration Doc** |
| `agents/ideate.md` | **Read decisions** (constraints for Connector / contradiction flags) |
| `agents/question.md` | **Read decisions** (self-answer pass evidence) |
| `agents/run-worker.md` | **Read decisions** (standing constraints; conflict → stop) |
| `agents/verify.md` | **`write_verify_report`** (and `read_ur` / `list_reqs_for_ur` for brief + REQs) |
| `agents/close.md` | Path-unit walk via **Linear issue ids** + **`write_close_report`** |
| `agents/retro.md` | **List run notes** (prefer) → local `RUN-NNN.yml` fallback; **Write calibration Doc** |

**Hard rules (REQ-297):**

1. **Config titles only** — decisions Doc = `tracker.linear.decisions_doc_title` (default `do-work/decisions`); calibration Doc = `tracker.linear.calibration_doc_title` (default `do-work/calibration`). Never invent alternate titles.
2. **Same decisions grammar as markdown** — every line is exactly `YYYY-MM-DD | Issue/REQ ref | decision | rationale` (SKILL.md § Decisions Memory). Linear issue ids may appear in the ref slot (e.g. `ENG-123`); pipe-separated four fields; one line per decision; append-only; supersede by new line.
3. **Close walks Linear issue ids** — under `backend: linear`, path-units are Issues in Project `do-work/{UR-id}` with path-unit semantics (`Layer: none` + non-empty Entry point + Terminal state). The `req` field in closure rows is the **Linear identifier** (e.g. `ENG-123`), not `REQ-NNN`.
4. **Retro prefers Linear run notes** — when `backend: linear`, collect `<!-- do-work-run-note -->` Issue comments via **List run notes** before treating local `.do-work/runs/` as the only history. Fall back to local telemetry only when comments are unavailable.
5. **Hard-stop on Doc / Initiative write failure — no invent** — if Team Doc **create** or **update** fails (permission, size, MCP error), or Issue Project Milestone description section update **and** milestone comment both fail for verify/close, **hard-stop**. Agents must **not** invent ad-hoc Linear issue comments for decisions/calibration, alternate Doc titles, local `.do-work/decisions.md` / `state/calibration.md` / `closure.md` as substitute stores, or any home outside the §10 table.
6. **§10-allowed spill only** — for verify/close, putting the full report in a **Issue Project Milestone comment** while leaving a one-line pointer under `## Verify` / `## Closure` is the documented size path (still §10). That is **not** inventing a home. Putting the report on a random Linear issue, a different milestone, or a new Doc title **is** inventing — forbidden.

---

## Path: Linear milestone mode (REQ-298)

| | |
|---|---|
| **Entry point** | Milestone-shaped UR (`source: /saas-thesis handoff` + `### Milestones`) with `tracker.backend: linear` — capture, run claim loop, deploy gate |
| **Terminal state** | Active milestone cursor lives on **Project description** `<!-- do-work-milestone -->`; `list_milestone_reqs` / `set_active_milestone` / `read_active_milestone` work via this file; deploy gate remains **local** `state/gate-owner.md` with human y/n; **trigger shape unchanged** |

This path-unit implements design **§11 Milestone mode (Linear)**. Trigger and gate ownership match markdown; only the **cursor store** and **REQ listing** move to Linear.

**Hard rules (REQ-298):**

1. **Trigger unchanged** — Milestone mode activates only when the Issue brief has **both** (a) `source: /saas-thesis handoff` and (b) a `### Milestones` heading with at least one `#### M1` (or higher) subheading. Same as markdown capture Step 1b. Do **not** invent a Linear-only trigger.
2. **Cursor home = Issue Project Milestone description** — machine block starting with `<!-- do-work-milestone -->` on the do-work Issue’s Project Milestone (shared product Project). **Not** local `state/active-milestone.md` as the work-item store under Linear. **Not** Initiative description. **Not** Team Docs.
3. **Checklist lives with the cursor** — active id + full milestone checklist (parity with markdown `active-milestone.md` + `milestones.md`) inside that Project description block.
4. **Deploy gate stays local** — first orchestrator claims via **`write_gate_state`** → `{project}/.do-work/state/gate-owner.md`; human y/n; siblings idle-wait on gate-owner + cursor changes via **`read_active_milestone`**. **Never** put gate ownership in Linear.
5. **Issue membership** — REQs for a milestone are Issues in the Issue Project, filterable by milestone marker: prefer Linear Project milestone entity when MCP tools support it after live rediscovery; else **label** equal to the milestone id (e.g. `M1`) and/or body header `**Milestone:** M1`. `list_milestone_reqs` uses those markers.
6. **No dual-write** — do not treat local `active-milestone.md` / `milestones.md` as authoritative while `backend: linear`. Local files remain allowed only for **gate locks** (`gate-owner.md`, final-suite locks).
7. **Rediscover Project tools** — every cursor read/write begins with `search_tool` for Project get/update. Missing tools → hard-stop (never invent a local cursor substitute store).

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Path narrative + trigger/cursor home/gate locality hard rules | This file (above) | REQ-298 |
| `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` full sequences + marker parse + empty→null | This file | **REQ-299** |
| Capture Linear branches call port ops after decompose | `agents/capture.md` | REQ-298 path; **REQ-299** ops |
| Run filter / idle-wait / deploy-gate drain call port ops; local gate-owner serialize | `agents/run.md` | REQ-298 path; **REQ-299** ops |
| `write_gate_state` (local-only + concurrent serialize) | This file + run.md | REQ-296 home; **REQ-299** concurrent rules |

---

## Path: Linear milestone cursor ops (REQ-299)

| | |
|---|---|
| **Entry point** | Capture milestone decompose; run Step 1.0 / 1.0a / 7b under `tracker.backend: linear` |
| **Terminal state** | Milestone cursor ops complete: marker format documented + parsed; empty marker → `active: null` (does **not** invent a milestone id); siblings idle on deploy gate same as markdown; concurrent gate ownership serializes via **local** `state/gate-owner.md`; `write_gate_state` remains local-allowed; capture/run call port ops only |

REQ-298 documented the §11 path (trigger, cursor home, local gate). **REQ-299** finishes the **port op surface** and acceptance rules:

| Op / rule | Where | Notes |
|-----------|-------|--------|
| Marker format + parse algorithm | This file — **Project description cursor block** + **Parse algorithm** | `<!-- do-work-milestone -->` + `**Active:**` + `# Milestones` checklist |
| `read_active_milestone` | This file | Empty / missing marker → `active: null`; **does not invent a milestone id** |
| `set_active_milestone` | This file | Set / advance / clear on Project description only |
| `list_milestone_reqs` | This file | Filter by do-work Linear-issue path-milestone markers; no widen to other M |
| Sibling idle on deploy gate | `agents/run.md` Step 1.0a | Same idle loop as markdown; Linear polls `read_active_milestone` + **local** `gate-owner.md` |
| Concurrent gate ownership | `write_gate_state` (this file) + run Step 7b.2 | Serializes via **local** `state/gate-owner.md` even when cursor content is remote |
| Capture / run Linear branches | `agents/capture.md`, `agents/run.md` | Call port ops; never treat local `active-milestone.md` as Linear store |

**Hard rules (REQ-299):**

1. **Marker format is authoritative** — Project description machine block must start with `<!-- do-work-milestone -->` then `**Active:**` then `# Milestones` checklist (see block template below). Parse only that format; do not invent alternate markers (YAML frontmatter, Initiative fields, Team Docs).
2. **Empty marker → null active (does not invent a milestone id)** — when the Project description has **no** `<!-- do-work-milestone -->` marker, or the block is present but `**Active:**` is empty / `none` / missing, `read_active_milestone` returns `active: null` (not-in-milestone / not-active). It **must not** invent `M1` or any other id on read. Capture may *choose* `M1` as first-decompose default **after** observing null — that default is capture policy, not a return value of `read_active_milestone`.
3. **`write_gate_state` remains local-allowed** — gate ownership and final-suite locks stay under `{project}/.do-work/state/` (design §5.5 / §10 / §11). Never Linear Issues as gate locks; never Team Docs for gate ownership. Not dual-write of work items.
4. **Concurrent gate ownership serializes via local `gate-owner.md`** — even when milestone **cursor** content is remote (Project description), gate ownership is **only** the local file. First successful claim (absent→write own `AGENT_ID`, re-read confirms self) owns the human y/n prompt; losers idle on Step 1.0a. Do **not** invent a Linear lock or Project-description gate field.
5. **Siblings idle same as markdown** — empty active-M backlog + foreign `gate-owner.md` → idle-wait; wake on cursor advance (`set_active_milestone` / `read_active_milestone`) or cursor clear + gate release. Poll interval and 30-minute stuck prompt parity with markdown Step 1.0a.
6. **Capture and run call port ops** — Linear milestone branches must use `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` / `write_gate_state` from this file; no silent markdown cursor fallback.

---

## Path: Idle markdown→Linear migration (REQ-300 path + REQ-301 upgrade wiring)

| | |
|---|---|
| **Entry point** | `/do-work upgrade migrate` (or upgrade **Step 9** migrate path) when the project still uses the **markdown** work-item store and wants a one-shot cutover to Linear — design §12 |
| **Terminal state** | All Issues/REQs from markdown backlog + archive exist in Linear (product Project + Issue Project Milestones / Issues on those milestones); Team Docs for decisions (+ empty calibration if missing); `tracker.backend: linear` + resolved team ids written to config; local `user-requests/` + `archive/` (and backlog REQ files) left as **read-only historical** trees; **post-cutover work-item ops ignore historical markdown trees**; **no dual-write**; dry-run lists planned creates without write; re-run when already linear **refuses without rewriting Linear issues** |

This path-unit implements design **§12 Migration (markdown → Linear)**. It is **idle-only**, **operator-confirmed** (destructive apply gate) or **dry-run**, and **all-or-nothing** on preflight / MCP failure (no partial cutover).

**Hard rules (REQ-300 + REQ-301):**

1. **Preflight is absolute** — migration runs only when **all** of:
   - `{project}/.do-work/working/` has **zero** `REQ-*.md` files (empty of in-flight work).
   - **No active claims** (no claim stamps with live heartbeats in working/ — redundant if working empty; still verify no stranded claim protocol elsewhere the agent knows about for markdown).
   - Effective `tracker.backend` is still **`markdown`** (or unset → markdown).
   - Operator **confirms** cutover via the **destructive/confirm gate** **or** the invocation is **dry-run** (report only).
2. **Already linear → refuse without rewriting Linear issues (idempotent refuse, REQ-301)** — if effective `tracker.backend` is already **`linear`**, report **already-migrated / `already-linear`** and **stop**. **Do not** create, update, rewrite, or re-sync Linear Issues (or product Project milestones / Docs from historical markdown). **Do not** re-run M2–M6 write phases. Config left unchanged. Re-running migrate after cutover is therefore safe: clear refuse, zero remote writes.
3. **Refuse entirely on failed preflight** — if `working/` is non-empty **or** active claims exist, **refuse the whole migration**. Do **not** create any Linear entities. Do **not** change `tracker.backend`. Config and markdown trees left unchanged. Message: idle required; finish or unblock in-flight work first.
4. **Hard-stop on unusable Linear MCP** — before any write (and if MCP dies mid-migration), **hard-stop** with Linear skill setup instructions. Leave markdown trees **and** `tracker.backend` **unchanged**. **No partial cutover** (do not flip config after only some Issues/REQs landed; do not dual-write). Prefer operator cleanup of any orphan Linear entities created mid-flight only when a write phase already started — document orphans in the stop report; never flip backend mid-orphan.
5. **No dual-write after cutover + ignore historical trees (REQ-301)** — once `tracker.backend: linear` is set, work-item ops use **only** this file. Local `.do-work/user-requests/`, backlog `REQ-*.md`, and `archive/` become **historical read-only** (do not delete). **Post-cutover work-item ops must ignore historical markdown trees** — never list/read/parse them as the work-item store (no silent fallthrough to markdown paths). Runtime/git/`state/*` stay local.
6. **Dry-run** — when flag/mode is dry-run: run preflight + inventory + **planned-create list** (Initiatives / Projects / Issues / Docs / config flip); **zero** Linear writes; **zero** config changes. Exit after the report.
7. **Destructive confirm for apply** — apply mode requires affirmative operator confirmation (upgrade Step 9b). Without confirm and without dry-run → refuse (no write).
8. **Rediscover tools** — every Linear create/list uses `search_tool` → `use_tool` with live schemas. Never invent tool names. Missing create tools → hard-stop (same as CRUD preflight).
9. **Map, do not invent** — preserve UR ids, REQ task text, AC checkboxes, deps, parents, status (backlog vs done), closure proof / outputs when present. Linear REQs get **Linear issue ids** only after create (markdown `REQ-NNN` may be noted in body for historical trace, not as the Linear identifier).

**Surfacing (upgrade / conformance — REQ-301 wiring):**

| Surface | Role |
|---------|------|
| `agents/upgrade.md` Step **9** / `/do-work upgrade migrate` | Operator-facing UX: preflight, **destructive confirm** or dry-run, invoke this sequence, report; already-linear refuse |
| `lib/conformance-scan.sh` | Documents that `migrate-linear` is **not** a drift row; historical trees after cutover are not drift; never auto-flags markdown backend |
| Port op `migrate_markdown_to_linear` | Shared contract (preconditions, refuse / hard-stop, dry-run) — `agents/tracker/port.md` |
| This section | Full agent sequence + status/relation/parent mapping + post-cutover ignore rules |

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Path narrative + hard rules + agent sequence | This file | **REQ-300** |
| Port op contract + shared refuse/hard-stop rules | `agents/tracker/port.md` | **REQ-300** |
| Upgrade migrate step + dry-run flag UX (initial) | `agents/upgrade.md` | **REQ-300** |
| Upgrade/conformance wiring: destructive confirm, dry-run list, already-linear no-rewrite, post-cutover ignore, scan header | `agents/upgrade.md`, `lib/conformance-scan.sh`, this file | **REQ-301** |

---

### `migrate_markdown_to_linear` (agent sequence)

| | |
|---|---|
| **Intent** | One-shot idle markdown → Linear cutover (design §12). |
| **Preconditions** | See hard rules. Team id/key intended for Linear must be known (config `tracker.linear.team_id` / `team_key` or operator-supplied before write). |
| **Modes** | `dry-run` (report planned creates only) \| `apply` (writes + config flip after full success; requires destructive confirm). |
| **Does not** | Delete markdown trees; dual-write after cutover; migrate mid-flight working/ REQs; flip config on partial failure; rewrite Issues when already linear. |

#### Step M0 — Invocation flags

| Flag | Meaning |
|------|---------|
| `--dry-run` / dry-run mode | Inventory + **list planned creates** only; no Linear write; no config write |
| apply (default when operator confirmed) | Full sequence after **destructive confirm**; config flip only at M6 after successful creates |

Upgrade agent passes the mode after confirm / dry-run selection (`agents/upgrade.md` Step 9).

#### Step M1 — Preflight (refuse = entire abort)

1. Resolve `{project}` (`git rev-parse --show-toplevel` or CWD).
2. Load config (`agents/config.md`). Effective backend must be **`markdown`**. If effective backend is **`linear`**, **refuse** with already-migrated / `already-linear`:
   - **Do not re-run production migration.**
   - **Do not create, update, or rewrite Linear Issues** (nor Initiatives / Projects / Docs from historical markdown).
   - **Do not** proceed to M2–M6.
   - Config and Linear store unchanged. This is the **idempotent re-run** path.
3. **Working empty:**
   ```bash
   # Non-zero count → refuse
   find "{project}/.do-work/working" -maxdepth 1 -name 'REQ-*.md' 2>/dev/null | wc -l
   ```
   Any `REQ-*.md` in `working/` → **refuse entirely** (message: drain or unblock working/ first). Config unchanged.
4. **No active claims:** with working empty of REQ files, markdown claims are absent. If any claim stamp protocol file is found outside the empty working/ contract, treat as refuse (do not invent partial cleanup).
5. **Linear readiness (write modes and dry-run):**
   - `search_tool "linear"` (or `"linear team"`) — must return Linear MCP tools. Zero tools → **hard-stop** with setup block (same as this file's **Hard-stop** section). **Config backend left markdown.** Markdown trees unchanged.
   - Resolve team via `tracker.linear.team_id` and/or `team_key`. Unresolved → **hard-stop** (do not guess). Config unchanged.
   - Validate every `status_map` state exists on the team workflow. Missing → **hard-stop** with rename/override instructions. Config unchanged.
6. **Destructive/confirm gate** (apply mode only): upgrade agent must have an affirmative confirm (`AskUserQuestion` or equivalent). Without confirm and without dry-run → **refuse** (do not write). Dry-run does not require this gate.
7. On any refuse/hard-stop in M1: **stop**. No Linear creates. No config edit.

#### Step M2 — Inventory (read markdown store only)

Build a plan from the **markdown** store (allowed because backend is still markdown):

| Source | Collect |
|--------|---------|
| `{project}/.do-work/user-requests/UR-*/` | Each `UR-NNN`: `input.md` brief, ideate, clarifications, verify/close artifacts if present |
| `{project}/.do-work/REQ-*.md` (backlog root) | Open REQs (not working, not archive) |
| `{project}/.do-work/archive/REQ-*.md` | Done REQs |
| `{project}/.do-work/decisions.md` | Standing decision lines (if present) |
| `{project}/.do-work/state/calibration.md` | Calibration body (if present) — else plan empty calibration Doc |

For each REQ file parse: `**UR:**`, `**Status:**`, `**Parent:**`, `**Depends on:**`, `**Files:**`, `**Layer:**`, `**Entry point:**` / `**Terminal state:**` (path-unit), `## Task`, `## Acceptance Criteria` (preserve `- [ ]` / `- [x]`), `## Verification Steps`, `## Outputs`, `**Closure proof:**`, size/priority/criteria-approved headers.

Group REQs by UR. Skip any REQ whose UR directory is missing only after recording a plan warning (still attempt create under that Issue slug if inventable from REQ header).

**In-flight forbidden:** working/ was empty at M1 — do not invent migration of in-progress slots.

#### Step M3 — Dry-run report (always build; exit here if dry-run)

Emit a planned-create report, for example:

```text
markdown→Linear migration plan (dry-run|apply)
Team: <team_id or key>
backend after cutover: linear

Team Docs:
  - create-or-update: do-work/decisions (N lines from decisions.md | empty)
  - create-if-missing: do-work/calibration (body | empty stub)

Issues (Initiatives + Projects):
  - UR-007: Initiative title "…" + Project do-work/UR-007 + link
  - …

REQs (Issues):
  - REQ-100 → Project do-work/UR-007 | status=done | parent=none | deps=REQ-99
  - REQ-101 → Project do-work/UR-007 | status=backlog | parent=REQ-100 (path-unit child)
  - …

Config flip (apply only): tracker.backend: linear; team_id: …
Post-cutover: user-requests/ + archive/ + backlog REQ-*.md remain on disk as historical read-only; ops stop reading them as store.
```

If mode is **dry-run**: **stop here**. Zero Linear writes. Zero config changes. Return report to operator.

#### Step M4 — Team Docs (apply only)

1. Rediscover Team Docs tools (`search_tool`).
2. **Decisions** — title `tracker.linear.decisions_doc_title` (default `do-work/decisions`). Find or create-if-missing. If local `decisions.md` has lines, write them into the Doc body (preserve one-line grammar). If local empty/missing, create empty/header Doc.
3. **Calibration** — title `tracker.linear.calibration_doc_title` (default `do-work/calibration`). Create-if-missing; if local `state/calibration.md` exists, full-replace Doc body with it; else empty stub.
4. Failure (permission/MCP) → **hard-stop**. Do **not** flip `tracker.backend`. Prefer not to continue Issues if Docs failed at the start; if any Doc was created, list it in the stop report for operator cleanup. **No partial cutover of config.**

#### Step M5 — Issues then REQs (apply only)

For each inventoried UR (stable order: ascending `UR-NNN`):

1. **Create do-work Issue Project Milestone** — name from `ur_milestone_name_pattern` / brief title; description = §9.1 template filled from `input.md` + ideate + clarifications + verify/closure when present (`<!-- do-work-ur -->`, `**UR-id:** UR-NNN`, `**Product-project:**` from config).
2. **Ensure product Project** (`product_project`, default `do-work`) on the resolved team.
3. **Attach** nothing else for Issue create — Linear issues (REQs) later attach to the do-work Issue Project Milestone. Record product project id + milestone id on the §9.1 body.
4. Atomicity: same as `create_ur` — no partial UR without product Project + milestone. Failure → **hard-stop**; list created entity ids for cleanup; **do not flip config**.

Then for each REQ belonging to that Issue (parents before children; backlog + archive):

5. **Map status** via `status_map`:
   - archive / `**Status:** done` → `status_map.done` (default `"Done"`)
   - backlog / open / missing done → `status_map.backlog` (default `"Todo"`)
   - **Never** migrate as `in_progress` (preflight forbids working/). If a file claims stopped in archive-like state, map to `status_map.done` only when archive path or explicit done; otherwise backlog or stopped map per `**Status:**` (`stopped` → `status_map.stopped`).
6. **Build Issue body** from §9.2: copy headers/sections; preserve AC checkboxes literally. Optional historical line: `**Migrated-from:** REQ-NNN` (display only; **not** the Linear id).
7. **Create Issue** in the Issue Project with mapped workflow state; labels Layer/Size/path-unit when tools exist; assignee from `default_assignee_id` when set.
8. **Parents / path-units:** if `**Parent:** REQ-X` (markdown id), resolve to the Linear issue id created earlier in this run for that markdown id (maintain a `REQ-NNN → ENG-…` map). Set Linear `parentId` + body `**Parent:** ENG-…`. Create path-unit parents before children.
9. **Deps:** after all Issues for the Issue (or globally once all Issues exist), for each REQ with `**Depends on:**`, map markdown ids through the same map and run **`set_blocked_by`** dual-write (native `blocks` + body mirror) using **Linear** ids. If relation tools missing → body-only + one-time warning (port rule).
10. Mid-sequence MCP failure → **hard-stop**. Do **not** set `tracker.backend: linear`. Report orphan milestone/Issue ids. Markdown trees unchanged. Operator may clean Linear side and re-run after idle preflight (re-run should be safe to plan; apply may create duplicates if orphans left — operator cleans first).

#### Step M6 — Config flip (apply only; only after M4–M5 full success)

Write `{project}/.do-work/config.yml`:

- `tracker.backend: linear`
- `tracker.linear.team_id` / `team_key` as resolved (persist the id used)
- Leave other `tracker.linear.*` keys as already migrated defaults

**Only after** this write is the cutover complete. Until then, effective backend remains markdown.

If config write fails after Linear creates succeeded: **hard-stop** with: Linear entities exist; config still markdown; operator must set `tracker.backend: linear` manually **or** delete Linear orphans and retry. Do not dual-write; do not invent a half-mode.

#### Step M7 — Post-cutover (historical trees; ops ignore them)

1. **Do not delete** `.do-work/user-requests/`, `.do-work/archive/`, backlog `REQ-*.md`, or `decisions.md`.
2. Treat them as **read-only historical**. Phase agents with `backend: linear` **must ignore historical markdown trees** as the work-item store:
   - **Forbidden as store** after cutover: reading/listing/parsing `.do-work/user-requests/`, `.do-work/REQ-*.md` (backlog root), `.do-work/archive/REQ-*.md`, local `decisions.md` / `state/calibration.md` as authoritative work-item data.
   - **Required store:** Linear only via named port ops in this file (load path → `port.md` + this file).
   - Historical trees may remain on disk for human audit; agents never dual-read them “for safety.”
3. Runtime locals unchanged: worktrees, `state/*` locks, events, gate-owner, optional ledger telemetry.
4. Report success: counts created, id map summary (`REQ-NNN → Linear id`), config backend now linear, pointer to Linear skill if further setup needed.
5. **Re-run after cutover:** M1 step 2 refuses with already-linear — **without rewriting Linear issues**.

#### Failure matrix (no partial cutover)

| Failure | Behavior |
|---------|----------|
| Already `tracker.backend: linear` | **Refuse** `already-linear` / already-migrated — **no Issue rewrites**; config unchanged |
| `working/` non-empty or active claims | **Refuse entirely** — no Linear writes; config unchanged |
| Operator declines confirm (apply) | **Refuse** — no writes |
| Linear MCP missing / unauthenticated / team unresolved / status_map missing | **Hard-stop** with setup instructions — markdown trees + config unchanged |
| MCP dies during M4–M5 | **Hard-stop** — config **not** flipped; list orphans; markdown unchanged |
| Config write fails after creates | **Hard-stop** — report manual flip or orphan cleanup; no dual-write mode |
| Dry-run | **List planned creates** only — always safe; zero writes |

#### Mapping summary

| Markdown | Linear |
|----------|--------|
| `user-requests/UR-NNN/` + brief | do-work Issue Project Milestone (`<!-- do-work-ur -->`) on product Project |
| Backlog `REQ-*.md` | Issue in Project; state `status_map.backlog` |
| `archive/REQ-*.md` | Issue in Project; state `status_map.done` (+ closure/outputs in body) |
| `**Parent:** REQ-X` | `parentId` + `**Parent:** <Linear id>` after id map |
| `**Depends on:** REQ-A REQ-B` | `blocks` relations + body mirror with Linear ids |
| AC `- [ ]` / `- [x]` | Same checkbox markdown in Issue description |
| `decisions.md` | Team Doc `do-work/decisions` (or config title) |
| `state/calibration.md` | Team Doc `do-work/calibration` (or config title); empty if missing |
| `tracker.backend` after success | `linear` + team ids |

---

## Path: Linear claim phase-agent wiring (REQ-293)

| | |
|---|---|
| **Entry point** | `/do-work status` \| `unblock` \| `resume` \| `run` after load path with `tracker.backend: linear` |
| **Terminal state** | Those phase agents call **only** the named port ops in this file for claim/pick/status/unblock/resume (no `.do-work/working/` claim stamps, no `pick-req.sh` / `claim-req.sh` / `synth-status.sh` as the work-item store) |

REQ-292 documents the op sequences. **REQ-293** wires the consumers:

| Phase agent | Linear port ops / sections (this file) |
|-------------|----------------------------------------|
| `agents/status.md` | **Status reporting (claimers / heartbeats)**; Helper: read active claim; optional `list_reqs_for_ur` scope |
| `agents/unblock.md` | **`unblock_req`** (release claim + backlog state); git partial-commit judgment stays local |
| `agents/resume.md` | **Resume** (compose `set_req_status` + `heartbeat_req`); worktree/branch stay local |
| `agents/run.md` | **`list_claimable_reqs`** → **`claim_req`**; **`archive_req`** + **`append_run_note`**; worker **`heartbeat_req`** checkpoints; mid-flight **leave claimed**; §6.5 commits |
| `agents/run-worker.md` | §6.5 commit/PR format; mid-flight **leave claimed**; Linear **`heartbeat_req`** when issue-id claim |

**Hard rules for wired consumers:**

1. Resolve backend first (load path). **Markdown** keeps existing `lib/*.sh` + file steps. **Linear** uses this file only for work-item claim/status/unblock/resume/pick/**archive/run notes**.
2. REQ identifiers under Linear are **Linear issue ids** (e.g. `ENG-123`), not `REQ-NNN` paths under `.do-work/`.
3. Human **assignee** is never stolen. Claim is comment + workflow.
4. Mid-flight MCP failure after `claim_req`: **leave claimed**; operator uses resume or unblock (port rule). Never silent-release; never markdown fallback.
5. Run loop (REQ-294): deps via **blocks**; footprint via Issue `**Files:**` of in-flight claims; archive via **`archive_req`**; commits use Linear issue ids.

---



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
| **Project Milestones** (UR) | `create_ur`, `read_ur`, `list_urs`, verify/close homes | unknown | — | REQ-289: **unproven** (MCP missing); hierarchy = Milestone-as-Issue on `product_project` |
| **Product Project** (`product_project`) | Shared container; Linear issues scoped by do-work Issue milestone | unknown | — | REQ-289: unproven |
| **Issue Project Milestone attach** | Issues attached to do-work Issue milestone on product Project | unknown | — | No Initiative create; MCP has no Initiative create tools |
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
| `create_ur` / `read_ur` / `list_urs` | Product Project + Project Milestones | **Documented** (REQ-290) — live `search_tool` required; hard-stop if undiscoverable |
| `append_ideate` / `append_clarifications` | Issue Project Milestone (description/comments) | **Documented** (REQ-291) — section append under §9.1; rediscover update tools |
| `create_req` / `update_req` / `read_req` | Issues, Projects, labels, statuses | **Documented** (REQ-290) |
| `list_reqs_for_ur` | Issues by Project | **Documented** (REQ-290) |
| `list_claimable_reqs` | Issues + relations + comments + statuses | **Documented** (REQ-292/294/295) — Priority DESC (missing→2) → created_at ASC → id ASC; skip reasons; deps via **blocks**; footprint algorithm; no claim side-effect |
| `claim_req` / `heartbeat_req` / `unblock_req` | Issues status + comments | **Documented** (REQ-292) — optimistic claim comment protocol |
| `set_req_status` | Workflow states, issues | **Documented** (REQ-292) — stopped / in-progress without archive or unclaim |
| `archive_req` | Workflow states, issues, claim release, body proof/outputs | **Documented** (REQ-294/295) — done + proof + outputs + claim released; **not** called after failed review/evidence |
| `set_blocked_by` | Issue relations `blocks` (+ body mirror) | **Documented** (REQ-291) — dual-write; if relations **missing** → body-only + one-time warning (port rule) |
| `set_files` | Issue description headers | **Documented** (REQ-291) — updates `**Files:**` only; no claim side-effect |
| `append_decision` | Team Doc `decisions_doc_title` | **Documented** (REQ-296 ops; REQ-297 consumers) — create-if-missing; same one-line grammar; hard-stop on create/update fail |
| Calibration (retro write / capture read) | Team Doc `calibration_doc_title` | **Documented** (REQ-296/297) — create-if-missing; full replace body; hard-stop invent ban |
| `write_verify_report` | Issue Project Milestone `## Verify` + milestone comment | **Documented** (REQ-296/297) — dual-fail hard-stop |
| `write_close_report` | Issue Project Milestone `## Closure` + milestone comment | **Documented** (REQ-296/297) — close path-unit walk uses Linear issue ids |
| `append_run_note` | Issue comments (+ optional project update) | **Documented** (REQ-294) — authoritative run/cost notes; local ledger optional telemetry |
| List run notes (helper) | Issue comments `<!-- do-work-run-note -->` | **Documented** (REQ-297) — retro prefers Linear notes, falls back to local telemetry |
| `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` | Issue Project Milestone description `<!-- do-work-milestone -->` + Linear-issue path-milestone markers (M1/M2) | **Documented** (REQ-298 path; **REQ-299** ops) — empty marker → null; does not invent milestone id |
| `write_gate_state` | **Local** `state/gate-owner.md` (not Linear) | **Documented** (REQ-296 home; **REQ-299** concurrent serialize) — local only; never Linear |

---


