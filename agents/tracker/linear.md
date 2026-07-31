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

This path-unit wires **work-item create/read/update/list** only (design §6 hierarchy, §9 templates). Claim/heartbeat/pick/status/unblock/resume are REQ-292; archive, non-ticket Docs, milestone, and migration remain later path-units.

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

1. **Machine markers are mandatory** on every Initiative description (`<!-- do-work-ur -->`) and Issue description (`<!-- do-work-req -->`). Parse/stop if missing on read/update — do not invent fields.
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

This path-unit maps **non-ticket** work-item artifacts to Linear homes and documents write/read sequences. Ticket lifecycle (UR/REQ/claim/archive) is prior path-units; this path freezes **where** decisions, calibration, verify, close, and run notes live.

**Hard rules (REQ-296):**

1. **Fixed homes only** — use the §10 table below. Do **not** invent alternate Docs titles, Initiative sections, comment markers, or local markdown dual-stores for these artifacts while `backend: linear`.
2. **Decisions + calibration = Team Docs** — titles from config: `tracker.linear.decisions_doc_title` (default `do-work/decisions`) and `tracker.linear.calibration_doc_title` (default `do-work/calibration`). **Create-if-missing** when Docs tools are discoverable.
3. **Verify / close = Initiative** — `write_verify_report` → Initiative description `## Verify` (+ Initiative comment with full report). `write_close_report` → Initiative `## Closure` (+ Initiative comment). Prefer description section update; fall back to comment-only if size limits require it (leave a one-line pointer in the section).
4. **Run notes = Issue comments** — `append_run_note` (REQ-294) remains authoritative; optional Project update is non-authoritative rollup only.
5. **Gate locks stay local** — `write_gate_state` writes/deletes `{project}/.do-work/state/gate-owner.md` (and final-suite locks under `state/*`). **Never** put gate ownership in Linear.
6. **No dual-write** — do not also write `.do-work/decisions.md`, `state/calibration.md`, or `user-requests/UR-NNN/closure.md` as the work-item store when `backend: linear`. Optional local ledger telemetry for run notes only when `ledger.enabled` (REQ-294).
7. **Rediscover Docs tools** — Team Docs are unproven until live MCP marks them available; each op still begins with `search_tool`. Missing Docs/Initiative tools → hard-stop for that op (never invent a local substitute store).

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
2. **Same decisions grammar as markdown** — every line is exactly `YYYY-MM-DD | UR/REQ ref | decision | rationale` (SKILL.md § Decisions Memory). Linear issue ids may appear in the ref slot (e.g. `ENG-123`); pipe-separated four fields; one line per decision; append-only; supersede by new line.
3. **Close walks Linear issue ids** — under `backend: linear`, path-units are Issues in Project `do-work/{UR-id}` with path-unit semantics (`Layer: none` + non-empty Entry point + Terminal state). The `req` field in closure rows is the **Linear identifier** (e.g. `ENG-123`), not `REQ-NNN`.
4. **Retro prefers Linear run notes** — when `backend: linear`, collect `<!-- do-work-run-note -->` Issue comments via **List run notes** before treating local `.do-work/runs/` as the only history. Fall back to local telemetry only when comments are unavailable.
5. **Hard-stop on Doc / Initiative write failure — no invent** — if Team Doc **create** or **update** fails (permission, size, MCP error), or Initiative description section update **and** Initiative comment both fail for verify/close, **hard-stop**. Agents must **not** invent ad-hoc Issue comments for decisions/calibration, alternate Doc titles, local `.do-work/decisions.md` / `state/calibration.md` / `closure.md` as substitute stores, or any home outside the §10 table.
6. **§10-allowed spill only** — for verify/close, putting the full report in an **Initiative comment** while leaving a one-line pointer under `## Verify` / `## Closure` is the documented size path (still §10). That is **not** inventing a home. Putting the report on a random Issue, a different Initiative, or a new Doc title **is** inventing — forbidden.

---

## Path: Linear milestone mode (REQ-298)

| | |
|---|---|
| **Entry point** | Milestone-shaped UR (`source: /saas-thesis handoff` + `### Milestones`) with `tracker.backend: linear` — capture, run claim loop, deploy gate |
| **Terminal state** | Active milestone cursor lives on **Project description** `<!-- do-work-milestone -->`; `list_milestone_reqs` / `set_active_milestone` / `read_active_milestone` work via this file; deploy gate remains **local** `state/gate-owner.md` with human y/n; **trigger shape unchanged** |

This path-unit implements design **§11 Milestone mode (Linear)**. Trigger and gate ownership match markdown; only the **cursor store** and **REQ listing** move to Linear.

**Hard rules (REQ-298):**

