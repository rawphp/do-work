# Design: Do-work SQLite tracker backend + local HTML board

**Date:** 2026-08-11  
**Status:** amended after validation — re-approve before writing-plans  
**Source:** brainstorming session + validation blockers/majors amendment  
**Supersedes / extends:** third local backend after markdown + Linear (see multi-tracker design). Does not implement GitHub.

## 1. Problem

do-work’s default **markdown** work-item store becomes unwieldy at scale: hundreds of peer UR/REQ documents, expensive for agents to glob/read and hard for operators to see “what’s going on.”

**Linear** as an optional sole store works for product boards but the current hierarchy (UR = Project Milestone stuffing brief/ideate/verify/close) floods project chrome and raises agent read/write cost. Fixing Linear hierarchy is a separate effort.

**GitHub Issues** map structurally to parent/sub-issue work, but are a poor high-churn agent coordination bus under global agent API pressure and secondary rate limits.

Operators want:

1. **Local** sole store that is structured (not file sprawl)
2. **Human visibility** without opening a database or hundreds of files
3. **Shared integration** with existing backends (one port)
4. **Remote glance** optional later — **out of v1**

## 2. Goals

1. **New opt-in backend `sqlite`** — when `tracker.backend: sqlite`, work items live **only** in `{project}/.do-work/work.db` (no dual-write to markdown or Linear).
2. **Markdown remains the default** — unset/empty `tracker.backend` → `markdown`; existing projects and tests unchanged until operators opt in.
3. **Common integration** — markdown, Linear, and sqlite share the same tracker port: load path, op catalog, claim/deps/footprint semantics, hard-stop rules. Backends differ only in representation.
4. **Local visibility** — `/do-work board` writes a **static HTML snapshot** operators open in a browser.
5. **Greenfield from switch** — switching to sqlite starts empty; **no migration** of historical markdown/Linear work items in v1.
6. **No split-brain** — load path, phase agents, and lib CLI all accept `sqlite` and never glob markdown REQ trees when backend is sqlite.

### Done when

- Config + `port.md` accept `sqlite`; unknown backends still hard-stop.
- With `tracker.backend: sqlite`, every phase agent that touches work items has an explicit **1S** (sqlite) path or port-op-only path — no FS globs of `REQ-*` / `user-requests/` as live truth.
- Full core loop against `work.db`: intake → ideate → capture → verify → run (claim/deps/footprint) → status / close.
- `/do-work board` produces escaped HTML from DB (explicit regen only); fails clearly on non-sqlite.
- Default markdown path still passes existing regression without requiring sqlite.
- Every port op name has a frozen home in §7 (SQL or local runtime file).
- Lib CLI surface (§5.5) implements coordination parity listed there.

## 3. Non-goals

- Markdown ↔ sqlite migration / import (not required; not default)
- Linear ↔ sqlite migration
- Fixing Linear hierarchy (UR = parent Issue, etc.)
- GitHub Issues backend
- Remote mirror / glance (Linear or GitHub)
- Live localhost board server or edit-in-browser
- Dual-write any backend pair
- Changing TDD-per-REQ, worktree isolation, or post-build review philosophy
- Replacing markdown as the default backend
- True distributed multi-host locking beyond single-machine SQLite transactions
- `migrate_markdown_to_sqlite` port op in v1

## 4. Decisions (locked)

| Decision | Choice |
|----------|--------|
| Approach | **A:** SQLite sole store + static HTML board |
| Backend name | `tracker.backend: sqlite` |
| Default backend | Still **markdown** (opt-in sqlite) |
| Integration | **One port** — `port.md` + `agents/tracker/{markdown,linear,sqlite}.md` |
| Store path | `{project}/.do-work/work.db` (configurable) |
| Migration | **None in v1** — empty DB from switch forward |
| Board | Static HTML; **`/do-work board` only** |
| Board scope | **sqlite only** in v1 |
| Remote | Deferred |
| External ids | **Slugs only** (`UR-NNN`, `REQ-NNN`) at agent/CLI/commit surface; integer PKs internal |
| REQ body | **Single `body` markdown** with fixed section headings (parity with capture template) |
| Claim atomicity | SQLite **transaction** + unique active claim constraint |
| Coordination surface | **Single CLI** `lib/dw-db.sh` (or `lib/dw-db`) — not freehand SQL in agents |
| Runtime dependency | **`sqlite3` CLI** on PATH (system SQLite) — no Python/Node required for v1 store ops |
| Git | **`work.db` and `board/` gitignored** by default (local-only) |
| Dual-write | **Never** while backend is sqlite |
| Unusable DB | **Hard-stop** — never silent markdown or Linear fallback |
| Runtime / git | worktrees, merges, `state/*` locks, config, optional ledger telemetry stay local |

