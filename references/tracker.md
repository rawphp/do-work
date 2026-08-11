# Tracker backends (work-item store)

Deep dive for multi-tracker configuration. Hard-stop and dual-write rules are summarized in `SKILL.md` (always loaded). Canonical contracts: [agents/tracker/port.md](../agents/tracker/port.md), [agents/config.md](../agents/config.md). Runtime sequences: [agents/tracker/markdown.md](../agents/tracker/markdown.md), [agents/tracker/linear.md](../agents/tracker/linear.md), [agents/tracker/sqlite.md](../agents/tracker/sqlite.md).

Work items (URs, REQs, decisions, verify/close reports, run notes) are stored through a **tracker port**. Config key `tracker.backend` selects the implementation:

| `tracker.backend` | Behavior |
|-------------------|----------|
| **unset / empty / missing** | Treat as **`markdown`** — no hard-stop, no Linear tools, no `sqlite3` required |
| **`markdown`** | Default: local `.do-work/` files + `lib/*.sh` (behavior matches today) |
| **`linear`** | Linear is the sole work-item store (no dual-write; hard-stop if Linear unusable) |
| **`sqlite`** | `.do-work/work.db` is the sole work-item store via `lib/dw-db.sh` (no dual-write; hard-stop if sqlite unusable; greenfield empty DB on switch) |

**Load path** for every phase agent that touches work items: (1) load config (`agents/config.md`), (2) resolve `tracker.backend` (default **`markdown`** if missing/empty), (3) read `agents/tracker/port.md`, (4) read `agents/tracker/<backend>.md`, (5) call only named port ops for storage. Runtime/git (worktrees, merges, state locks, `config.yml`) stay local on every backend. Markdown remains the default; existing tests and conformance do not require Linear or sqlite.

**Hard-stop (no silent fallback):** when the **active** backend is unusable, agents **hard-stop** with setup instructions — they never fall through to another backend:

| Backend | Hard-stop when |
|---------|----------------|
| **linear** | MCP missing/unauthenticated, team unresolved, missing `status_map` state, or `agents/tracker/linear.md` missing/unreadable |
| **sqlite** | `sqlite3` missing from PATH, `agents/tracker/sqlite.md` missing/unreadable, DB corrupt / bad `user_version` after ensure |
| **any** | Unknown `tracker.backend` string |

Canonical contract: `agents/tracker/port.md` + Load Config steps 6–7 / **7b** in `agents/config.md`.

**`tracker.linear.*` (when `backend: linear`).** Full schema and defaults live in `agents/config.md` (canonical template + schema reference). Summary:

| Key area | Defaults / rules |
|----------|------------------|
| Team | `team_id` and/or `team_key` — **hard-fail** if neither resolves |
| MCP | Linear MCP tools must be discoverable — **hard-fail** with skill setup instructions if not |
| Hierarchy | **UR = Project Milestone** on shared product Project per local product; REQs = Issues with that milestone. Not Initiatives (MCP has no Initiative create tools). |
| `product_project` | Shared Linear Project (**name or UUID**) for all URs on this local product — **default empty** (not skill name `do-work`). Resolve: explicit `product_project` → `project.name` → git-root basename; `ensure_product_container` create-if-missing + **always persist UUID**. Example for this skill repo only: name `do-work`. |
| `ur_milestone_name_pattern` | Default `{ur_id}: {title}` |
| `status_map` | `backlog→Todo`, `in_progress→In Progress`, `stopped→Canceled`, `done→Done` — **hard-fail** if a mapped state is missing on the team (rename team state or override the map key) |
| Labels | `Layer/`, `path-unit`, `Size/` prefixes |
| Claim | `agent_claim_marker: "<!-- do-work-claim -->"`; heartbeat age defaults to `parallel.stale_threshold_seconds` when `heartbeat_max_age_seconds` is null |
| Docs | Team Docs `do-work/decisions` and `do-work/calibration` |