1. **Trigger unchanged** — Milestone mode activates only when the UR brief has **both** (a) `source: /saas-thesis handoff` and (b) a `### Milestones` heading with at least one `#### M1` (or higher) subheading. Same as markdown capture Step 1b. Do **not** invent a Linear-only trigger.
2. **Cursor home = Project description** — machine block starting with `<!-- do-work-milestone -->` on the UR’s Project (`do-work/{UR-id}`). **Not** local `state/active-milestone.md` as the work-item store under Linear. **Not** Initiative description. **Not** Team Docs.
3. **Checklist lives with the cursor** — active id + full milestone checklist (parity with markdown `active-milestone.md` + `milestones.md`) inside that Project description block.
4. **Deploy gate stays local** — first orchestrator claims via **`write_gate_state`** → `{project}/.do-work/state/gate-owner.md`; human y/n; siblings idle-wait on gate-owner + cursor changes via **`read_active_milestone`**. **Never** put gate ownership in Linear.
5. **Issue membership** — REQs for a milestone are Issues in the UR Project, filterable by milestone marker: prefer Linear Project milestone entity when MCP tools support it after live rediscovery; else **label** equal to the milestone id (e.g. `M1`) and/or body header `**Milestone:** M1`. `list_milestone_reqs` uses those markers.
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
| `list_milestone_reqs` | This file | Filter by Issue milestone markers; no widen to other M |
| Sibling idle on deploy gate | `agents/run.md` Step 1.0a | Same idle loop as markdown; Linear polls `read_active_milestone` + **local** `gate-owner.md` |
| Concurrent gate ownership | `write_gate_state` (this file) + run Step 7b.2 | Serializes via **local** `state/gate-owner.md` even when cursor content is remote |
| Capture / run Linear branches | `agents/capture.md`, `agents/run.md` | Call port ops; never treat local `active-milestone.md` as Linear store |

**Hard rules (REQ-299):**

1. **Marker format is authoritative** — Project description machine block must start with `<!-- do-work-milestone -->` then `**Active:**` then `# Milestones` checklist (see block template below). Parse only that format; do not invent alternate markers (YAML frontmatter, Initiative fields, Team Docs).
2. **Empty marker → null active (does not invent a milestone id)** — when the Project description has **no** `<!-- do-work-milestone -->` marker, or the block is present but `**Active:**` is empty / `none` / missing, `read_active_milestone` returns `active: null` (not-in-milestone / not-active). It **must not** invent `M1` or any other id on read. Capture may *choose* `M1` as first-decompose default **after** observing null — that default is capture policy, not a return value of `read_active_milestone`.
3. **`write_gate_state` remains local-allowed** — gate ownership and final-suite locks stay under `{project}/.do-work/state/` (design §5.5 / §10 / §11). Never Linear Issues, Project description, Initiative, or Docs. Not dual-write of work items.
4. **Concurrent gate ownership serializes via local `gate-owner.md`** — even when milestone **cursor** content is remote (Project description), gate ownership is **only** the local file. First successful claim (absent→write own `AGENT_ID`, re-read confirms self) owns the human y/n prompt; losers idle on Step 1.0a. Do **not** invent a Linear lock or Project-description gate field.
5. **Siblings idle same as markdown** — empty active-M backlog + foreign `gate-owner.md` → idle-wait; wake on cursor advance (`set_active_milestone` / `read_active_milestone`) or cursor clear + gate release. Poll interval and 30-minute stuck prompt parity with markdown Step 1.0a.
6. **Capture and run call port ops** — Linear milestone branches must use `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` / `write_gate_state` from this file; no silent markdown cursor fallback.

---

## Path: Idle markdown→Linear migration (REQ-300)

| | |
|---|---|
| **Entry point** | `/do-work upgrade migrate` (or upgrade **Step 9** migrate path) when the project still uses the **markdown** work-item store and wants a one-shot cutover to Linear — design §12 |
| **Terminal state** | All URs/REQs from markdown backlog + archive exist in Linear (Initiatives / Projects `do-work/{UR-id}` / Issues); Team Docs for decisions (+ empty calibration if missing); `tracker.backend: linear` + resolved team ids written to config; local `user-requests/` + `archive/` (and backlog REQ files) left as **read-only historical** trees; **no dual-write**; dry-run reports planned creates without write |

This path-unit implements design **§12 Migration (markdown → Linear)**. It is **idle-only**, **operator-confirmed** (or dry-run), and **all-or-nothing** on preflight / MCP failure (no partial cutover).

**Hard rules (REQ-300):**

1. **Preflight is absolute** — migration runs only when **all** of:
   - `{project}/.do-work/working/` has **zero** `REQ-*.md` files (empty of in-flight work).
   - **No active claims** (no claim stamps with live heartbeats in working/ — redundant if working empty; still verify no stranded claim protocol elsewhere the agent knows about for markdown).
   - Effective `tracker.backend` is still **`markdown`** (or unset → markdown). Already-`linear` → refuse (already cut over; do not re-migrate).
   - Operator **confirms** cutover **or** the invocation is **dry-run** (report only).
