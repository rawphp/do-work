# Tracker port (shared contract)

Shared work-item operation catalog and load path for do-work multi-tracker backends.
Phase agents that touch URs/REQs (or other work-item artifacts) resolve storage **only** through this port and the active backend file — never by inventing raw store paths or tools outside the backend doc.

This file freezes **op names**, **preconditions**, and **backend-independent semantic rules** (claim, deps, footprint, hard-stop, mid-flight failure). Backend files implement each op; they must not invent alternate op names or weaken these rules.

---

## Path: markdown-default (REQ-283)

| | |
|---|---|
| **Entry point** | `/do-work` phase agents with `tracker.backend` **unset**, **empty**, or explicitly `markdown` |
| **Terminal state** | All work-item ops resolve through `agents/tracker/port.md` + `agents/tracker/markdown.md`; existing `lib/tests` and conformance pass **without** Linear MCP, Linear credentials, or dual-write |

This path is the happy path for every project that has not opted into Linear. Product behavior (TDD-per-REQ, worktrees, claim/deps/footprint, review gate) is unchanged; only the **documented store surface** is named so a second backend can plug in later.

**Child work under this path (do not re-implement here):**

| Area | Responsibility |
|------|----------------|
| Config schema (`tracker.*`) | Full keys, validation, migrate-to-disk |
| Port op catalog body | This file — preconditions, claim/deps/footprint, hard-stop, mid-flight |
| Markdown backend mapping | Op → `lib/*.sh` + `.do-work/` path sequences (`markdown.md`) |
| Linear backend mapping | Op → Linear skill/MCP sequences (`linear.md`; no tool inventing here) |
| Phase-agent load-path wiring | Each agent that touches work items loads port + backend |

---

## Load path (every work-item phase)

1. Load config (`agents/config.md`).
2. Resolve `tracker.backend`:
   - **missing key, empty string, or whitespace-only** → treat as **`markdown`**
   - **`markdown`** → continue; **no Linear tools required**, no hard-stop
   - **`linear`** → Linear backend path; Linear must be usable (see **Hard-stop matrix**)
   - **`sqlite`** → SQLite backend path; `sqlite3` + `agents/tracker/sqlite.md` + usable DB required (see **Hard-stop matrix**)
   - **`do-work-io`** → do-work.io backend path; remote MCP + PAT + project slug required (see **Hard-stop matrix**)
   - **any other value** → hard-stop with a clear config error (do not guess)
3. Read `agents/tracker/port.md` (this file).
4. Read `agents/tracker/<backend>.md` (for default: `agents/tracker/markdown.md`; opt-in: `linear.md`, `sqlite.md`, or `do-work-io.md`).
5. For work-item storage, call **only** named port ops documented in the backend file.

Phase agents keep product logic (TDD, review, decomposition). They do not re-implement store details and do not dual-write across backends.

---

## Backend files

| File | Role |
|------|------|
| `agents/tracker/port.md` | Shared op names, rules, load path (this document) |
| `agents/tracker/markdown.md` | File + `lib/*.sh` implementation of port ops (default) |
| `agents/tracker/linear.md` | Linear skill/MCP sequences for the same ops (opt-in) |
| `agents/tracker/sqlite.md` | SQLite + `lib/dw-db.sh` sequences for the same ops (opt-in) |
| `agents/tracker/do-work-io.md` | do-work.io MCP sequences for the same ops (opt-in) |

Later backends (e.g. GitHub Issues, Jira) add sibling files; they are not part of the markdown-default path.

---

## Work-item vs runtime split (design §5.5)

From the storage inventory: **work-item** data is what the active tracker backend owns; **runtime / git / config** always stay local regardless of backend.

### Must map through port ops (work-item store)

