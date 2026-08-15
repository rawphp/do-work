# Tracker backend: markdown (default)

Implements the tracker port (`agents/tracker/port.md`) with local files under `.do-work/` and existing `lib/*.sh` helpers.

**This is the default backend.** When `tracker.backend` is missing, empty, or `markdown`, agents load this file and run today's file-based loop. No Linear tools, credentials, or dual-write.

---

## When to load

After config load and backend resolution (see `port.md` load path and each phase agent's **Tracker load path** block):

1. Backend resolves to `markdown` (including unset/empty default).
2. Read `agents/tracker/port.md`.
3. Read this file.
4. Perform work-item ops only via the mappings below.

Do **not** load `agents/tracker/linear.md` on this path.

---

## Bash surface (markdown only)

**No Linear-aware bash is required for the markdown backend.** Every `lib/*.sh` script listed here is file/git coordination against `.do-work/`. Scripts do not call Linear MCP, GraphQL, or Linear APIs. Linear reimplements the same *semantics* in `agents/tracker/linear.md` via agent/MCP steps — it does not reuse these scripts as Linear clients.

| Script | Role on this backend |
|--------|----------------------|
| `lib/pick-req.sh` | Pick first claimable backlog REQ (scope, deps, footprint) |
| `lib/claim-req.sh` | Atomic claim: `git mv` / `mv` + stamp + status |
| `lib/check-deps.sh` | Unsatisfied `**Depends on:**` vs `archive/` |
| `lib/check-footprint.sh` | Footprint overlap vs `working/` slots |
| `lib/heartbeat.sh` | Refresh `**Heartbeat:**` on a claimed working/ REQ (FS-only) |
| `lib/scan-stale.sh` | List working/ slots past stale threshold (orchestrator) |
| `lib/check-archive-integrity.sh` | Gate before archive: status done, proof, AC checked |
| `lib/run-ledger.sh` | Append `.do-work/runs/RUN-NNN.yml` when ledger enabled |
| `lib/score-coverage.sh` | Verify-phase confidence arithmetic |
| `lib/deadlock-check.sh` | Parallel drain diagnosis (orchestrator) |
| `lib/derive-status.sh` | proven/unproven from closure proof + Suite header |

**Composition note:** `list_claimable_reqs` is implemented by `pick-req.sh`, which inlines deps + footprint filters equivalent to `check-deps.sh` and `check-footprint.sh`. The standalone check scripts remain the explicit ops/helpers for single-REQ diagnostics and tests; pick is the run-loop picker.

---

## Store layout (unchanged)

| Artifact | Location |
|----------|----------|
| Issue brief | `.do-work/user-requests/UR-NNN/input.md` |
| Ideate | `.do-work/user-requests/UR-NNN/ideate.md` |
| Clarifications | `## Clarifications` section inside `input.md` |
| REQ backlog | `.do-work/REQ-NNN-*.md` (or `REQ-M<n>-NNN-*.md` in milestone mode) |
| In-flight | `.do-work/working/REQ-NNN-*.md` |
| Done | `.do-work/archive/REQ-NNN-*.md` |
| Decisions | `.do-work/decisions.md` |
| Close report | `.do-work/user-requests/UR-NNN/closure.md` (+ optional `closure-evidence/`) |
| Verify report | Console/agent output from `agents/verify.md` (no single fixed file path; scoring via `lib/score-coverage.sh`) |
| Run notes / ledger | `.do-work/runs/RUN-NNN.yml` via `lib/run-ledger.sh` when `ledger.enabled` |
| Milestone cursor | `.do-work/state/active-milestone.md`, checklist `.do-work/state/milestones.md` |
| Gate lock | `.do-work/state/gate-owner.md` |
| Final-suite lock | `.do-work/state/final-suite-*.md` (runtime; not a port work-item field) |

Runtime/git (worktrees, merges, events, config) stay local and are outside the port op surface.

---

## Op → implementation map

Every op name from `port.md` appears below with **script path and/or file glob**. Paths under `lib/` are only listed when the file exists in this repo. Where no dedicated script exists, the implementation is **agent playbook + file edit** (called out as such — not invented as a fake `lib/*.sh`).

### Catalog index (quick)

| Port op | Primary implementation |
|---------|------------------------|
| `ensure_product_container` | `mkdir -p` / install layout under `.do-work/` — no dedicated lib |
| `create_ur` | `agents/intake.md` → `.do-work/user-requests/UR-NNN/input.md` |
| `read_ur` | Read `.do-work/user-requests/UR-NNN/input.md` (+ `ideate.md` if present) |
| `list_urs` | Glob `.do-work/user-requests/UR-*/` |
| `append_ideate` | `agents/ideate.md` → `user-requests/UR-NNN/ideate.md` |
| `append_clarifications` | `agents/question.md` → append `## Clarifications` in `input.md` |
| `create_req` | `agents/capture.md` → `.do-work/REQ-NNN-*.md` |
| `update_req` | Edit REQ file in place (capture/audit/worker/orchestrator) |
| `read_req` | Read REQ from backlog / `working/` / `archive/` |
| `list_reqs_for_ur` | Glob REQs with matching `**UR:**` across backlog/working/archive |
| `list_claimable_reqs` | **`lib/pick-req.sh`** (uses deps + footprint filters; peers: **`lib/check-deps.sh`**, **`lib/check-footprint.sh`**) |
| `claim_req` | **`lib/claim-req.sh`** |
| `heartbeat_req` | **`lib/heartbeat.sh`** |
| `set_req_status` | Edit `**Status:**` on REQ file (agent/orchestrator; no dedicated lib) |
| `set_blocked_by` | Edit `**Depends on:**` header (no dedicated lib) |
| `set_files` | Edit `**Files:**` header (no dedicated lib) |
| `archive_req` | Orchestrator: status/proof/outputs + move to `archive/`; gate **`lib/check-archive-integrity.sh`** |
| `unblock_req` | `agents/unblock.md` — strip claim stamp, status backlog, move out of `working/` |
| `append_decision` | Append line to `.do-work/decisions.md` |
| `write_verify_report` | `agents/verify.md` + **`lib/score-coverage.sh`** (console report; no fixed durable path) |
| `write_close_report` | `agents/close.md` → `user-requests/UR-NNN/closure.md` |
| `append_run_note` | **`lib/run-ledger.sh`** → `.do-work/runs/RUN-NNN.yml` when ledger enabled |
| `read_active_milestone` | Read `.do-work/state/active-milestone.md` |
| `set_active_milestone` | Write/delete `.do-work/state/active-milestone.md` (+ `milestones.md` checklist) |
| `list_milestone_reqs` | Glob `.do-work/REQ-M<n>-*.md` (and working/archive forms) for active `M<n>` |
| `write_gate_state` | Write/delete `.do-work/state/gate-owner.md` (local lock) |

---

### Op contracts (markdown sequences)

#### `ensure_product_container`

| | |
|---|---|
| **Intent** | Ensure local product store dirs exist. |
| **Implementation** | Agent/install: `mkdir -p .do-work/{user-requests,working,archive,state,runs}` as needed. Install path: `install.sh` / first-use conventions. |
| **lib/*.sh** | **None** — no `lib/ensure-product-container.sh`. Gap: intentional; directory creation is playbook/install. |
| **File globs** | `.do-work/` tree |

#### `create_ur`

| | |
|---|---|
| **Intent** | Record intake brief. |
| **Implementation** | `agents/intake.md`: allocate next `UR-NNN`, `mkdir -p .do-work/user-requests/UR-NNN/assets`, write `input.md`. |
| **lib/*.sh** | **None** |
| **File paths** | `.do-work/user-requests/UR-NNN/input.md` |

#### `read_ur`

| | |
|---|---|
| **Intent** | Load brief (+ ideate if present). |
| **Implementation** | Read `input.md`; optionally read `ideate.md` and `## Clarifications` in the brief. |
| **lib/*.sh** | **None** |
| **File paths** | `.do-work/user-requests/UR-NNN/input.md`, `…/ideate.md` |

#### `list_urs`

| | |
|---|---|
| **Intent** | Enumerate Issues. |
| **Implementation** | Glob directories under `.do-work/user-requests/UR-*/` (exclude non-UR siblings such as `archive/` if present). |
| **lib/*.sh** | **None** |
| **File globs** | `.do-work/user-requests/UR-*/` |

#### `append_ideate`

| | |
|---|---|
| **Intent** | Write ideate onto UR. |
| **Implementation** | `agents/ideate.md` writes `.do-work/user-requests/UR-NNN/ideate.md`. |
| **lib/*.sh** | **None** |
| **File paths** | `user-requests/UR-NNN/ideate.md` |

#### `append_clarifications`

| | |
|---|---|
| **Intent** | Question-phase Q&A. |
| **Implementation** | `agents/question.md` appends `## Clarifications` (and Q&A entries) to `input.md`. Never overwrites the original brief above that section. |
| **lib/*.sh** | **None** |
| **File paths** | `user-requests/UR-NNN/input.md` |

#### `create_req`

| | |
|---|---|
| **Intent** | Create one backlog REQ for an Issue. |
| **Implementation** | `agents/capture.md` writes `.do-work/REQ-NNN-slug.md` (or `REQ-M<n>-NNN-slug.md`) with template headers, `**Status:** backlog`, footprint/deps as known. |
| **lib/*.sh** | **None** for create; later eligibility uses pick/deps/footprint. |
| **File globs** | `.do-work/REQ-*.md` |

#### `update_req`

| | |
|---|---|
| **Intent** | Edit body/fields without claim/archive lifecycle. |
| **Implementation** | In-place edit of the REQ file wherever it lives (backlog / working / archive for allowed phases). Prefer dedicated ops for status, deps, footprint, claim. |
| **lib/*.sh** | **None** |
| **File paths** | matching `REQ-*.md` in backlog, `working/`, or `archive/` |

#### `read_req`

| | |
|---|---|
| **Intent** | Load full REQ. |
| **Implementation** | Read the REQ file; resolve by id across backlog root, `working/`, `archive/`. |
| **lib/*.sh** | **None** (optional downstream: `lib/derive-status.sh` for proven/unproven view). |
| **File globs** | `.do-work/REQ-<id>-*.md`, `.do-work/working/REQ-<id>-*.md`, `.do-work/archive/REQ-<id>-*.md` |

#### `list_reqs_for_ur`

| | |
|---|---|
| **Intent** | All REQs for an Issue, any status. |
| **Implementation** | Glob REQ files; filter on header `**UR:** UR-NNN`. |
| **lib/*.sh** | **None** — no `lib/list-reqs-for-ur.sh`. |
| **File globs** | `.do-work/REQ-*.md`, `working/REQ-*.md`, `archive/REQ-*.md` |

#### `list_claimable_reqs`

| | |
|---|---|
| **Intent** | Backlog REQs that are unclaimed, deps-satisfied, footprint-free — pick order. |
| **Implementation** | **`lib/pick-req.sh <scope> <agent-id>`** from project root. Scope: `any` or `UR-NNN`. Prints absolute path of first claimable REQ (exit 0) or empty (exit 1). Stderr: `dep:…` / `overlap:…` / `scope:…` rejects. |
| **Related scripts** | **`lib/check-deps.sh <req-path>`** — missing deps (stdout one id per line). **`lib/check-footprint.sh <req-path>`** — overlap lines vs `working/`. **`lib/scan-stale.sh`** — stale slots for reclaim policy (orchestrator, not a pick filter input). |
| **Authoritative deps** | Markdown: `**Depends on:**` on the REQ file (satisfied iff each id has `.do-work/archive/<id>-*.md`). |
| **File globs** | Candidates: `.do-work/REQ-*.md` or `.do-work/REQ-M<active>-*.md` when `state/active-milestone.md` exists. In-flight exclusion: `.do-work/working/REQ-*.md`. |

#### `claim_req`

| | |
|---|---|
| **Intent** | Optimistic claim + in-progress. |
| **Implementation** | **`lib/claim-req.sh <req-path> <agent-id>`** where `<req-path>` is a backlog-root file (`.do-work/REQ-*.md`, not under `working/`). |
| **Sequence (script)** | 1) Validate backlog-root REQ. 2) Move into `.do-work/working/`: **tracked** `.do-work/` → `git mv`; **untracked** → plain `mv`. 3) Insert claim stamp (`Claimed by` / `Claimed at` / `Heartbeat`, optional Session) under the `# REQ-…:` heading. 4) Set `**Status:**` to `in-progress`. 5) If tracked: stage + commit `chore(REQ-NNN): claim by <agent-id>`; print short hash. If untracked: print `untracked`. |
| **Claim atomicity (mv / git mv race)** | Concurrent claim is a **filesystem race on the move**, not a distributed lock. Loser semantics match the script: |
| | • **Exit 0** — claim succeeded. |
| | • **Exit 2** — race lost (source no longer at backlog root). Stderr: `Claim lost: <req-id>`. Caller re-runs `pick-req.sh`; do not force-claim. |
| | • **Exit 1** — other failure; script attempts to reverse the move. |
| **lib/*.sh** | **`lib/claim-req.sh`** (exists). |
| **File paths** | Source: `.do-work/REQ-NNN-*.md` → dest: `.do-work/working/REQ-NNN-*.md` |

#### `heartbeat_req`

| | |
|---|---|
| **Intent** | Refresh liveness on active claim. |
| **Implementation** | **`lib/heartbeat.sh <req-path>`** with path under `.do-work/working/`. Updates `**Heartbeat:**` inside the claim stamp to current UTC ISO. **No git commit** — filesystem only. |
| **lib/*.sh** | **`lib/heartbeat.sh`** (exists). Related consumer: **`lib/scan-stale.sh`**. |
| **File paths** | `.do-work/working/REQ-*.md` |

#### `set_req_status`

| | |
|---|---|
| **Intent** | Set workflow status without full archive. |
| **Implementation** | Edit `**Status:**` on the REQ file (e.g. `stopped`, `in-progress`). `claim_req` already sets `in-progress`. Resume: `agents/resume.md` (stopped → in-progress + heartbeat). Archive/done → `archive_req`. Clear claim → `unblock_req`. |
| **lib/*.sh** | **None** for generic status write. |
| **File paths** | REQ file at current location |

#### `set_blocked_by`

| | |
|---|---|
| **Intent** | Write depends-on graph. |
| **Implementation** | Set/clear header `**Depends on:**` (comma and/or whitespace separated REQ ids). Eligibility readers: `pick-req.sh` / `check-deps.sh`. |
| **lib/*.sh** | **None** for write; **`lib/check-deps.sh`** for read/eligibility. |
| **File paths** | REQ header field |

#### `set_files`

| | |
|---|---|
| **Intent** | Set footprint list. |
| **Implementation** | Set/clear header `**Files:**` (space-separated paths/globs). Overlap evaluated at pick/claim via `pick-req.sh` / `check-footprint.sh`. |
| **lib/*.sh** | **None** for write; **`lib/check-footprint.sh`** for read/eligibility. |
| **File paths** | REQ header field |

#### `archive_req`

| | |
|---|---|
| **Intent** | Done + closure proof / outputs; leave in-flight. |
| **Implementation** | Orchestrator (`agents/run.md` post-worker): set `**Status:** done`, write `**Closure proof:**` and `## Outputs`, optional `**Suite:**`, then move `.do-work/working/REQ-*.md` → `.do-work/archive/REQ-*.md` (git-aware when tracked). **Before archive write, gate with `lib/check-archive-integrity.sh <req-path>`** (requires done status, non-empty closure proof, no unchecked `- [ ]` ACs). |
| **lib/*.sh** | **`lib/check-archive-integrity.sh`** (gate). **No** `lib/archive-req.sh` — move/status/outputs are orchestrator playbook. Optional: **`lib/derive-status.sh`**, **`lib/check-acceptance-evidence.sh`**. |
| **File paths** | `working/` → `archive/` |

#### `unblock_req`

| | |
|---|---|
| **Intent** | Return to backlog; clear claim. |
| **Implementation** | `agents/unblock.md`: locate `.do-work/working/REQ-NNN-*.md`, strip claim stamp block (`<!-- claimed-start -->` … `<!-- claimed-end -->`), set `**Status:** backlog`, move file back to `.do-work/` backlog root. |
| **lib/*.sh** | **None** — no `lib/unblock-req.sh`. Gap: agent-only today. |
| **File paths** | `working/REQ-*.md` → `.do-work/REQ-*.md` |

#### `append_decision`

| | |
|---|---|
| **Intent** | Append standing decision line. |
| **Implementation** | Append one line to `.do-work/decisions.md` (create if absent when writer is capture/etc.). Format: `YYYY-MM-DD \| Issue/REQ ref \| decision \| rationale`. |
| **lib/*.sh** | **None** |
| **File paths** | `.do-work/decisions.md` |

#### `write_verify_report`

| | |
|---|---|
| **Intent** | Persist verify-phase coverage report for an Issue. |
| **Implementation** | `agents/verify.md` produces the coverage report (console-primary). Scoring arithmetic: **`lib/score-coverage.sh`**. |
| **lib/*.sh** | **`lib/score-coverage.sh`** (exists). **No** `lib/write-verify-report.sh`. |
| **File paths** | **Gap:** no single durable path equivalent to `closure.md`; report is agent console output unless the operator asks to save it. Do not invent a path. |

#### `write_close_report`

| | |
|---|---|
| **Intent** | Persist close-phase report for an Issue. |
| **Implementation** | `agents/close.md` writes `.do-work/user-requests/UR-NNN/closure.md` (+ optional `closure-evidence/`). |
| **lib/*.sh** | **None** |
| **File paths** | `user-requests/UR-NNN/closure.md` |

#### `append_run_note`

| | |
|---|---|
| **Intent** | Ledger-ish / cost note for a REQ or run. |
| **Implementation** | When `ledger.enabled`: **`lib/run-ledger.sh`** with flags (`--project`, `--req`, `--agent`, `--model`, `--branch`, timestamps, `--result`, `--cost-estimate`, evidence paths, etc.) appends `.do-work/runs/RUN-NNN.yml`. |
| **lib/*.sh** | **`lib/run-ledger.sh`** (exists). |
| **File paths** | `.do-work/runs/RUN-NNN.yml` |

#### `read_active_milestone`

| | |
|---|---|
| **Intent** | Read milestone cursor. |
| **Implementation** | Read `.do-work/state/active-milestone.md` (absent ⇒ not milestone mode). |
| **lib/*.sh** | **None** (pick-req.sh reads it for glob constraint). |
| **File paths** | `.do-work/state/active-milestone.md` |

#### `set_active_milestone`

| | |
|---|---|
| **Intent** | Set or advance milestone cursor. |
| **Implementation** | Write milestone id into `active-milestone.md`; maintain checklist in `milestones.md` (capture / run deploy-gate). Delete cursor when all milestones deployed / run stop. |
| **lib/*.sh** | **None** |
| **File paths** | `.do-work/state/active-milestone.md`, `.do-work/state/milestones.md` |

#### `list_milestone_reqs`

| | |
|---|---|
| **Intent** | REQs for active (or named) milestone. |
| **Implementation** | Glob `REQ-M<n>-*.md` under backlog (and optionally working/archive) for `M<n>` from active cursor or argument. |
| **lib/*.sh** | **None** dedicated; **`lib/pick-req.sh`** constrains claimable backlog to active milestone when cursor exists. |
| **File globs** | `.do-work/REQ-M<n>-*.md`, `working/REQ-M<n>-*.md`, `archive/REQ-M<n>-*.md` |

#### `write_gate_state`

| | |
|---|---|
| **Intent** | Deploy-gate ownership coordination. |
| **Implementation** | Write single-line `AGENT_ID` to `.do-work/state/gate-owner.md`; delete when gate resolves. Local runtime lock — allowed even if a future backend stores work items remotely. |
| **lib/*.sh** | **None** — no `lib/write-gate-state.sh`. |
| **File paths** | `.do-work/state/gate-owner.md` |

---

## Gaps (explicit — do not invent scripts)

These port ops have **no** dedicated `lib/*.sh` writer/reader. Implementations are agent playbooks and file globs only. **Do not invent** names such as `lib/create-ur.sh`, `lib/archive-req.sh`, or `lib/unblock-req.sh` in callers.

| Op | Gap |
|----|-----|
| `ensure_product_container` | No lib; mkdir/install |
| `create_ur` / `read_ur` / `list_urs` | No lib; intake + globs |
| `append_ideate` / `append_clarifications` | No lib; ideate/question agents |
| `create_req` / `update_req` / `read_req` / `list_reqs_for_ur` | No lib; capture + file IO |
| `set_req_status` / `set_blocked_by` / `set_files` | No lib writers; header edits |
| `archive_req` | Integrity gate only (`check-archive-integrity.sh`); move is orchestrator |
| `unblock_req` | Agent-only (`agents/unblock.md`) |
| `append_decision` | File append only |
| `write_verify_report` | Score lib only; no durable report path |
| `write_close_report` | Agent-only (`closure.md`) |
| `read_active_milestone` / `set_active_milestone` / `list_milestone_reqs` | State files + globs; pick-req consumes cursor |
| `write_gate_state` | State file only |

Coordination ops that **do** have real scripts: `list_claimable_reqs` → `pick-req.sh` (+ `check-deps.sh`, `check-footprint.sh`); `claim_req` → `claim-req.sh`; `heartbeat_req` → `heartbeat.sh`; `append_run_note` → `run-ledger.sh`; archive integrity → `check-archive-integrity.sh`; verify score → `score-coverage.sh`.

---

## Claim atomicity (summary)

Matches `lib/claim-req.sh` and `agents/run.md` claim step:

1. Pick via `lib/pick-req.sh` (does not claim).
2. Claim via `lib/claim-req.sh` — **atomic unit is `git mv` (tracked) or `mv` (untracked)** of the REQ from backlog root into `working/`, then stamp + status rewrite.
3. **Race lost → exit 2** (`Claim lost: REQ-NNN`); re-pick. Same stopper class as Linear concurrent-conflict for multi-agent recovery.
4. Heartbeats via `lib/heartbeat.sh` keep the slot fresh; `lib/scan-stale.sh` detects abandoned slots.

---

## Rules specific to markdown

- **Default / no hard-stop:** unset or empty `tracker.backend` → this backend; never require Linear.
- **No Linear-aware bash required** for any markdown port op (see **Bash surface**).
- **No dual-write:** do not create Linear Initiatives/Issues/comments as part of markdown ops.
- **Bash remains authoritative** for claim, pick, deps, footprint, heartbeat, and archive integrity on this path.
- **Never invent `lib/*.sh` paths** that are not in the repo; use the **Gaps** table.
- **Regression:** `bash lib/tests/run-all.sh` and `bash lib/conformance-scan.sh {project}` stay runnable without Linear.

---

## Related runtime helpers (not port ops)

Listed so agents do not confuse them with the catalog; still markdown-local scripts:

| Script | Use |
|--------|-----|
| `lib/scan-stale.sh` | Orchestrator pre-flight stale slots |
| `lib/deadlock-check.sh` | Parallel drain diagnosis |
| `lib/provision-worktree.sh` | Worker worktree deps |
| `lib/file-feedback.sh` | Trend feedback inbox |
| `lib/emit-event.sh` / `lib/session-hook.sh` / `lib/stamp-session.sh` / `lib/resolve-session.sh` | Session telemetry |
| `lib/check-acceptance-evidence.sh` | Acceptance evidence validation |
| `lib/derive-status.sh` | proven/unproven derivation |

---

## Out of scope for this file

- Linear MCP sequences → `agents/tracker/linear.md`.
- Changing TDD, worktree isolation, or review philosophy — documentation of the existing store only.
- Implementing new bash for gap ops — out of scope for this mapping REQ.