2. **Refuse entirely on failed preflight** — if `working/` is non-empty **or** active claims exist, **refuse the whole migration**. Do **not** create any Linear entities. Do **not** change `tracker.backend`. Config and markdown trees left unchanged. Message: idle required; finish or unblock in-flight work first.
3. **Hard-stop on unusable Linear MCP** — before any write (and if MCP dies mid-migration), **hard-stop** with Linear skill setup instructions. Leave markdown trees **and** `tracker.backend` **unchanged**. **No partial cutover** (do not flip config after only some URs/REQs landed; do not dual-write). Prefer operator cleanup of any orphan Linear entities created mid-flight only when a write phase already started — document orphans in the stop report; never flip backend mid-orphan.
4. **No dual-write after cutover** — once `tracker.backend: linear` is set, work-item ops use **only** this file. Local `.do-work/user-requests/`, backlog `REQ-*.md`, and `archive/` become **historical read-only** (do not delete; ops **stop reading them** as the store).
5. **Dry-run** — when flag/mode is dry-run: run preflight + inventory + planned-create report; **zero** Linear writes; **zero** config changes. Exit after the report.
6. **Rediscover tools** — every Linear create/list uses `search_tool` → `use_tool` with live schemas. Never invent tool names. Missing create tools → hard-stop (same as CRUD preflight).
7. **Map, do not invent** — preserve UR ids, REQ task text, AC checkboxes, deps, parents, status (backlog vs done), closure proof / outputs when present. Linear REQs get **Linear issue ids** only after create (markdown `REQ-NNN` may be noted in body for historical trace, not as the Linear identifier).

**Surfacing (upgrade / conformance):**

| Surface | Role |
|---------|------|
| `agents/upgrade.md` Step **9** / `/do-work upgrade migrate` | Operator-facing UX: preflight, confirm or dry-run, invoke this sequence, report |
| Port op `migrate_markdown_to_linear` | Shared contract (preconditions, refuse / hard-stop, dry-run) — `agents/tracker/port.md` |
| This section | Full agent sequence + status/relation/parent mapping + post-cutover rules |

**Child work under this path:**

| Area | Responsibility | REQ |
|------|----------------|-----|
| Path narrative + hard rules + agent sequence | This file | **REQ-300** |
| Port op contract + shared refuse/hard-stop rules | `agents/tracker/port.md` | **REQ-300** |
| Upgrade migrate step + dry-run flag UX | `agents/upgrade.md` | **REQ-300** |

---

### `migrate_markdown_to_linear` (agent sequence)

| | |
|---|---|
| **Intent** | One-shot idle markdown → Linear cutover (design §12). |
| **Preconditions** | See hard rules 1–2. Team id/key intended for Linear must be known (config `tracker.linear.team_id` / `team_key` or operator-supplied before write). |
| **Modes** | `dry-run` (report only) \| `apply` (writes + config flip after full success). |
| **Does not** | Delete markdown trees; dual-write after cutover; migrate mid-flight working/ REQs; flip config on partial failure. |

#### Step M0 — Invocation flags

| Flag | Meaning |
|------|---------|
| `--dry-run` / dry-run mode | Inventory + planned creates only; no Linear write; no config write |
| apply (default when operator confirmed) | Full sequence; config flip only at M6 after successful creates |

Upgrade agent passes the mode after confirm / dry-run selection (`agents/upgrade.md` Step 9).

#### Step M1 — Preflight (refuse = entire abort)

1. Resolve `{project}` (`git rev-parse --show-toplevel` or CWD).
2. Load config (`agents/config.md`). Effective backend must be **`markdown`**. If effective backend is **`linear`**, **refuse**: already on Linear; do not re-run production migration.
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
6. **Operator confirm** (apply mode only): upgrade agent must have an affirmative confirm. Without confirm and without dry-run → **refuse** (do not write).
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

Group REQs by UR. Skip any REQ whose UR directory is missing only after recording a plan warning (still attempt create under that UR slug if inventable from REQ header).

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

URs (Initiatives + Projects):
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

#### Step M5 — URs then REQs (apply only)

For each inventoried UR (stable order: ascending `UR-NNN`):

1. **Create Initiative** — title from `initiative_title_pattern` / brief title; description = §9.1 template filled from `input.md` + ideate + clarifications + verify/closure sections when present (`<!-- do-work-ur -->`, `**UR-id:** UR-NNN`, `**Project:** do-work/UR-NNN`).
2. **Create Project** named `do-work/{UR-id}` on the resolved team.
3. **Link** Project → Initiative (discovered InitiativeToProject or equivalent). Update Initiative `**Project-id:**`.
4. Atomicity: same as `create_ur` — no Initiative without Project+link. Failure → **hard-stop**; list created entity ids for cleanup; **do not flip config**.

Then for each REQ belonging to that UR (parents before children; backlog + archive):