| Domain | Examples (ops) |
|--------|----------------|
| Issue lifecycle (slug `UR-NNN`; ops still `*_ur`) | `create_ur`, `read_ur`, `list_urs`, `append_ideate`, `append_clarifications` |
| REQ lifecycle | `create_req`, `update_req`, `read_req`, `list_reqs_for_ur`, `set_req_status`, `archive_req` |
| Claim / pick | `list_claimable_reqs`, `claim_req`, `heartbeat_req`, `unblock_req` |
| Deps / footprint fields | `set_blocked_by`, `set_files` |
| Non-ticket artifacts | `append_decision`, `write_verify_report`, `write_close_report`, `append_run_note` |
| Milestone cursor content | `read_active_milestone`, `set_active_milestone`, `list_milestone_reqs` |
| Product container | `ensure_product_container` |

In Linear mode these live only in Linear (Initiatives, Projects, Linear Issues for REQs, Docs, comments) — **no dual-write** to Issue/REQ markdown as source of truth. Product noun **Issue** (do-work) ≠ Linear Issue (REQ).

### Stay local (not port work-item storage)

| Domain | Notes |
|--------|--------|
| Worktrees, branches, merges, PRs | Git isolation; branch names may reference Linear issue ids |
| `state/*` locks, events, context-pack, retry counters | Orchestrator coordination |
| `config.yml`, install, conformance | Config load path; tracker backend selection |
| Gate-owner / final-suite locks | Deploy-gate coordination; `write_gate_state` may still use a **local** lock file even when work-items are remote |
| Optional local ledger telemetry | If `ledger.enabled`, local `.do-work/runs/RUN-NNN.yml` may mirror cost notes for offline tooling — **telemetry only**, not a second work-item store |

Claim **semantics** are port rules; claim **representation** is backend-specific (markdown: claim stamp on the REQ file; Linear: workflow status + claim **comment**, not a local claim file).

---

## Hard-stop matrix (unusable active backend)

**Shared rule:** unusable **active** backend → **hard-stop**; **never** silent fallback to another backend (markdown ↔ linear ↔ sqlite ↔ do-work-io).

| Condition | markdown | linear | sqlite | do-work-io |
|-----------|----------|--------|--------|------------|
| Backend doc missing / unreadable | n/a (default file always present) | **hard-stop** (`agents/tracker/linear.md`) | **hard-stop** (`agents/tracker/sqlite.md`) | **hard-stop** (`agents/tracker/do-work-io.md`) |
| MCP / team / `status_map` fail | n/a | **hard-stop** | n/a | **hard-stop** (MCP unusable / unauthenticated) |
| `sqlite3` missing from PATH | n/a | n/a | **hard-stop** (+ install hint) | n/a |
| DB corrupt / unreadable | n/a | n/a | **hard-stop** | n/a |
| Schema `user_version` unsupported / bad | n/a | n/a | **hard-stop** | n/a |
| Lock timeout after retries | n/a | n/a | **hard-stop** or concurrent-conflict (claim races) | n/a |
| PAT / base URL / project slug missing | n/a | n/a | n/a | **hard-stop** |
| Mid-flight after successful claim | leave claimed | leave claimed | leave claimed (active claims row) | leave claimed (active claim on the server) |
| Fallback to another backend | **never** | **never** | **never** | **never** |

### Linear detail (when `backend: linear`)

| Condition | Behavior |
|-----------|----------|
| `agents/tracker/linear.md` missing or unreadable | **Hard stop** with setup instructions (restore the Linear backend doc from the skill install; do not invent Linear sequences) |
| Linear MCP missing, offline, or unauthenticated | **Hard stop** with setup instructions from the Linear skill |
| Team id / team key unresolved | **Hard stop**; do not guess a team |
| Required `status_map` workflow state missing on the team | **Hard stop** with rename / map-fix instructions |
| MCP dies mid-op before a safe commit point | **Hard stop** — see **Mid-flight failure (leave claimed)** |

Agents must not switch to `markdown` or `sqlite` ops “to keep going”, write UR/REQ files under `.do-work/` as a substitute store while backend is `linear`, or invent partial local mirrors of Linear work items.

