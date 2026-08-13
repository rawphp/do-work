# Tracker backend: do-work-io (opt-in)

Implements the tracker port (`agents/tracker/port.md`) with **do-work.io as the sole work-item store** when `tracker.backend: do-work-io`. Agent steps invoke **MCP tools on `{base_url}/mcp/{mcp_profile}`** (capability names) — never raw `/capabilities` invention outside this file, never live `REQ-*.md` / `user-requests/` trees.

**This is not the default.** When `tracker.backend` is missing, empty, or `markdown`, agents load `markdown.md` instead.

---

## When to load

After config load and backend resolution (`port.md` + Load Config **7c**):

1. Effective backend is **`do-work-io`**.
2. `tracker.dowork.base_url`, `${token_env}` PAT, and `tracker.dowork.project` (slug) are set — else **hard-stop**.
3. Read `agents/tracker/port.md`.
4. Read this file.
5. Rediscover tools (`search_tool` query `req.claim` / `project.ensure` / server `do-work`) and call **only** named port ops below.

Do **not** load this file when backend is `markdown`, `linear`, or `sqlite`.

---

## Hierarchy (authoritative)

| Entity | Home |
|--------|------|
| Product container | do-work.io `projects` row; identity = **slug**; REST id = ULID |
| UR | `user_requests` row; agent id = slug `UR-NNN` |
| REQ | `requirements` row; agent id = slug `REQ-NNN` |
| Ideate / clarifications / verify / close | `ur_artifacts` (`kind`) |
| Decisions | `decisions` (append-only) |
| Run notes | `run_notes` |
| Gate locks | **local** `{project}/.do-work/state/gate-owner.md` only |

### Hard rules

1. **No dual-write** — do not treat `REQ-*.md` / `user-requests/` / Linear / `work.db` as live truth.
2. **Slugs at the agent surface** — pass `project` (slug from `tracker.dowork.project`) plus `ur` / `req` slugs. ULIDs are accepted by the server but agents should use slugs.
3. **REQ status underscore** — `in_progress` (never store `in-progress`).
4. **URs have no status** — closure is `closed_at` from `write_close_report`.
5. **`archived` is not a status** — `req.archive` is a separate gate (`done` + `closure_proof` + all AC checked).
6. **`agent_id` is advisory** — any of the owning user's tokens may heartbeat/unblock.
7. **Rediscover tools** — `search_tool` then `use_tool` / MCP `tools/call` with the **observed** qualified name. Never hard-code a host-specific `server__tool` string.

---

## Auth + MCP mount

```text
URL:  {tracker.dowork.base_url}/mcp/{tracker.dowork.mcp_profile}
      default profile dowork.control → /mcp/dowork.control
Header: Authorization: Bearer ${tracker.dowork.token_env}
        default token_env = DOWORK_IO_PAT
```

Mint the PAT in the do-work.io web UI (verified email). **Do not paste the PAT into chat.**

Tool **name** equals the capability `name` attribute (`req.claim`, `ur.create`, …). Hosts may prefix a server qualifier; rediscover and use the observed name whose suffix is the capability.

---

## Tool rediscovery (every MCP op)

1. Call **`search_tool`** with the capability name (e.g. `req.claim`) or the server / profile (`do-work`, `dowork.control`).
2. Call **`use_tool`** (or MCP `tools/call`) only with a **qualified** name + **`input_schema`** from that search.
3. Pass arguments from the op sequence below. Always include `project: {tracker.dowork.project}` except `auth.whoami` / `project.list` / `project.ensure` (ensure uses `slug`).
4. If tools are missing, unauthenticated, or the call fails because MCP/PAT/project is unusable → **hard-stop**. **Never** fall back to markdown, Linear, or sqlite.

---

## Hard-stop template

When `tracker.backend` is **`do-work-io`**, an unusable MCP mount, PAT, project slug, or backend doc is a **hard stop**. **Never** silent-fallback to markdown, Linear, or sqlite. **Never** invent local UR/REQ files as a substitute store.

### Operator-facing message (use as template)