5. **Map status** via `status_map`:
   - archive / `**Status:** done` → `status_map.done` (default `"Done"`)
   - backlog / open / missing done → `status_map.backlog` (default `"Todo"`)
   - **Never** migrate as `in_progress` (preflight forbids working/). If a file claims stopped in archive-like state, map to `status_map.done` only when archive path or explicit done; otherwise backlog or stopped map per `**Status:**` (`stopped` → `status_map.stopped`).
6. **Build Issue body** from §9.2: copy headers/sections; preserve AC checkboxes literally. Optional historical line: `**Migrated-from:** REQ-NNN` (display only; **not** the Linear id).
7. **Create Issue** in the UR Project with mapped workflow state; labels Layer/Size/path-unit when tools exist; assignee from `default_assignee_id` when set.
8. **Parents / path-units:** if `**Parent:** REQ-X` (markdown id), resolve to the Linear issue id created earlier in this run for that markdown id (maintain a `REQ-NNN → ENG-…` map). Set Linear `parentId` + body `**Parent:** ENG-…`. Create path-unit parents before children.
9. **Deps:** after all Issues for the UR (or globally once all Issues exist), for each REQ with `**Depends on:**`, map markdown ids through the same map and run **`set_blocked_by`** dual-write (native `blocks` + body mirror) using **Linear** ids. If relation tools missing → body-only + one-time warning (port rule).
10. Mid-sequence MCP failure → **hard-stop**. Do **not** set `tracker.backend: linear`. Report orphan Initiative/Project/Issue ids. Markdown trees unchanged. Operator may clean Linear side and re-run after idle preflight (re-run should be safe to plan; apply may create duplicates if orphans left — operator cleans first).

#### Step M6 — Config flip (apply only; only after M4–M5 full success)

Write `{project}/.do-work/config.yml`:

- `tracker.backend: linear`
- `tracker.linear.team_id` / `team_key` as resolved (persist the id used)
- Leave other `tracker.linear.*` keys as already migrated defaults

**Only after** this write is the cutover complete. Until then, effective backend remains markdown.

If config write fails after Linear creates succeeded: **hard-stop** with: Linear entities exist; config still markdown; operator must set `tracker.backend: linear` manually **or** delete Linear orphans and retry. Do not dual-write; do not invent a half-mode.

#### Step M7 — Post-cutover (historical trees)

1. **Do not delete** `.do-work/user-requests/`, `.do-work/archive/`, backlog `REQ-*.md`, or `decisions.md`.
2. Treat them as **read-only historical**. Phase agents with `backend: linear` **must not** read them as the work-item store (port load path → this file only).
3. Runtime locals unchanged: worktrees, `state/*` locks, events, gate-owner, optional ledger telemetry.
4. Report success: counts created, id map summary (`REQ-NNN → Linear id`), config backend now linear, pointer to Linear skill if further setup needed.

#### Failure matrix (no partial cutover)

| Failure | Behavior |
|---------|----------|
| `working/` non-empty or active claims | **Refuse entirely** — no Linear writes; config unchanged |
| Operator declines confirm (apply) | **Refuse** — no writes |
| Linear MCP missing / unauthenticated / team unresolved / status_map missing | **Hard-stop** with setup instructions — markdown trees + config unchanged |
| MCP dies during M4–M5 | **Hard-stop** — config **not** flipped; list orphans; markdown unchanged |
| Config write fails after creates | **Hard-stop** — report manual flip or orphan cleanup; no dual-write mode |
| Dry-run | Report only — always safe |

#### Mapping summary

| Markdown | Linear |
|----------|--------|
| `user-requests/UR-NNN/` + brief | Initiative (`<!-- do-work-ur -->`) + Project `do-work/UR-NNN` + link |
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

## When to load

After config load and backend resolution (`port.md` load path + `agents/config.md` Load Config step 7):

1. Effective backend is **`linear`**.
2. Linear validation passes (team resolvable, MCP discoverable, every `status_map` state exists on the team) — or agent **hard-stops** (see below).
3. Read `agents/tracker/port.md`.
4. Read this file.
5. Perform work-item ops only via port ops mapped here (**UR/REQ CRUD**, templates §9, append/deps/footprint, claim/status/unblock/resume, run archive / append_run_note / §6.5 commits, **§10 non-ticket artifacts** — `append_decision`, calibration Doc, `write_verify_report`, `write_close_report`, **§11 milestone cursor** — `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs`; gate locks local via `write_gate_state`).

**Exception — idle migration (REQ-300):** `/do-work upgrade migrate` / port op **`migrate_markdown_to_linear`** is invoked while effective backend is still **`markdown`**. The upgrade agent loads this file’s **Path: Idle markdown→Linear migration** section for the cutover sequence only (preflight still refuses non-idle markdown state). After successful config flip to `linear`, all subsequent work-item ops use this file under the normal load path above.