---

## 5. Architecture

### 5.1 Layout

```
.do-work/
  config.yml
  work.db                 # sole work-item store when backend=sqlite (gitignored)
  board/index.html        # static snapshot (gitignored)
  state/                  # runtime locks (gate-owner, etc.) — unchanged
  runs/                   # optional ledger telemetry — unchanged
  # user-requests/, REQ-*.md, working/, archive/ — NOT live truth when backend=sqlite
```

**VCS policy (locked):**

| Path | Git |
|------|-----|
| `.do-work/work.db` | **gitignore** (binary, machine-local) |
| `.do-work/work.db-*` (WAL/SHM) | **gitignore** |
| `.do-work/board/` | **gitignore** (regenerable snapshot) |
| `.do-work/config.yml` | tracked as today |
| `.do-work/state/` | as today (project convention) |

Install/upgrade templates add these ignore rules when missing.

### 5.2 Load path (three backends — B1)

**Resolve `tracker.backend` (config Load Config + `port.md` — must be edited):**

| Stored value | Effective backend |
|--------------|-------------------|
| missing / null / empty / whitespace | `markdown` |
| `markdown` | `markdown` |
| `linear` | `linear` |
| `sqlite` | `sqlite` |
| anything else | **hard-stop** unknown backend (do not guess) |

**Then:**

1. Read `agents/tracker/port.md`
2. Read `agents/tracker/<backend>.md` — if missing/unreadable → **hard-stop** (never fall through to another backend)
3. Work-item ops: **only** named port ops for that backend

### 5.3 Hard-stop matrix (generalized — B1)

| Condition | markdown | linear | sqlite |
|-----------|----------|--------|--------|
| Backend doc missing | n/a (default file always present) | hard-stop | hard-stop |
| MCP / team / status_map fail | n/a | hard-stop | n/a |
| DB corrupt / unreadable | n/a | n/a | hard-stop |
| Schema version unsupported | n/a | n/a | hard-stop |
| Lock timeout after retries | n/a | n/a | hard-stop or concurrent-conflict (claim races) |
| Mid-flight after successful claim | leave claimed | leave claimed | leave claimed (active claims row) |
| Fallback to another backend | never | never | never |

`port.md` must stop describing hard-stop as **Linear-only**. Shared rule: **unusable active backend → hard-stop; never silent fallback.**

### 5.4 Work-item vs runtime

| In `work.db` (sqlite mode) | Always local runtime (not port sole-store) |
|----------------------------|--------------------------------------------|
| URs, REQs, deps, claims, ideate/verify/close artifacts, **decisions**, **calibration**, **milestone cursor**, run notes | worktrees, git, `state/*` locks (incl. **gate-owner**), `config.yml`, optional `runs/` telemetry |

**Intentional divergence from markdown file homes:** under sqlite, decisions / calibration / milestone cursor live in the **DB** (sole store), not `.do-work/decisions.md` / `state/calibration.md` / `state/active-milestone.md`. Under markdown those files remain. Under Linear, Team Docs / milestone description remain as today.

**`write_gate_state`:** always **local** `.do-work/state/gate-owner.md` (all backends) — not in `work.db`.

### 5.5 Coordination surface: `lib/dw-db` CLI (B3)

**Locked:** one entrypoint — **`lib/dw-db.sh`** (bash wrapper invoking `sqlite3`). Agents and phase docs call this CLI; they **must not** invent ad-hoc `sqlite3` one-liners or freehand SQL for claim/pick/deps.

#### Runtime dependency

- **`sqlite3`** must be on `PATH` when `backend: sqlite`.
- Missing `sqlite3` → hard-stop with install hint (`brew install sqlite` / distro package).
- No Python/Node/ORM required for v1 store ops.
- Board generator: same stack (bash + sqlite3 + HTML emit) preferred for zero new runtime.

#### Concurrency knobs (locked)

| Setting | Value |
|---------|--------|
| `journal_mode` | **WAL** |
| `busy_timeout` | **5000** ms |
| Transient lock retry | up to **3** attempts, backoff **50ms / 100ms / 200ms** |
| After retries | claim ops → `concurrent-conflict` or hard-stop; other writes → hard-stop |