```text
HARD STOP: do-work-io tracker backend is configured but MCP/PAT/project is not usable.

do-work will not fall back to markdown, Linear, or sqlite work-item storage
while tracker.backend is "do-work-io".
No local REQ/UR files, Linear issues, or work.db rows were invented.

What failed: <MCP missing | unauthenticated | tools undiscoverable | PAT unset |
              base_url missing | project slug missing | project not found |
              agents/tracker/do-work-io.md missing>

Fix:

1. Export the Sanctum PAT (do not paste the token into chat):
     export ${tracker.dowork.token_env:-DOWORK_IO_PAT}='…'
   Mint a PAT in the do-work.io web UI (verified email). Profile must include
   the loop tools (default tracker.dowork.mcp_profile = dowork.control).

2. Set in .do-work/config.yml:
     tracker.backend: do-work-io
     tracker.dowork.base_url: https://<host>     # origin, no /mcp path
     tracker.dowork.token_env: DOWORK_IO_PAT     # or the env name you exported
     tracker.dowork.project: <project-slug>
     tracker.dowork.mcp_profile: dowork.control  # or dowork.read / dowork.admin

3. Point the MCP host at {base_url}/mcp/{mcp_profile} with
     Authorization: Bearer $<token_env>
   Restart / refresh MCP and verify via search_tool "req.claim".

Then re-run the phase. If a claim was already active when MCP died mid-flight,
leave it; use /do-work resume or unblock after MCP recovers (port: leave claimed).
```

### Conditions → stop (summary)

| Condition | Behavior |
|-----------|----------|
| `agents/tracker/do-work-io.md` missing or unreadable | Hard stop; restore from skill install |
| `tracker.dowork.base_url` missing / empty | Hard stop |
| `${token_env}` unset or rejected (401) | Hard stop |
| `tracker.dowork.project` missing / empty / not found | Hard stop |
| `search_tool` returns no do-work.io tools | Hard stop |
| MCP offline / unauthenticated mid-session | Hard stop; if already claimed → **leave claimed** |
| Required capability missing on the profile | Hard stop (use `dowork.control` for the loop) |

**Never** write “fall back to markdown” (or Linear / sqlite) as a recovery step.

---

## Mid-flight failure (leave claimed)

If MCP/PAT becomes unusable **after** a successful `claim_req` (`req.claim`) and **before** `archive_req` / clean `unblock_req`:

1. **Leave claimed** — do **not** call `req.unblock`, do **not** invent a local claim release, do **not** write markdown REQ files.
2. The REQ stays in-progress with the last `active_claim` / heartbeat on the server.
3. Exit stopped (`dependency-missing` / `missing-creds` / `unknown-error` as appropriate). Operator recovers with `/do-work resume` or `/do-work unblock` after MCP is healthy.
4. Heartbeats under this backend use **`heartbeat_req` → `req.heartbeat`** (not `lib/heartbeat.sh` on a local working/ file).

---

## Port op index → MCP tool

Tool **name** = capability name. Every call includes `project: {tracker.dowork.project}` except `auth.whoami` / `project.list` / `project.ensure`.

| Port op | MCP tool | Arguments (conceptual) |
|---------|----------|------------------------|
| `ensure_product_container` | `project.ensure` | `{ slug: tracker.dowork.project, name?: project.name \|\| slug }` — create-or-return |
| `create_ur` | `ur.create` | `{ project, title, brief }` → `data.slug` is `UR-NNN` |
| `read_ur` | `ur.get` | `{ project, ur: UR-NNN }` |
| `list_urs` | `ur.list` | `{ project }` |
| `append_ideate` | `ur.append-ideate` | `{ project, ur, body }` — append; never overwrite brief |
| `append_clarifications` | `ur.append-clarifications` | `{ project, ur, body }` |
| `create_req` | `req.create` | `{ project, ur, title, files?, ... }` → `data.slug` is `REQ-NNN` |
| `update_req` | `req.update` | `{ project, req, ... }` — not for claim/archive |
| `read_req` | `req.get` | `{ project, req }` — embeds `active_claim: {id, agent_id, heartbeat_at, claimed_at} \| null` |
| `list_reqs_for_ur` | `req.list` | `{ project, ur }` — same `active_claim` embed |
| `list_claimable_reqs` | `req.list-claimable` | `{ project }` — Priority DESC, REQ-id ASC; already deps+footprint filtered |
| `claim_req` | `req.claim` | `{ project, req, agent_id, session? }` — `concurrent-conflict:` / `footprint-overlap:` / `not-claimable:` in the error message |
| `heartbeat_req` | `req.heartbeat` | `{ project, req }` |
| `set_req_status` | `req.set-status` | `{ project, req, status }` (`backlog`/`in_progress`/`stopped`/`done`) |
| `set_blocked_by` | `req.set-blocked-by` | `{ project, req, depends_on: ["REQ-…"] }` (empty clears) |
| `set_files` | `req.set-files` | `{ project, req, files: ["path"] }` |
| `archive_req` | `req.archive` | `{ project, req }` — gate: done + proof + all AC checked; releases claim |
| `unblock_req` | `req.unblock` | `{ project, req }` |
| `append_decision` | `decision.append` | `{ project, date, ref?, decision, rationale? }` |
| `write_verify_report` | `ur.write-verify-report` | `{ project, ur, body }` |
| `write_close_report` | `ur.write-close-report` | `{ project, ur, body }` — sets `closed_at` |
| `append_run_note` | `req.append-run-note` | `{ project, payload, req?, ur? }` |
| `read_active_milestone` | **Refuse (v1.1)** | Not implemented as MCP. Treat as “not in milestone mode.” Do not invent a local cursor. |
| `set_active_milestone` | **Refuse (v1.1)** | Same. |
| `list_milestone_reqs` | **Refuse (v1.1)** | Same. |
| `write_gate_state` | **Local only** | `{project}/.do-work/state/gate-owner.md` — never a do-work.io / MCP op |
| `migrate_markdown_to_linear` | **Refuse** | Backend is already `do-work-io` |