Do **not** load this file for ordinary work-item ops when backend is `markdown` (including unset/empty), except the migration path above.

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
| `list_claimable_reqs` | Issues + relations + comments + statuses | **Documented** (REQ-292/294/295) — Priority DESC (missing→2) → created_at ASC → id ASC; skip reasons; deps via **blocks**; footprint algorithm; no claim side-effect |
| `claim_req` / `heartbeat_req` / `unblock_req` | Issues status + comments | **Documented** (REQ-292) — optimistic claim comment protocol |
| `set_req_status` | Workflow states, issues | **Documented** (REQ-292) — stopped / in-progress without archive or unclaim |
| `archive_req` | Workflow states, issues, claim release, body proof/outputs | **Documented** (REQ-294/295) — done + proof + outputs + claim released; **not** called after failed review/evidence |
| `set_blocked_by` | Issue relations `blocks` (+ body mirror) | **Documented** (REQ-291) — dual-write; if relations **missing** → body-only + one-time warning (port rule) |
| `set_files` | Issue description headers | **Documented** (REQ-291) — updates `**Files:**` only; no claim side-effect |
| `append_decision` | Team Doc `decisions_doc_title` | **Documented** (REQ-296 ops; REQ-297 consumers) — create-if-missing; same one-line grammar; hard-stop on create/update fail |
| Calibration (retro write / capture read) | Team Doc `calibration_doc_title` | **Documented** (REQ-296/297) — create-if-missing; full replace body; hard-stop invent ban |
| `write_verify_report` | Initiative `## Verify` + Initiative comment | **Documented** (REQ-296/297) — dual-fail hard-stop |
| `write_close_report` | Initiative `## Closure` + Initiative comment | **Documented** (REQ-296/297) — close path-unit walk uses Linear issue ids |
| `append_run_note` | Issue comments (+ optional project update) | **Documented** (REQ-294) — authoritative run/cost notes; local ledger optional telemetry |
| List run notes (helper) | Issue comments `<!-- do-work-run-note -->` | **Documented** (REQ-297) — retro prefers Linear notes, falls back to local telemetry |
| `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` | Project description `<!-- do-work-milestone -->` + Issue milestone markers | **Documented** (REQ-298 path; **REQ-299** ops) — empty marker → null; does not invent milestone id |
| `write_gate_state` | **Local** `state/gate-owner.md` (not Linear) | **Documented** (REQ-296 home; **REQ-299** concurrent serialize) — local only; never Linear |

---

## Templates (design §9)

Bodies are **markdown conventions** in Linear description fields — not custom Linear fields. Prefer description appends; fall back to Initiative/Issue **comments** if description size limits require it (record a one-line pointer in the section when spilling).

**Machine markers (required):**

| Entity | Marker (first non-empty line of structured body) | Op consumers |
|--------|--------------------------------------------------|--------------|
| Initiative (UR) | `<!-- do-work-ur -->` | `create_ur`, `read_ur`, `list_urs`, `append_ideate`, `append_clarifications`, verify/close writers |
| Issue (REQ) | `<!-- do-work-req -->` | `create_req`, `update_req`, `read_req`, `set_files`, `set_blocked_by`, `claim_req` / `heartbeat_req` / `unblock_req` / `set_req_status`, archive later |

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

## Non-ticket artifact homes (design §10 — REQ-296)

Agents **must not invent** homes. Use only the rows below (plus local gate locks). Config titles are authoritative when set.

| Artifact | Linear home | Format | Writers / readers | Port op / sequence |
|----------|-------------|--------|-------------------|--------------------|
| Decisions | Team Doc title = `tracker.linear.decisions_doc_title` (default **`do-work/decisions`**) | One line per decision: `YYYY-MM-DD \| UR/REQ ref \| decision \| rationale` | capture write; capture / ideate / question / worker read | **`append_decision`**; **Read decisions** helper |
| Calibration | Team Doc title = `tracker.linear.calibration_doc_title` (default **`do-work/calibration`**) | Full calibration body (same shape as markdown `state/calibration.md`) | retro write (full replace); capture read | **Write / read calibration Doc** |
| Run / cost notes | Comment on Issue after attempt; optional Project update for run rollup | YAML fenced block + `<!-- do-work-run-note -->` | run | **`append_run_note`** (REQ-294) |
| Verify report | Initiative description `## Verify` + Initiative comment | Full report markdown | verify, go | **`write_verify_report`** |
| Close report | Initiative description `## Closure` + Initiative comment | Per path-unit results (closure schema) | close | **`write_close_report`** |
| Milestone cursor | Project description `<!-- do-work-milestone -->` | active M + checklist | capture, run | **`read_active_milestone`** / **`set_active_milestone`** / **`list_milestone_reqs`** (REQ-298 path; **REQ-299** ops) |
| Gate locks | **Local** `{project}/.do-work/state/gate-owner.md`, `final-suite-*.md` | unchanged | run | **`write_gate_state`** (local only; REQ-299 concurrent serialize) |