### SQLite detail (when `backend: sqlite`)

| Condition | Behavior |
|-----------|----------|
| `agents/tracker/sqlite.md` missing or unreadable | **Hard stop** with setup instructions (restore from skill install; do not invent SQL sequences) |
| `sqlite3` CLI missing from PATH | **Hard stop** with install hint (`brew install sqlite` / distro package) |
| DB corrupt, unreadable, or `PRAGMA user_version` unsupported | **Hard stop** — offer recreate-empty option in the operator message; **never** fall back to markdown or Linear |
| `lib/dw-db.sh` ensure/open fails after retries | **Hard stop** (or concurrent-conflict on claim races) |

Agents must not glob `.do-work/REQ-*` / `user-requests/` as live truth while backend is `sqlite`, dual-write markdown trees, or invent freehand `sqlite3` one-liners outside `lib/dw-db.sh` / `sqlite.md`.

### do-work-io detail (when `backend: do-work-io`)

| Condition | Behavior |
|-----------|----------|
| `agents/tracker/do-work-io.md` missing or unreadable | **Hard stop** with setup instructions (restore from skill install; do not invent MCP sequences) |
| MCP mount unreachable, tools undiscoverable, or unauthenticated | **Hard stop** with PAT / URL setup (do not fall back to HTTP-only invention outside the backend doc) |
| `tracker.dowork.project` empty / project.ensure over-cap or 404 | **Hard stop**; do not guess a slug |
| `token_env` empty or unset in the process environment | **Hard stop**; do not paste the PAT into chat |
| Mid-flight after successful claim | leave claimed (active claim row on the server) |

Agents must not switch to `markdown`, `linear`, or `sqlite` ops “to keep going”, write UR/REQ files under `.do-work/` as a substitute store while backend is `do-work-io`, or invent partial local mirrors of remote work items.

### Markdown detail (when `backend: markdown`, including unset/empty)

Linear MCP and SQLite DB availability are irrelevant — no Linear tools or `sqlite3` required, no hard-stop for those backends.

---

## Mid-flight failure (leave claimed)

If the active backend becomes unusable **after** a successful `claim_req` but **before** `archive_req` / clean `unblock_req`:

1. **Leave claimed** — do **not** clear the claim, force backlog, or silently release the slot.
2. Work item stays in-progress with the last claim / heartbeat as written (Linear: claim comment; markdown: working/ stamp; sqlite: active claims row).
3. Operator recovers with `/do-work resume` or `/do-work unblock` after the backend is healthy again (same multi-agent recovery story as concurrent-conflict).
4. The failing agent exits stopped (e.g. concurrent-conflict / missing-creds / dependency-missing as appropriate to the surface); it does **not** invent a “claimed-but-abandoned” cleanup that races siblings.

This applies to **all** backends (Linear MCP death, markdown worker crash, sqlite lock/DB failure mid-flight).

---

## Deps authority (relations authoritative)

| Backend | Authoritative deps for eligibility | Mirror / display |
|---------|------------------------------------|------------------|
| **markdown** | `**Depends on:**` header on the REQ (file is the store) | same field |
| **linear** | Native Linear **`blocks` relations** | `**Depends on:**` line in Issue body is a **mirror** only |

Rules (backend-independent intent):

1. **`list_claimable_reqs` / deps checks** use the **authoritative** graph for the active backend — never a stale mirror when relations exist.
2. On Linear, if native `blocks` relations and body `**Depends on:**` diverge, **relations win** for claim eligibility.
3. **`set_blocked_by`** always updates the authoritative store; when relation tools exist on Linear, it updates **both** relations and body mirror.
4. If relation tools are unavailable on Linear, backends may fall back to description-only deps with a one-time warning (documented in `linear.md`) — still no silent markdown fallback.
5. A dependency is **satisfied** only when the depended-on REQ is **archived/done** (backend equivalent). Unsatisfied deps block claim.