AC checkboxes (product op, not a port name): `req.set-acceptance-criteria` — `{ project, req, items: [{body, is_checked?}] }` replace.

---

## Op sequences

Each sequence starts with rediscovery (`search_tool` → observed tool). Inputs match the server capability DTOs. Do **not** invent extra HTTP `/capabilities/*` calls.

#### `ensure_product_container`

1. `search_tool` `project.ensure`
2. `project.ensure` `{ slug: tracker.dowork.project, name: project.name || slug, layers? }`
3. Persist nothing locally except the already-configured slug. Over-cap / auth failure → hard-stop (no markdown substitute).

#### `create_ur`

1. `search_tool` `ur.create`
2. `ur.create` `{ project, title, brief, classification?, layers_in_scope? }`
3. Use returned `data.slug` (`UR-NNN`) as the agent id.

#### `read_ur`

1. `search_tool` `ur.get`
2. `ur.get` `{ project, ur }` — read-only.

#### `list_urs`

1. `search_tool` `ur.list`
2. `ur.list` `{ project, page?, per_page? }` — ids + titles; `read_ur` for full body.

#### `append_ideate`

1. `search_tool` `ur.append-ideate`
2. `ur.append-ideate` `{ project, ur, body }` — append; never overwrite the intake brief.

#### `append_clarifications`

1. `search_tool` `ur.append-clarifications`
2. `ur.append-clarifications` `{ project, ur, body }` — append; does not create REQs.

#### `create_req`

1. `search_tool` `req.create`
2. `req.create` `{ project, ur, title, body?, priority?, files?, layer?, size?, parent? }`
3. Use returned `data.slug` (`REQ-NNN`). Starts unclaimed, backlog.

#### `update_req`

1. `search_tool` `req.update`
2. `req.update` `{ project, req, title?, body?, priority?, layer?, size?, entry_point?, terminal_state?, closure_proof?, criteria_approved?, suite? }`
3. Status / files / deps / claim / archive are **ignored** here — use the dedicated ops.

#### `read_req`

1. `search_tool` `req.get`
2. `req.get` `{ project, req }` — full REQ + `active_claim` embed.

#### `list_reqs_for_ur`

1. `search_tool` `req.list`
2. `req.list` `{ project, ur, page?, per_page? }` — any status; `active_claim` embed.

#### `list_claimable_reqs`

1. `search_tool` `req.list-claimable`
2. `req.list-claimable` `{ project, page?, per_page? }`
3. Server already filters backlog + deps-satisfied + footprint-free + unclaimed (or stale-takeover eligible). Empty list is valid. Does not claim.

#### `claim_req`

1. Re-read via `req.get` / pick via `req.list-claimable`.
2. `search_tool` `req.claim`
3. `req.claim` `{ project, req, agent_id, session? }`
4. Same `agent_id` refreshes. Fresh foreign claim → error message starts with `concurrent-conflict:` → stop / resume. Footprint clash → `footprint-overlap:`. Not eligible → `not-claimable:`. Stale foreign claim → server takeover.

#### `heartbeat_req`

1. `search_tool` `req.heartbeat`
2. `req.heartbeat` `{ project, req }` — refresh liveness on the active claim only; no second claim row; no git commit.

#### `set_req_status`