#### CLI command parity (vs markdown `lib/*.sh`)

| Concern | Markdown today | sqlite CLI (`dw-db`) |
|---------|----------------|----------------------|
| Pick claimable | `pick-req.sh` | `dw-db pick [--ur UR-NNN] [--agent ID]` |
| Claim | `claim-req.sh` | `dw-db claim <REQ-NNN> <agent_id>` |
| Heartbeat | `heartbeat.sh` | `dw-db heartbeat <REQ-NNN> <agent_id>` |
| Deps check | `check-deps.sh` | `dw-db check-deps <REQ-NNN>` |
| Footprint check | `check-footprint.sh` | `dw-db check-footprint <REQ-NNN>` |
| Scan stale | `scan-stale.sh` | `dw-db scan-stale` |
| Archive integrity | `check-archive-integrity.sh` | `dw-db check-archive <REQ-NNN>` |
| Status synth | `synth-status.sh` | `dw-db status-synth [--ur UR-NNN]` |
| Cycle / deadlock helpers | `cycle-check.sh`, `deadlock-check.sh` | `dw-db cycle-check`, `dw-db deadlock-check` (same semantics over SQL graph) |
| Ensure schema / open | mkdir layout | `dw-db ensure` |
| Board | n/a | `dw-db board` (or board calls query subcommands) |

**Agent-playbook ops (no dedicated markdown lib today; same under sqlite — CLI subcommands still preferred for atomic writes):**

| Port op | sqlite implementation |
|---------|------------------------|
| `create_ur`, `create_req`, `update_req`, `set_*`, append artifacts, archive body fields | `dw-db <subcommand>` with transactional SQL |
| `read_ur` / `read_req` / lists | `dw-db get-*` / `list-*` |
| `write_gate_state` | still write **local** `state/gate-owner.md` (not dw-db work-item) |

Markdown `lib/pick-req.sh` etc. remain **markdown-only**. Do not teach them to open `work.db`.

### 5.6 Phase-agent branch inventory (B2)

**Mandate:** when `backend: sqlite`, phase agents **must not** use live paths:

- `.do-work/REQ-*.md`, `working/REQ-*.md`, `archive/REQ-*.md`
- `.do-work/user-requests/UR-*/`
- `.do-work/decisions.md`, `state/calibration.md`, `state/active-milestone.md` as work-item store

Use **port ops + `dw-db`** only (mirror Linear’s **1L** pattern → **1S**).

| Agent | Today | Required for sqlite |
|-------|--------|---------------------|
| `config.md` | resolve markdown\|linear only | Accept `sqlite`; validate/ensure DB step; hard-stop matrix |
| `intake.md` / `start.md` | FS UR dir vs Linear milestone | **1S:** `create_ur` via dw-db |
| `ideate.md` | `ideate.md` file vs Linear | **1S:** `append_ideate` |
| `question.md` | clarifications in input.md | **1S:** `append_clarifications` |
| `capture.md` / `audit.md` | REQ files | **1S:** `create_req` / `update_req` / `list_reqs_for_ur` |
| `verify.md` | score + console | **1S:** `write_verify_report` + list/read ops |
| `run.md` | pick/claim scripts + working/ | **1S:** dw-db pick/claim/…; no FS claim |
| `run-worker.md` | read REQ file path | **1S:** `read_req` by slug; heartbeat via dw-db |
| `review.md` | working/ path vs Linear id | **1S:** `read_req` by slug |
| `status.md` | synth-status.sh or 1L | **1S:** `dw-db status-synth` (not board-only) |
| `resume.md` / `unblock.md` | working/REQ | **1S:** `set_req_status` / `unblock_req` / claim ops by slug |
| `close.md` | closure.md path | **1S:** `write_close_report` + list path-units from DB |
| `retro.md` | local runs + calibration file | **1S:** read run_notes + write calibration row; local runs telemetry optional |
| `log.md` | ledger / archive | Port-aware; no markdown-only REQ scans when sqlite |
| `upgrade.md` | migrate to Linear | Refuse Linear migrate when backend is sqlite; no sqlite migrate |
| `go.md` / `help.md` | docs | Document sqlite + board command |
| `tracker/port.md` | two backends | Three backends + generalized hard-stop |

Primary silent-failure mode to prevent: **phase agent still globs `.do-work/REQ-*` while backend is sqlite.**

---

## 6. Data model