`ledger`, `parallel`, `delivery`, `review`, and `layers` remain valid under Linear. Authoritative run notes are Linear Issue comments; local `.do-work/runs/` is optional telemetry when `ledger.enabled: true`.

**`tracker.sqlite.*` (when `backend: sqlite`).** Full schema and defaults live in `agents/config.md`. Summary:

| Key | Default | Rules |
|-----|---------|-------|
| `tracker.sqlite.path` | `""` → `{project}/.do-work/work.db` | Sole work-item DB path; gitignored binary (`work.db` + WAL sidecars) |
| `tracker.sqlite.board_path` | `""` → `{project}/.do-work/board/index.html` | Static HTML snapshot for `/do-work board` (sqlite-only; regenerate on demand) |
| `tracker.sqlite.busy_timeout_ms` | `5000` | SQLite `busy_timeout` for `lib/dw-db.sh` opens |

**SQLite rules:** greenfield empty DB on switch (no markdown/Linear history import); agents use `lib/dw-db.sh` only (no freehand `sqlite3` work-item SQL); `/do-work upgrade migrate` **refuses** under sqlite (`refused-sqlite-backend`); missing `user-requests/` / backlog `REQ-*.md` trees are **not** conformance drift when backend is sqlite.

**No dual-write.** With `tracker.backend: linear` **or** `sqlite`, that backend is the **only** work-item store. Agents must not mirror URs/REQs into another store as a second source of truth, and must not fall back when the active backend fails (hard-stop instead). After idle markdown→Linear migration (`/do-work upgrade migrate`), historical `.do-work/user-requests/` and `archive/` trees remain on disk as **read-only history** — work-item ops ignore them.

**Linear commit / branch convention** (when `backend: linear`):

```
feat(ENG-123): short title

Issue: ENG-123
UR: UR-007
Output: path/to/primary/output
```

- Subject uses the **Linear issue id** only (e.g. `ENG-123`) — not `REQ-NNN`.
- Footer: `Issue:` + id; `UR:` when known; `Output:` primary path. No `.do-work/archive/REQ-…` path required.
- Feature branch / worktree: `req/<sanitized-linear-id>` (e.g. `req/ENG-123`); worktree dir hard-defaults to lowercase (`req-eng-123`). See `agents/run-worker.md` W2 / design §6.5.

**SQLite commit / branch convention** (when `backend: sqlite`): same shape as markdown — `feat(REQ-NNN): …`, footer `REQ:` / `UR:` / `Output:`, worktree `req/REQ-NNN`. Ids remain `UR-NNN` / `REQ-NNN` rows in `work.db`.

**Human assignee + agent claim comments (operator warning):** under Linear, the **human** remains the Issue assignee; agents claim via workflow state + a claim-protocol comment (`tracker.linear.agent_claim_marker`, default `<!-- do-work-claim -->`) with `agent_id`, timestamps, and `status: active`. **Do not clear, edit, or delete agent claim comments in the Linear UI while a `/do-work run` is live** — that breaks multi-agent claim/heartbeat and can strand or double-claim work. Recover stuck claims with `/do-work status`, then `/do-work resume` or `/do-work unblock` after the run is idle or the agent has stopped. Mid-flight Linear MCP failure leaves the claim active; resume/unblock after MCP recovers.

**Markdown remains the default.** Unset/empty `tracker.backend` → `markdown`. No Linear MCP or `sqlite3` required for the happy path. Operator setup: Linear — [docs/troubleshooting.md](../docs/troubleshooting.md) § Linear tracker backend; SQLite — same file § SQLite tracker backend; deep dive [docs/HOW-IT-WORKS.md](../docs/HOW-IT-WORKS.md) § Multi-tracker; first-run pointer [docs/getting-started.md](../docs/getting-started.md). Full sequences: `agents/tracker/linear.md`, `agents/tracker/sqlite.md`.