**Create-if-missing (Team Docs):** on first write, if no Doc with the configured title exists for the configured team, create it (title exact match to config), then write. Readers: if missing, treat as empty (no decisions / no calibration) — never invent content.

**Hard-stop (REQ-296 / REQ-297):** if Docs tools (for decisions/calibration) or Initiative update/comment tools (for verify/close) are undiscoverable after `search_tool`, **or** Team Doc create/update fails (permission, size, MCP error), **or** Initiative description append/update fails **and** the §10 Initiative-comment path also fails — hard-stop that op with Linear setup / permission instructions. Do **not**:

- fall back to local `.do-work/decisions.md` / `state/calibration.md` / `closure.md` as the work-item store
- invent alternate Doc titles outside `decisions_doc_title` / `calibration_doc_title`
- invent ad-hoc Issue comments (or Project updates) as a substitute home for decisions, calibration, verify, or close reports

§10-allowed Initiative comment for the full verify/close body (with a section pointer) remains valid when description size alone fails.

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

### Concept → Linear mapping

| Concept | Linear rule |
|---------|-------------|
| **Unclaimed** | Workflow maps to `status_map.backlog` **and** no **active** claim comment (or latest claim is `released`) |
| **Claim** | Re-read issue + comments; if another agent has active claim with **fresh** heartbeat → fail; else set state → `in_progress`; post claim comment (`status: active`) |
| **Heartbeat** | New claim-protocol comment **or** append/update path that writes updated `heartbeat` (prefer new comment if update-comment tools missing); consumers take latest active block |
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
| **Preconditions** | Preflight passed; Project scope known (optional `UR-NNN` / project id, or product-wide `do-work/UR-*` scan). |
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

Milestone / scope filters (when caller passes them) apply **before** the walk: only issues in the scoped Project(s) / milestone marker are candidates.

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
2. **Enumerate candidates** — issues in scope Project(s) whose workflow state maps to **`status_map.backlog`**. Exclude `done` / `in_progress` / `stopped` unless a stale active claim is being recovered under explicit reclaim policy (default pick: **backlog + unclaimed only**). Apply scope filter; emit `scope:<id>` for excluded-by-scope backlog issues when useful for classify.
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
2. **Read active claim** — must be `status: active` and `agent_id` match (or explicit owner handoff policy). If no active claim → error (nothing to heartbeat). If foreign active fresh claim → error / concurrent-conflict (do not stamp over).
3. **Write heartbeat** — post a new claim-protocol comment (or update the existing comment if update-comment tools exist and schema allows) with:
   - same `agent_id`, same `claimed_at` (preserve original claim time)
   - `heartbeat: {now_iso}`
   - `status: active`
   - same `session` if known
4. Consumers always take the **latest** active block by `heartbeat` timestamp.
5. **Return** issue id + new heartbeat time.

| Failure | Behavior |
|---------|----------|
| Not claim owner / no active claim | Error; do not create a new claim (use `claim_req`) |
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
4. **Optional Project update** — if project-update tools exist and the caller wants a run rollup, post a short summary on Project `do-work/{UR-id}` (non-authoritative convenience; Issue comment remains the home per design §10).
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
2. **Scope** — Issues under Projects matching `do-work/UR-*` for the configured team (or a single UR’s Project when scoped). Prefer Issues that have been attempted (in_progress / stopped / done), not pure backlog with zero comments.
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
| **Does not** | Rewrite prior lines; change Issues/Initiatives; write calibration. |

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
| **Preconditions** | UR Initiative exists (`read_ur` / `do-work/{UR-id}` project linked); verify agent has produced the report body. |
| **Home** | Initiative description section **`## Verify`** + **Initiative comment** with the full report. **Not** a local file under `user-requests/` as source of truth. |
| **Does not** | Create REQs; change claim state; invent alternate section names. |

**Agent sequence:**

1. **Rediscover** — tools to get/update Initiative description and create Initiative comments. Queries such as `"linear initiative"`, `"linear update initiative"`, `"linear create comment"`.
2. **Resolve UR** — load Initiative for `UR-NNN` (`read_ur`). Confirm `<!-- do-work-ur -->` body.
3. **Build report** — full markdown verify report (confidence score, coverage, gaps, issues, summary — same console shape as `agents/verify.md` Step 5c).
4. **Update `## Verify` section** — replace or insert content under `## Verify` in the Initiative description (prefer description append/replace of that section only; do not overwrite `## Brief`). Include at least: confidence score, recommendation, and a short summary. If the full report exceeds size limits, put a one-line pointer in `## Verify` (e.g. `Full report: see Initiative comment <timestamp>`) and put the **full** body in the comment.
5. **Post Initiative comment** — full report body, optionally prefixed with `<!-- do-work-verify-report -->` for stable readers.
6. **Return** Initiative id + comment id / success. Do **not** write a durable local verify path as the work-item store.