Single file DB. **Schema version:** `PRAGMA user_version = 1` at init. Migration runner lives in `dw-db ensure` / `lib/sqlite-schema.sql` applied by ensure. Unsupported `user_version` → hard-stop with message: current version, supported version, recreate empty DB option (no auto-migrate from foreign schemas).

### 6.1 Tables

**`urs`**

| Column | Notes |
|--------|--------|
| `id` | Integer PK (internal only) |
| `slug` | `UR-NNN` **UNIQUE** — external id |
| `title` | short |
| `class` | feature / … |
| `brief` | verbatim intake |
| `created_at` | ISO |
| `closed_at` | null until closed |

**`ur_artifacts`** — UNIQUE(`ur_id`, `kind`)

| kind | Write semantics |
|------|-----------------|
| `ideate` | **append** (concat with separator); never touch `urs.brief` |
| `clarifications` | **append** Q/A blocks |
| `open_gaps` | replace or append per capture (default **replace** section body) |
| `capture_summary` | **replace** |
| `verify` | **replace** full report body |
| `close` | **replace** full closure body |

**`reqs`**

| Column | Notes |
|--------|--------|
| `id` | Integer PK internal |
| `slug` | `REQ-NNN` **UNIQUE** — external id |
| `ur_id` | FK |
| `title` | |
| `status` | `backlog` \| `in_progress` \| `stopped` \| `done` |
| `layer` | |
| `parent_req_id` | nullable FK internal id of path-unit parent |
| `entry_point` / `terminal_state` | path-unit parents |
| `path_milestone` | `M1` / null (no `REQ-M*-` filenames) |
| `files` | footprint text |
| `size` | S\|M\|L |
| `priority` | integer; **missing/null → treat as 2** at pick |
| `criteria_approved` | |
| `closure_proof` / `suite` | |
| `body` | **single markdown** with frozen headings (below) |
| `created_at` / `updated_at` | |

**Frozen `body` template sections (in order):**

```markdown
## Task
## Acceptance Criteria
## Verification Steps
## Integration
## Manual checks (advisory)
## Outputs
```

**`deps`** — (`req_id`, `depends_on_req_id`) PK; authoritative eligibility graph.

**`claims`**

| Column | Notes |
|--------|--------|
| `id` | Integer PK |
| `req_id` | FK |
| `agent_id` | |
| `claimed_at` / `heartbeat` | ISO |
| `session` | optional |
| `status` | `active` \| `released` |

**Constraint (locked):** at most **one** row with `status = 'active'` per `req_id` — implement via partial unique index:

```sql
CREATE UNIQUE INDEX claims_one_active_per_req
  ON claims(req_id) WHERE status = 'active';
```

**`decisions`** — append-only lines (`id`, `line`, `created_at`)

**`calibration`** — single-row table (id=1) full body; retro **replace**

**`milestone_state`** — `ur_id` UNIQUE, `active` (`M1` or null), `checklist_json`

**`run_notes`** — `id`, `req_id`, `payload` (YAML/JSON text), `created_at`

### 6.2 Identifiers and commits

External API (CLI args, agent prompts, commits): **slugs only**.

```
feat(REQ-NNN): short title

REQ: REQ-NNN
UR: UR-007
Output: path/to/primary/output
```

Branch/worktree: `req/REQ-NNN`.

### 6.3 Slug allocation (B4)

Under concurrent intake/capture, allocate inside a transaction:

1. `BEGIN IMMEDIATE`
2. `SELECT MAX(slug)` / parse numeric suffix for `UR-%` or `REQ-%`
3. Next zero-padded `NNN`
4. INSERT
5. COMMIT

Never allocate outside a transaction.

---

## 7. Full port-op → home map (B5)