---

## Claim, deps, and footprint semantic rules

These rules are shared. Backends implement the representation; they must preserve the semantics.

### Claim

| Concept | Rule |
|---------|------|
| Unclaimed | Backlog-equivalent status **and** no active claim (or last claim released / unblocked) |
| Claim (`claim_req`) | **Optimistic:** re-read before write; if another agent holds an active claim with a fresh heartbeat → fail (`concurrent-conflict`); else mark in-progress and record claim + heartbeat |
| Heartbeat (`heartbeat_req`) | Refresh liveness timestamp on the active claim; consumers take the latest active claim |
| Stale | Latest active heartbeat older than configured max age (`parallel.stale_threshold_seconds` or backend override) — recoverable by claim takeover / resume / unblock per multi-agent rules |
| Unblock (`unblock_req`) | Return to backlog-equivalent; clear / release claim |
| Resume | stopped → in-progress; refresh heartbeat; do not steal human assignee semantics on Linear |
| Atomicity | Markdown: FS claim stamp + move. Linear: re-read + comment protocol (no true distributed lock — intentional) |

### Footprint

| Concept | Rule |
|---------|------|
| Representation | Structured `**Files:**` (and related header fields) on the REQ — **not** ad-hoc custom fields |
| Free footprint | No other **in-flight** (claimed / working) REQ’s footprint overlaps the candidate’s declared paths |
| Overlap | Blocks `list_claimable_reqs` / claim until the overlapping in-flight REQ archives or changes footprint |
| `set_files` | Updates the footprint list; does not by itself claim or unclaim |

### Deps (eligibility)

| Concept | Rule |
|---------|------|
| Graph | Declared depends-on edges (authoritative store per backend — see **Deps authority**) |
| Satisfied | Every depended-on work item is done/archived |
| Unsatisfied | REQ is not claimable |
| `set_blocked_by` | Writes the graph (and mirror when applicable) |

### Pick order (`list_claimable_reqs`)

A REQ is claimable only when **all** of the following hold:

1. Status is backlog-equivalent (not in-progress, stopped-held, or done).
2. Unclaimed (or stale claim eligible for recovery per multi-agent rules).
3. Deps satisfied (authoritative graph).
4. Footprint free vs other in-flight REQs.
5. Within scope filters the caller applies (e.g. active milestone, single UR project).

Backends return pick-order suitable for the run loop; exact ordering policy lives in the backend / pick implementation.

---

## Operation catalog (design §5.4)

Names freeze intent. Exact field shapes and store sequences live in each backend file. Markdown may compose several ops from existing `lib/*.sh` scripts. **Do not invent Linear tool call names in this file** — those belong only in `linear.md`.

### Catalog index

| Op | Intent |
|----|--------|
| `ensure_product_container` | Product/team container ready (markdown: dirs; Linear: shared product Project create/bind + persist UUID) |
| `create_ur` | Record intake brief |
| `read_ur` | Load brief (+ ideate if present) |
| `list_urs` | Enumerate URs for prompts/status |
| `append_ideate` | Write ideate onto UR |
| `append_clarifications` | Question-phase Q&A |
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
| `migrate_markdown_to_linear` | One-shot idle markdown→Linear cutover (design §12); dry-run supported |

### Op contracts

Each op lists **intent**, **preconditions**, and **notes**. Inputs/outputs are conceptual; backends map them to files or remote entities.

#### `ensure_product_container`

| | |
|---|---|
| **Intent** | Ensure the product/team container for work items is ready. **Markdown:** local `.do-work/` dirs. **Linear:** team resolvable; **create or bind** the shared product Project when missing (`product_project` resolve chain + list/create + **persist UUID**); optional labels ready. |
| **Preconditions** | Config loaded; backend resolved. For Linear: team resolvable or hard-stop. |
| **Notes** | Idempotent. Does not create an Issue or REQ. Linear never falls through to skill name `do-work` for empty `product_project`. Multi-match by name and empty-name failures hard-stop (no markdown substitute store). |

