# Tracker port (shared contract)

Shared work-item operation catalog and load path for do-work multi-tracker backends.
Phase agents that touch URs/REQs (or other work-item artifacts) resolve storage **only** through this port and the active backend file — never by inventing raw store paths or tools outside the backend doc.

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
| Port op catalog body | Preconditions, inputs/outputs, error contracts per op |
| Markdown backend mapping | Op → `lib/*.sh` + `.do-work/` path sequences |
| Phase-agent load-path wiring | Each agent that touches work items loads port + backend |

---

## Load path (every work-item phase)

1. Load config (`agents/config.md`).
2. Resolve `tracker.backend`:
   - **missing key, empty string, or whitespace-only** → treat as **`markdown`**
   - **`markdown`** → continue; **no Linear tools required**, no hard-stop
   - **`linear`** → Linear backend path (separate path-unit; not this default)
   - **any other value** → hard-stop with a clear config error (do not guess)
3. Read `agents/tracker/port.md` (this file).
4. Read `agents/tracker/<backend>.md` (for default: `agents/tracker/markdown.md`).
5. For work-item storage, call **only** named port ops documented in the backend file.

Phase agents keep product logic (TDD, review, decomposition). They do not re-implement store details and do not dual-write across backends.

---

## Backend files

| File | Role |
|------|------|
| `agents/tracker/port.md` | Shared op names, rules, load path (this document) |
| `agents/tracker/markdown.md` | File + `lib/*.sh` implementation of port ops (default) |
| `agents/tracker/linear.md` | Linear skill/MCP sequences for the same ops (opt-in) |

Later backends (e.g. GitHub Issues, Jira) add sibling files; they are not part of the markdown-default path.

---

## Work-item vs runtime split

| Stays local (all backends) | Work-item store (backend-specific) |
|----------------------------|------------------------------------|
| Worktrees, branches, merges, PRs | UR create/read/update |
| `state/*` locks, events, context-pack | REQ create/edit/status/claim/archive |
| `config.yml`, install/conformance | Deps / footprint fields |
| Gate-owner / final-suite locks | Decisions, verify/close reports, run notes, calibration, milestone cursor content |

Markdown mode implements work-item ops with existing `.do-work/` trees and `lib/*.sh`. Linear mode reimplements the **same op names** via MCP; it never silently falls back to markdown.

---

## Operation catalog (names)

Names freeze intent. Full preconditions, fields, and error contracts live in the port catalog expansion and each backend file. Markdown may implement several ops by composing existing scripts.

| Op | Intent |
|----|--------|
| `ensure_product_container` | Product/team labeling ready (markdown: no-op / local dirs) |
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

---

## Shared rules (backend-independent)

- **No dual-write.** One active backend owns work-item truth. Markdown does not mirror to Linear; Linear does not write UR/REQ markdown as source of truth.
- **Claim eligibility** requires deps satisfied + footprint free + unclaimed (or stale claim recoverable per multi-agent rules).
- **Optimistic claim:** re-read before write; loser stops with concurrent-conflict / resume allowed.
- **Footprint** is the structured `**Files:**` (and related header fields) on the REQ — not ad-hoc custom fields.
- **Deps** are the declared depends-on graph; consumers honor archive-done dependencies before claim.
- **Hard-stop on unusable Linear** applies only when `tracker.backend: linear` — never on the markdown-default path.

---

## Regression (markdown-default terminal)

When `tracker.backend` resolves to `markdown`:

- Existing `lib/*.sh` coordination remains the implementation surface.
- `bash lib/tests/run-all.sh` and `bash lib/conformance-scan.sh` remain the regression gates.
- No Linear MCP discovery, team resolution, or credentials are required.
- Agents must not invent Linear tools or dual-write “for safety.”