| Port op | sqlite home | Notes |
|---------|-------------|--------|
| `ensure_product_container` | create dirs + `dw-db ensure` | empty schema if missing |
| `create_ur` | INSERT `urs` | brief only; no artifacts yet |
| `read_ur` | SELECT `urs` + optional `ur_artifacts` | |
| `list_urs` | SELECT slug, title, … | slim |
| `append_ideate` | upsert `ur_artifacts` kind=ideate **append** | never modify brief |
| `append_clarifications` | kind=clarifications **append** | |
| `create_req` | INSERT `reqs` + optional `deps` | status=backlog |
| `update_req` | UPDATE `reqs` | not claim/archive |
| `read_req` | SELECT by **slug** | |
| `list_reqs_for_ur` | JOIN by ur slug | any status |
| `list_claimable_reqs` | pick SQL (§8) | |
| `claim_req` | transaction status+claims | |
| `heartbeat_req` | **UPDATE** active claim row only | no new active row |
| `set_req_status` | UPDATE status | stopped keeps active claim |
| `set_blocked_by` | replace `deps` rows | |
| `set_files` | UPDATE `files` | |
| `archive_req` | proof + done + release claim | |
| `unblock_req` | backlog + release claim | |
| `append_decision` | INSERT `decisions` | append-only |
| `write_verify_report` | `ur_artifacts` kind=verify **replace** | |
| `write_close_report` | kind=close **replace** | |
| `append_run_note` | INSERT `run_notes` | authoritative; local `runs/` telemetry optional if ledger on |
| `read_active_milestone` | `milestone_state` | |
| `set_active_milestone` | upsert `milestone_state` | |
| `list_milestone_reqs` | `reqs.path_milestone = active` | |
| `write_gate_state` | **local** `state/gate-owner.md` only | not DB |
| `migrate_markdown_to_linear` | **refuse** if backend is sqlite | also refuse if operator is “on sqlite”; no sqlite migrate op |

**Calibration** (not a named port op today): document in `sqlite.md` like Linear Docs — retro full-replace `calibration` row; capture read advisory.

**Board** is not a port op — `dw-db board` / `/do-work board`.

---

## 8. Claim, pick, footprint, milestone (B4 + majors)

### 8.1 Pick order (locked — markdown parity)

Among claimable candidates:

1. **Priority DESC** (null/missing → **2**)
2. **Numeric REQ slug ASC** (parse `REQ-NNN`)
3. Tie-break: `created_at` ASC, then slug ASC

### 8.2 Claimable predicate

All of:

1. `status = backlog`
2. No **fresh** active claim (or stale-active eligible for takeover per policy)
3. Every dep in `deps` has `status = done`
4. Footprint free vs in-flight set
5. Scope: optional UR filter; if path-milestone active for that UR → only `path_milestone = active` (or nulls excluded — **parity: only matching M**)

### 8.3 Stale / takeover

| Situation | Behavior |
|-----------|----------|
| Active claim, heartbeat age ≤ stale_max | foreign claim → **concurrent-conflict** |
| Active claim, heartbeat age > stale_max | **stale** — eligible for reclaim by new `claim_req` (same transaction: release or replace active row under unique index) |
| Own active claim | claim_req idempotent / heartbeat |
| Mid-flight crash | row stays `active`; **leave claimed**; resume/unblock |

`stale_max` = `parallel.stale_threshold_seconds` (default 900). Optional future `tracker.sqlite.heartbeat_max_age_seconds`; v1 uses parallel key only.

### 8.4 Heartbeat

`UPDATE claims SET heartbeat = ? WHERE req_id = ? AND status = 'active' AND agent_id = ?`  
Zero rows → error (not claim owner / not claimed). **Do not INSERT** a second active claim.

### 8.5 Footprint (major 6)

Parity with `check-footprint.sh` / Linear algorithm:

- Tokenize `files` on **whitespace** (and commas treated as separators)
- Empty/missing → free
- Expand globs against **local project tree** (nullglob: unmatched patterns contribute nothing)
- In-flight peers: `status IN (in_progress, stopped)` **and** active claim (fresh or stale-not-yet-unblocked)
- Non-empty path intersection → `overlap:<slug>`

### 8.6 Deps tokens

`set_blocked_by` accepts REQ slugs (comma and/or whitespace separated). Store as FK rows. Display mirror optional in body not required if deps table is sole authority (sqlite: table is authority; no second body mirror required).

### 8.7 Path-milestone pick filter (major 5)

When `milestone_state.active` is `M<n>` for the scoped UR (or global active if product has one cursor per UR):

- `list_claimable_reqs` / pick only REQs with `path_milestone = 'M<n>'`
- No filename encoding

---

## 9. Config schema

```yaml
tracker:
  backend: markdown          # markdown | linear | sqlite
  sqlite:
    path: ""                 # default: .do-work/work.db
    board_path: ""           # default: .do-work/board/index.html
    busy_timeout_ms: 5000    # optional override
  linear:
    # existing — unchanged
```

Load Config when `sqlite`:

1. Resolve path; require `sqlite3` on PATH
2. `dw-db ensure` (create empty schema if missing)
3. Verify `user_version` supported
4. Skip Linear validation; skip product_project bind

---

## 10. Board (visibility)