| Failure | Behavior |
|---------|----------|
| Initiative tools missing | Hard-stop |
| UR / Initiative not found | Hard-stop; do not invent Initiative |
| Size limit on description only | Section pointer + full **Initiative** comment (required §10 path above) — **not** inventing a home |
| Description **and** Initiative comment both fail (permission / size / MCP) | Hard-stop; **do not** invent Issue comments, alternate Docs, or local verify files as the store |

**Markdown backend note:** `markdown.md` remains console-primary for verify (no fixed durable path). Linear makes verify durable via this op.

---

### `write_close_report`

| | |
|---|---|
| **Intent** | Persist close-phase path-unit closure report for a UR. |
| **Preconditions** | UR Initiative exists; close agent has produced the closure document (YAML front matter + per path-unit rows). |
| **Home** | Initiative description section **`## Closure`** + **Initiative comment** with the full closure report. **Not** `{project}/.do-work/user-requests/UR-NNN/closure.md` as source of truth under Linear. |
| **Does not** | Edit REQs/source; reopen Issues; put gate locks in Linear. |

**Agent sequence:**

1. **Rediscover** Initiative get/update + comment create tools.
2. **Resolve UR** — Initiative for `UR-NNN` via `read_ur`.
3. **Build report** — same schema as `agents/close.md` Step 5 (`ur`, `closed_at`, `branch`, `path_units`, `verdict_summary`, `overall`, plus per-path-unit rows). Empty path-unit case still writes a valid `overall: no-path-units` report.
4. **Update `## Closure` section** — replace/insert under `## Closure` only. Short summary in description is fine; full YAML+rows may live in the comment if size-constrained (pointer line in section required when spilling).
5. **Post Initiative comment** — full closure markdown, optionally prefixed with `<!-- do-work-close-report -->`.
6. **Evidence artifacts** — screenshots / command captures remain **local** under a UR-scoped path only if the operator needs files on disk (optional); `evidence_ref` may point at local paths or inline snippets. Local evidence files are **not** a second work-item store for the report itself.
7. **Return** Initiative id + success. Do **not** dual-write authoritative `closure.md` under `user-requests/` when `backend: linear`.

| Failure | Behavior |
|---------|----------|
| Initiative tools missing | Hard-stop |
| UR missing | Hard-stop |
| Size limit on description only | Section pointer + full **Initiative** comment (§10) |
| Description **and** Initiative comment both fail (permission / size / MCP) | Hard-stop; **do not** invent Issue comments, alternate Docs, or local `closure.md` as the store |

#### Close path-unit collection (Linear — REQ-297)

When `agents/close.md` walks a UR under `backend: linear`, path-units come from Linear Issues — not from local `archive/REQ-*.md`:

1. Resolve Project `do-work/{UR-id}` and call **`list_reqs_for_ur`** (all Issues in that Project; include done/archived-equivalent).
2. For each Issue body, treat as a **path-unit** when `**Layer:**` is `none` **and** both `**Entry point:**` and `**Terminal state:**` are present and non-empty after trim.
3. Extract: `req` = **Linear issue identifier** (e.g. `ENG-123`); `entry_point` / `terminal_state` = verbatim header values.
4. Do **not** read `**Closure proof:**` (same cold-dispatch rule as markdown).
5. Walk still runs against the **merged local app** (git). Persist results only via **`write_close_report`**.
6. Closure row `req:` fields and report headings use Linear ids (`## ENG-123 — closed`), never parallel `REQ-NNN` allocation.

Brief load under Linear: **`read_ur`** (Initiative description `## Brief` / machine sections) — do not require local `user-requests/UR-NNN/input.md` as the store.

---

## Milestone mode (design §11 — REQ-298 path; REQ-299 ops)

### Trigger (unchanged)

Identical to markdown capture / run:

1. UR brief frontmatter or body contains `source: /saas-thesis handoff`.
2. Body contains a `### Milestones` heading with at least one `#### M1` (or higher) subheading.

Both required → **milestone mode**. Neither Linear labels nor Project cursor alone turn milestone mode on. Brief load under Linear: **`read_ur`** (`## Brief` / machine sections); do not invent a different trigger.

### Project description cursor block (marker format)

Authoritative work-item cursor under `backend: linear`. Lives on the UR **Project** description (`do-work/{UR-id}`), not Initiative and not local `active-milestone.md`.

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
| **Home** | UR Project description block `<!-- do-work-milestone -->`. |
| **Preconditions** | None beyond readable Project; missing / empty block ⇒ not in milestone mode. |
| **Returns** | `{ active: "M1" \| null, checklist: [...] }` — `active` null when marker missing, `**Active:**` empty/`none`/malformed, or Project unresolved. **Does not invent a milestone id.** |

**Agent sequence:**

1. **Rediscover** Project get/list tools (`search_tool` → `use_tool`).
2. **Resolve Project** — name `do-work/{UR-id}` (or Project id from `read_ur` / `**Project-id:**`). Caller may pass Project id or UR id.
3. **Read description.** Apply **Parse algorithm** above.
4. **Return** structured result. Do **not** read local `state/active-milestone.md` as the store. Do **not** default missing cursor to `M1` inside this op.

