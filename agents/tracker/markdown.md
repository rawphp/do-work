# Tracker backend: markdown (default)

Implements the tracker port (`agents/tracker/port.md`) with local files under `.do-work/` and existing `lib/*.sh` helpers.

**This is the default backend.** When `tracker.backend` is missing, empty, or `markdown`, agents load this file and run today's file-based loop. No Linear tools, credentials, or dual-write.

---

## When to load

After config load and backend resolution (see `port.md` load path):

1. Backend resolves to `markdown` (including unset/empty default).
2. Read `agents/tracker/port.md`.
3. Read this file.
4. Perform work-item ops only via the mappings below (or their expanded child-REQ sequences).

Do **not** load `agents/tracker/linear.md` on this path.

---

## Store layout (unchanged)

| Artifact | Location |
|----------|----------|
| UR brief | `.do-work/user-requests/UR-NNN/input.md` (+ ideate/clarifications/closure siblings as today) |
| REQ backlog | `.do-work/REQ-NNN-*.md` |
| In-flight | `.do-work/working/REQ-NNN-*.md` |
| Done | `.do-work/archive/REQ-NNN-*.md` |
| Decisions | `.do-work/decisions.md` |
| Verify / close reports | under the UR directory (existing conventions) |
| Run notes / ledger | `.do-work/runs/RUN-NNN.yml` when `ledger.enabled` |
| Milestone cursor | `.do-work/state/active-milestone.md`, `milestones.md` |
| Gate / suite locks | `.do-work/state/gate-owner.md`, `final-suite-*.md` |

Runtime/git (worktrees, merges, events, config) stay local and are outside the port op surface.

---

## Op → implementation map (scaffolding)

Full step-by-step sequences expand with the markdown-backend and agent-wiring children. Until then, agents continue existing playbook steps; this table **names** the port op each existing surface already realizes so the path is reachable and regression stays green.

| Port op | Markdown implementation (existing) |
|---------|-------------------------------------|
| `ensure_product_container` | Ensure `.do-work/` dirs exist (install / first use) |
| `create_ur` | Intake writes next `user-requests/UR-NNN/input.md` |
| `read_ur` | Read `user-requests/UR-NNN/input.md` (+ ideate if present) |
| `list_urs` | List `.do-work/user-requests/` |
| `append_ideate` | Ideate agent appends to UR artifacts |
| `append_clarifications` | Question agent appends Q&A to UR |
| `create_req` | Capture writes `REQ-NNN-*.md` in backlog root |
| `update_req` | Edit REQ file in place (capture/audit/worker as allowed) |
| `read_req` | Read REQ file from backlog / working / archive |
| `list_reqs_for_ur` | Glob REQs with matching `**UR:**` |
| `list_claimable_reqs` | `lib/pick-req.sh` (deps + footprint + unclaimed) |
| `claim_req` | `lib/claim-req.sh` (atomic claim stamp + move to `working/`) |
| `heartbeat_req` | `lib/heartbeat.sh` (filesystem-only stamp) |
| `set_req_status` | Update `**Status:**` on the REQ file |
| `set_blocked_by` | Update `**Depends on:**` header |
| `set_files` | Update `**Files:**` header |
| `archive_req` | Orchestrator move to `archive/` + Status done + outputs/proof |
| `unblock_req` | `/do-work unblock` / `agents/unblock.md` |
| `append_decision` | Append line to `.do-work/decisions.md` |
| `write_verify_report` | Verify agent report under the UR |
| `write_close_report` | Close agent `closure.md` under the UR |
| `append_run_note` | `lib/run-ledger.sh` / run notes when ledger enabled |
| `read_active_milestone` | Read `.do-work/state/active-milestone.md` |
| `set_active_milestone` | Write milestone state files |
| `list_milestone_reqs` | Glob `REQ-M<n>-*.md` for active milestone |
| `write_gate_state` | `.do-work/state/gate-owner.md` (local lock) |

---

## Rules specific to markdown

- **Default / no hard-stop:** unset or empty `tracker.backend` → this backend; never require Linear.
- **No dual-write:** do not create Linear Initiatives/Issues/comments as part of markdown ops.
- **Bash remains authoritative** for claim, pick, deps, footprint, heartbeat, and archive integrity on this path.
- **Regression:** `bash lib/tests/run-all.sh` and `bash lib/conformance-scan.sh {project}` must stay runnable without Linear.

---

## Out of scope for this file

- Linear MCP sequences → `agents/tracker/linear.md` (other path-unit).
- Expanding every op into exhaustive agent steps → child REQs under the markdown-default path.
- Changing TDD, worktree isolation, or review philosophy — store documentation only.