| Item | Spec |
|------|------|
| Command | `/do-work board` → `dw-db board` |
| Output | `board_path` default `.do-work/board/index.html` |
| Regen | **Explicit only** |
| Backend | **sqlite only**; else clear error |
| Safety | **HTML-escape** all user-derived text (titles, slugs, excerpts, bodies if drilled) |
| Format | Self-contained HTML, inline CSS, no required CDN |

### Page content

Header (`generated_at`, project, backend); UR list with counts; REQ table by status; claimer + heartbeat age; stale banner.

### Status vs board

| Command | Audience |
|---------|----------|
| `/do-work status` | Terminal situation room — **all backends**; sqlite uses **`dw-db status-synth` (1S)** |
| `/do-work board` | Human HTML snapshot — sqlite only |

Done-when includes status 1S path, not board-only.

---

## 11. Switching to sqlite (no migration)

1. Set `tracker.backend: sqlite`.
2. Ensure creates empty `work.db` + schema.
3. All new work-item ops → sqlite only.
4. Markdown trees remain non-live history (not imported, not deleted).
5. Finish old work under markdown **before** switch, or re-intake under sqlite.

**Refuse:**

- `migrate_markdown_to_linear` when effective backend is already `sqlite`
- Any auto-import of markdown into sqlite in v1

---

## 12. Conformance / install / upgrade (major 7)

| Concern | Rule |
|---------|------|
| Install | Optional: add gitignore entries for `work.db` and `board/` |
| Ensure on first sqlite op | Create empty DB; do **not** require `user-requests/` or REQ files |
| Conformance | Missing markdown trees when `backend: sqlite` is **not** drift |
| Conformance | `backend: sqlite` + missing/corrupt DB → advisory or hard-stop on next op |
| Upgrade migrate Linear | Preflight: backend must be markdown; refuse if sqlite |
| Upgrade | Do not invent markdown→sqlite migrate step in v1 |

---

## 13. Error handling

| Failure | Behavior |
|---------|----------|
| Unknown backend string | hard-stop |
| `sqlite3` missing | hard-stop + install hint |
| DB missing on ensure | create empty |
| Corrupt / bad user_version | hard-stop; recreate empty option; no markdown fallback |
| busy_timeout after retries | hard-stop or concurrent-conflict |
| Claim race / unique active | concurrent-conflict |
| Mid-flight crash | leave claimed (active row) |
| Board on non-sqlite | clear error |
| Agent globs markdown REQs on sqlite | forbidden — design/test against this |

---

## 14. Testing and proof

1. Markdown regression unchanged  
2. Load path accepts `sqlite`; unknown backend still hard-stops  
3. Port parity checklist every op → §7  
4. CLI tests: ensure, slug alloc race, claim race, unique active claim, deps, footprint, pick order, stale reclaim, heartbeat update-only, archive integrity  
5. Board: fixture DB → escaped HTML; board fails when backend markdown  
6. Phase-agent wiring tests or checklist: no `REQ-*.md` glob on sqlite fixtures  
7. No migration tests  

---

## 15. Implementation phasing (for writing-plans)

1. **Load path + hard-stop** — config, port.md, SKILL (accept sqlite; three-way matrix)  
2. **Schema + `dw-db ensure`** + gitignore templates  
3. **dw-db CLI** coordination: pick, claim, heartbeat, deps, footprint, scan-stale, archive check, status-synth  
4. **UR/REQ CRUD** + slug alloc transactions  
5. **Artifacts** + decisions + calibration + milestone_state + run_notes  
6. **Phase-agent 1S branches** (inventory §5.6) — status, run, run-worker, resume, unblock, intake, capture, …  
7. **`/do-work board`** + HTML escape  
8. **Conformance/upgrade refuse rules** + docs/troubleshooting  

---

## 16. Open risks

1. **Phase agent still globs `.do-work/REQ-*`** — primary silent-markdown failure mode; 1S inventory + tests  
2. Empty start feels lossy — documented; no migrate by design  
3. Board staleness — explicit regen; show `generated_at`  
4. SQLite multi-process on one machine only — WAL + busy_timeout; not multi-host  
5. Linear hierarchy pain unchanged — separate effort  
6. Agents freehand SQL — mitigated by mandatory `dw-db` surface  

---

## 17. References

- `docs/superpowers/specs/2026-07-31-do-work-multi-tracker-design.md` — port, Linear, dual-write ban  
- `agents/tracker/port.md`, `markdown.md`, `linear.md`  
- Validation review: blockers B1–B5 + majors 1–10  
- Session: local primary, static board, no remote v1, opt-in, **no migration**  