#### `create_ur`

| | |
|---|---|
| **Intent** | Record a new intake brief as an **Issue** (product noun; wire/slug still `UR-NNN` / `ur.*`). |
| **Preconditions** | `ensure_product_container` satisfied; next Issue slug (`UR-NNN`) allocatable; backend store writable. |
| **Notes** | Allocates sequential `UR-NNN` slug (machine-stable). Does not create REQs. Op name stays `create_ur` — not `create_issue`. |

#### `read_ur`

| | |
|---|---|
| **Intent** | Load the Issue brief and attached sections (ideate, clarifications, etc. if present). |
| **Preconditions** | Issue id (`UR-NNN`) known and exists. |
| **Notes** | Read-only. |

#### `list_urs`

| | |
|---|---|
| **Intent** | Enumerate Issues for prompts, status, and migration. |
| **Preconditions** | Product container ready. |
| **Notes** | May return ids + titles only; use `read_ur` for full body. |

#### `append_ideate`

| | |
|---|---|
| **Intent** | Append or write ideate content onto an existing Issue. |
| **Preconditions** | Issue exists; ideate phase allowed for that Issue. |
| **Notes** | Prefer append over overwrite of intake brief. |

#### `append_clarifications`

| | |
|---|---|
| **Intent** | Append question-phase Q&A onto the Issue. |
| **Preconditions** | Issue exists. |
| **Notes** | Does not create REQs. |

#### `create_req`

| | |
|---|---|
| **Intent** | Create one REQ in the backlog for an Issue (optionally under a path-unit parent). |
| **Preconditions** | Issue exists; capture/schema fields available; backend writable. |
| **Notes** | Starts unclaimed, backlog-equivalent status. Footprint/deps may be set at create or via `set_files` / `set_blocked_by`. |

#### `update_req`

| | |
|---|---|
| **Intent** | Edit REQ body or structured fields without changing claim/archive lifecycle. |
| **Preconditions** | REQ exists; caller is allowed to edit in the current phase (capture/audit/worker rules). |
| **Notes** | Prefer dedicated ops for status, deps, footprint, claim when those are the intent. |

#### `read_req`

| | |
|---|---|
| **Intent** | Load the full REQ (headers + body sections). |
| **Preconditions** | REQ id known; present in backlog, in-flight, or archive store. |
| **Notes** | Read-only. |

#### `list_reqs_for_ur`

| | |
|---|---|
| **Intent** | List all REQs for a UR in any status. |
| **Preconditions** | UR exists (or UR id known). |
| **Notes** | Scope is the UR’s project/container; not global product backlog unless caller expands. |

#### `list_claimable_reqs`

| | |
|---|---|
| **Intent** | Return REQs that are backlog, deps-satisfied, footprint-free, and unclaimed — in pick order. |
| **Preconditions** | Backend readable; claim/deps/footprint rules evaluable. |
| **Notes** | Uses **authoritative** deps (relations on Linear). Does not claim. Empty list is valid. |

#### `claim_req`

| | |
|---|---|
| **Intent** | Optimistically claim a REQ and move it to in-progress. |
| **Preconditions** | REQ appears claimable under **Claim / deps / footprint** rules at re-read time; agent id available. |
| **Notes** | Re-read before write; loser → concurrent-conflict / stop; resume allowed. On Linear, human assignee is not stolen for claim. |

#### `heartbeat_req`

| | |
|---|---|
| **Intent** | Refresh liveness on an active claim so siblings do not treat the slot as stale. |
| **Preconditions** | REQ is claimed by this agent (or caller is the claim owner); claim still active. |
| **Notes** | Filesystem-only / comment-only — no git commit for stamps. |