1. `search_tool` `req.set-status`
2. `req.set-status` `{ project, req, status }` where `status` is `backlog` / `in_progress` / `stopped` / `done`.
3. Archive/done gate → `archive_req`. Clear claim → `unblock_req`.

#### `set_blocked_by`

1. `search_tool` `req.set-blocked-by`
2. `req.set-blocked-by` `{ project, req, depends_on: ["REQ-…"] }` — empty array clears. Server rejects cycles.

#### `set_files`

1. `search_tool` `req.set-files`
2. `req.set-files` `{ project, req, files: ["path"] }` — replacement footprint. Does not claim.

#### `archive_req`

1. Set `closure_proof` via `req.update` and status `done` via `req.set-status` first (AC boxes via `req.set-acceptance-criteria`).
2. `search_tool` `req.archive`
3. `req.archive` `{ project, req }` — gate: `done` + proof + all AC checked; releases claim. Gate failure leaves `done` and returns deny reasons.

#### `unblock_req`

1. `search_tool` `req.unblock`
2. `req.unblock` `{ project, req }` — return to backlog; clear/release claim.

#### `append_decision`

1. `search_tool` `decision.append`
2. `decision.append` `{ project, date, decision, ref?, rationale? }` — append-only.

#### `write_verify_report`

1. `search_tool` `ur.write-verify-report`
2. `ur.write-verify-report` `{ project, ur, body }`.

#### `write_close_report`

1. `search_tool` `ur.write-close-report`
2. `ur.write-close-report` `{ project, ur, body }` — sets UR `closed_at`.

#### `append_run_note`

1. `search_tool` `req.append-run-note`
2. `req.append-run-note` `{ project, payload, req?, ur? }`. Optional local `.do-work/runs/RUN-NNN.yml` is telemetry only when `ledger.enabled`.

#### `read_active_milestone`

**Refuse (v1.1).** Not implemented as an MCP call. Treat as “not in milestone mode.” Do **not** invent a local `active-milestone.md` cursor and do **not** call any milestone capability.

#### `set_active_milestone`

**Refuse (v1.1).** Same — not implemented as MCP. Leave any remote milestone cursor untouched.

#### `list_milestone_reqs`

**Refuse (v1.1).** Same. Use `list_reqs_for_ur` (`req.list`) when you need the UR’s REQs.

#### `write_gate_state`

**Local only.** Write or delete `{project}/.do-work/state/gate-owner.md` (single-line `AGENT_ID`). This is a runtime lock, **never** a do-work.io MCP / capability op.

#### `migrate_markdown_to_linear`

**Refuse.** Effective backend is already `do-work-io`. Do not run markdown→Linear cutover. Leave config + remote store unchanged.

---

## Claim protocol

1. **Pick:** `req.list-claimable`. Empty list is valid.
2. **Claim:** `req.claim` with `agent_id` = `$(hostname).$$` (or the session’s AGENT_ID). Same `agent_id` refreshes. Fresh foreign claim → error message starts with `concurrent-conflict:` → stop / resume. Stale foreign claim → server takeover (no client `scan-stale` op).
3. **Heartbeat:** `req.heartbeat` only (no second active row).
4. **Stale discovery (v1):** there is **no** `scan-stale` tool. For each in-flight REQ from `req.list` / `req.get`, if `active_claim.heartbeat_at` is older than `parallel.stale_threshold_seconds` (default 900), treat as stale for triage. Authoritative recovery is in-claim takeover on the next `req.claim`.
5. **Archive:** `req.set-status` → `done` (set `closure_proof` via `req.update` first), then `req.archive`. Gate failure leaves `done` and returns deny reasons.
6. **Unblock:** `req.unblock`.
7. **Mid-flight MCP death:** leave claimed; resume/unblock after MCP recovers.

---

## status_map (REQ-only)

Identity: `backlog` / `in_progress` / `stopped` / `done`. Do not invent UR statuses.

---

## Commits / branches

Same as markdown/sqlite:

```
feat(REQ-NNN): short title

REQ: REQ-NNN
UR: UR-NNN
Output: path/to/primary/output
```

Worktree: `req/REQ-NNN`.

---

## Cycle-check / deadlock

Server `req.set-blocked-by` rejects cycles. For a read-side diagnostic, `req.list` + each REQ’s `depends_on` slugs; DFS in working memory. Not a claim gate (server already enforces).

---

## Related

- `agents/tracker/port.md` — shared op catalog + hard-stop / leave-claimed
- `agents/config.md` — `tracker.dowork.*` + Load Config 7c
- Design §4.1 / §5 — capability ↔ port map