| Failure | Behavior |
|---------|----------|
| Project tools missing | Hard-stop — Linear setup; do **not** fall back to local `active-milestone.md` as work-item store |
| Project missing | Hard-stop (UR not provisioned) |
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

1. **Rediscover** Project get/update tools.
2. **Resolve Project** for the UR.
3. **Read** current description + existing milestone block (create block if capture is writing first cursor).
4. **Apply caller intent:**
   - **Set / advance** to `M<n>`: set `**Active:** M<n>`; update checklist line for prior M to `deployed` (or caller-supplied status); set target line to `captured` / `running` / as requested.
   - **Capture stamp:** after capture writes REQs for `M<n>`, set `**Active:** M<n>` and mark that line `captured` (create full checklist from brief `### Milestones` on first write).
   - **Clear** (all deployed, or gate `n` stop): set `**Active:**` empty or remove the active value; mark remaining lines per caller; or strip the whole block when the run stops with no next M. Prefer leaving checklist history with `deployed` marks when useful for humans.
5. **Write** Project description — replace **only** the milestone machine block; preserve any other Project description content outside the block.
6. **Return** new `active` value (or null if cleared).

| Failure | Behavior |
|---------|----------|
| Project tools missing / update fails | Hard-stop; do **not** write local `active-milestone.md` as substitute store |
| Invalid target id | Hard-stop / refuse |

**Deploy-gate consumers (run Step 7b):** on human **y**, call `set_active_milestone` with next pending id (or clear if none). On human **n**, clear active. Gate file lifecycle stays on **`write_gate_state`**.

### `list_milestone_reqs`

| | |
|---|---|
| **Intent** | List REQs (Linear Issues) belonging to the active or named milestone. |
| **Preconditions** | Milestone id known (`M<n>`) or active cursor set via `read_active_milestone`. |
| **Scope** | Issues in the UR Project `do-work/{UR-id}` only. |

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

1. **Rediscover** list issues (scope: optional UR Project `do-work/{UR-id}`, or all `do-work/UR-*` projects on the team). Prefer `list_reqs_for_ur` / list-by-project sequences already documented above.
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

## Out of scope for this file state

- Full UR/REQ CRUD rewires beyond homes already mapped → later REQs where noted. **Claim consumers** as of REQ-293; **run archive/notes/commits** as of REQ-294; **pick order / footprint / review-gate / branch sanitize** as of REQ-295; **§10 non-ticket homes** as of REQ-296; **artifact home consumers** as of REQ-297; **milestone path** (trigger, cursor home, local gate) as of **REQ-298**; **milestone cursor ops** as of **REQ-299**; **idle markdown→Linear migration** (`migrate_markdown_to_linear`, dry-run, refuse non-empty working/, hard-stop MCP without partial cutover, historical trees) as of **REQ-300**.
- Dual-write or treating local REQ files as source of truth while `backend: linear`.
- Inventing tool names not returned by live `search_tool` (including treating Linear skill typical-tool tables as proven).
- True distributed locks on Linear (optimistic claim only — design non-goal).
- Linear-aware bash under `lib/` (explicitly deferred; agent/MCP sequences only for v1).
- Automatic re-migration or continuous sync after cutover (one-shot only).

---

## References

- `agents/tracker/port.md` — shared ops and hard-stop / leave-claimed / relations-authoritative / claim rules; **`migrate_markdown_to_linear`** contract
- `agents/config.md` — `tracker.*` schema including `decisions_doc_title` / `calibration_doc_title`, `agent_claim_marker`, `heartbeat_max_age_seconds`, `review.required`, Load Config step 7
- `agents/upgrade.md` — **Step 9** `/do-work upgrade migrate` UX (preflight, dry-run, confirm, invoke sequence)
- `agents/resume.md` / `agents/unblock.md` / `agents/status.md` / `agents/run.md` / `agents/run-worker.md` / `agents/review.md` — claim/run consumers
- `agents/capture.md` / `agents/ideate.md` / `agents/question.md` / `agents/verify.md` / `agents/close.md` / `agents/retro.md` / `agents/run-worker.md` — §10 artifact consumers (REQ-296 homes; REQ-297 full reader/writer wiring)
- `agents/capture.md` / `agents/run.md` — §11 milestone consumers (REQ-298 path; **REQ-299** port ops)
- Design: `docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md` (§5.5 runtime split, §6.5 commits, §7 config/ledger, §8 claim, §9 templates, §10 homes, §11 milestone mode, **§12 migration**, §14 errors, §17 risks)
- Linear skill: MCP-first, rediscover tools live (`search_tool` → `use_tool`)
- Prior: REQ-288–299; this path **REQ-300** idle markdown→Linear migration