#### `set_req_status`

| | |
|---|---|
| **Intent** | Set workflow status (e.g. stopped, in-progress) without full archive. |
| **Preconditions** | REQ exists; target status is valid for the backend `status_map` / schema. |
| **Notes** | Archive/done should use `archive_req`. Unclaim/backlog return should use `unblock_req` when clearing a claim. |

#### `set_blocked_by`

| | |
|---|---|
| **Intent** | Write the depends-on graph for a REQ. |
| **Preconditions** | REQ exists; dependency ids valid (or empty to clear). |
| **Notes** | Updates authoritative store; on Linear with relation tools, updates **blocks relations + body mirror**. |

#### `set_files`

| | |
|---|---|
| **Intent** | Set the footprint (`**Files:**`) list for a REQ. |
| **Preconditions** | REQ exists. |
| **Notes** | Does not claim. Overlap is evaluated by consumers at pick/claim time. |

#### `archive_req`

| | |
|---|---|
| **Intent** | Mark REQ done with closure proof and outputs; move to archive-equivalent store. |
| **Preconditions** | Acceptance / verification evidence complete per run-worker rules; claim owned by orchestrating flow as required by backend. |
| **Notes** | Releases in-flight footprint. Does not delete historical data. |

#### `unblock_req`

| | |
|---|---|
| **Intent** | Return a REQ to backlog and clear/release the claim. |
| **Preconditions** | REQ is in-flight or stopped with a claim (or explicitly targeted by unblock). |
| **Notes** | Used after mid-flight failure recovery and operator-driven unblock. |

#### `append_decision`

| | |
|---|---|
| **Intent** | Append one standing decision line to decisions memory. |
| **Preconditions** | Decisions store reachable (markdown file or Linear team Doc). |
| **Notes** | Append-only; readers treat lines as constraints. |

#### `write_verify_report`

| | |
|---|---|
| **Intent** | Persist verify-phase output for an Issue. |
| **Preconditions** | Issue exists; verify phase has produced a report. |
| **Notes** | Backend chooses home (Issue tree vs Initiative section/comment). |

#### `write_close_report`

| | |
|---|---|
| **Intent** | Persist close-phase output for an Issue. |
| **Preconditions** | Issue exists; close phase has produced a report. |
| **Notes** | Backend chooses home (Issue tree vs Initiative section/comment). |

#### `append_run_note`

| | |
|---|---|
| **Intent** | Append a ledger-ish / cost / run note for a REQ or run. |
| **Preconditions** | Target REQ or run context exists when required. |
| **Notes** | Authoritative work-item note is backend store; optional local ledger file is telemetry only when `ledger.enabled`. |

#### `read_active_milestone`

| | |
|---|---|
| **Intent** | Read the active milestone cursor (if any). |
| **Preconditions** | None beyond readable state; missing cursor means not in milestone mode. |
| **Notes** | Content is work-item-ish; representation may be local file or Project description marker. |

#### `set_active_milestone`

| | |
|---|---|
| **Intent** | Set or advance the active milestone cursor. |
| **Preconditions** | Milestone mode applicable; target milestone id valid. |
| **Notes** | Deploy-gate human y/n remains orchestrator-owned; this op only persists the cursor. |

#### `list_milestone_reqs`

| | |
|---|---|
| **Intent** | List REQs belonging to the active (or named) milestone. |
| **Preconditions** | Milestone id known or active cursor set. |
| **Notes** | Used by run loop and milestone-complete detection. |

#### `write_gate_state`

| | |
|---|---|
| **Intent** | Coordinate deploy-gate ownership / state. |
| **Preconditions** | Milestone / gate flow active. |
| **Notes** | **Local lock still allowed** (e.g. `state/gate-owner.md`) even when work-items are remote. Not a dual-write of work items. |

#### `migrate_markdown_to_linear`

| | |
|---|---|
| **Intent** | One-shot, idle-only cutover from the markdown work-item store to Linear (design §12). Creates Initiatives / Projects / Issues for existing URs and REQs (backlog + archive), Team Docs for decisions/calibration, then flips `tracker.backend` to `linear`. After cutover, local UR/REQ trees are **read-only historical** — not dual-write. |
| **Preconditions** | Effective backend is still **`markdown`** (cutover target is Linear). **`working/` empty.** No active claims. Operator confirms (or explicit dry-run). Linear team resolvable and MCP usable **before** any write. Surfaced via `/do-work upgrade migrate` (or upgrade migrate step) — see `agents/upgrade.md` + `agents/tracker/linear.md`. |
| **Notes** | **Not a normal lifecycle op.** Sequences and dry-run live in `linear.md`. **Refuse entirely** if effective backend is already **`sqlite`**, **`linear`**, or **`do-work-io`** — leave config + store unchanged (no partial cutover; there is no markdown→sqlite migrate in v1). **Refuse entirely** if `working/` non-empty or active claims exist — leave config + markdown trees unchanged (no partial cutover). **Hard-stop** if Linear MCP is unusable mid-migration — leave markdown trees + config backend unchanged (no partial cutover). Supports **dry-run** (report planned creates; zero Linear writes; config untouched). |

---

## Shared rules (backend-independent summary)

- **No dual-write.** One active backend owns work-item truth. Markdown, Linear, and sqlite do not mirror each other as a second source of truth.
- **Port-only storage API.** Phase agents call named ops only — never raw `.do-work/REQ-*` paths, raw Linear tools, or freehand SQL outside the backend file.
- **Claim eligibility** requires deps satisfied + footprint free + unclaimed (or stale claim recoverable per multi-agent rules).
- **Optimistic claim:** re-read before write; loser stops with concurrent-conflict / resume allowed.
- **Footprint** is structured `**Files:**` (and related headers) on the REQ — not ad-hoc custom fields.
- **Deps authority:** Linear native **blocks relations** are authoritative for eligibility; body `**Depends on:**` is mirror. Markdown file header is the store. SQLite deps live in the DB via `dw-db` (see `sqlite.md`).
- **Hard-stop on unusable active backend** (see **Hard-stop matrix**) — **never silent fallback** to another backend.
- **Mid-flight failure:** **leave claimed** on all backends; resume/unblock repair after recovery.
- **Work-item vs runtime:** work-item data through port ops; git/worktrees/`state/*`/config/gate locks stay local.
- **Idle markdown→Linear migration (design §12 / `migrate_markdown_to_linear`):** only when effective backend is still **`markdown`**, idle (`working/` empty, no active claims) + operator confirm (or dry-run). **Refuse** when already `sqlite`, `linear`, or `do-work-io`. No partial cutover: refuse preflight or hard-stop MCP failure leaves `tracker.backend` and markdown trees unchanged. After successful cutover, ops **stop reading** local `user-requests/` and `archive/` as the work-item store (historical read-only only). No markdown→sqlite migrate in v1.

---

## Regression (markdown-default terminal)

When `tracker.backend` resolves to `markdown`:

- Existing `lib/*.sh` coordination remains the implementation surface.
- `bash lib/tests/run-all.sh` and `bash lib/conformance-scan.sh` remain the regression gates.
- No Linear MCP discovery, team resolution, or credentials are required.
- Agents must not invent Linear tools or dual-write “for safety.”

---

## Out of scope for this file

- Concrete Linear MCP / skill tool call sequences (including **`migrate_markdown_to_linear`** agent sequence + dry-run report format) → `agents/tracker/linear.md`.
- Concrete `lib/*.sh` step lists → `agents/tracker/markdown.md`.
- Upgrade/conformance UX that surfaces the migrate step → `agents/upgrade.md`.
- Config key schema → `agents/config.md`.
- Changing TDD, worktree isolation, or review philosophy — store contract only.
