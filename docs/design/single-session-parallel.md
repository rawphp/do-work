# Single-Session Parallelism

**Date:** 2026-06-12
**Status:** Design approved — implementation spec for REQ-221
**UR:** UR-035 R4 / path-unit REQ-219
**Scope:** Add a single-session parallel run mode: one `/do-work run` orchestrator dispatching N concurrent workers from one terminal, while merge/evidence/policy/review/archive serialize through a merge queue. Touches `agents/run.md` (the run loop), `agents/config.md` (one config key), and `SKILL.md`/`commands` (the `--parallel N` flag surface). It does **not** touch the coordination lib (`pick-req.sh`, `claim-req.sh`, `check-footprint.sh`, `scan-stale.sh`) — those primitives already provide every safety guarantee this mode needs.

This document makes the hard coordination decisions concrete enough that REQ-221 implements them without inventing semantics.

---

## Problem

The system is already "safe to launch from N terminals": the coordination layer (footprint exclusion in `pick-req.sh`, atomic claims in `claim-req.sh`, dependency ordering, per-worker worktree isolation, heartbeat staleness) guarantees that two orchestrators never stomp each other. What it does **not** offer is parallelism from **one** terminal. A single operator who wants 3 workers running must open 3 terminals and 3 `/do-work run` processes.

Single-session mode closes that gap: one orchestrator process fans out N concurrent worker dispatches, then integrates their results through a **serialized merge queue**. The safety machinery is unchanged — what changes is the shape of the run loop's hot path: from `claim → dispatch → wait → integrate` (serial) to `claim K → dispatch K → integrate as each returns → refill` (windowed).

### Why the merge step is the whole problem

Workers are embarrassingly parallel: each runs TDD red→green in its own worktree on its own `req/REQ-NNN` branch, returning a structured YAML report (`agents/run-worker.md` `## Return Report`). They never touch `.do-work/` lifecycle state and never merge — that is the orchestrator's Step 4. The serial run loop already merges from the **main working tree, not the worktree** (`run.md` Step 4a). So even today, if two workers returned at the same instant, their merges would have to serialize through the one main working tree. Single-session mode makes that implicit serialization **explicit and ordered**: a merge queue. Everything in `run.md` Steps 3–4 (acceptance-evidence gate → policy gate → review gate → merge → archive → teardown → metadata commit) runs one-REQ-at-a-time; only Step 2 (worker dispatch) runs N-wide.

---

## Decisions

### 1. Fan-out mechanism — concurrent `Agent`-tool dispatches (NOT the Workflow tool)

**Decision: hand-rolled fan-out via N concurrent `Agent`-tool dispatches from the orchestrator, reaped as each returns.** Reject delegating the fan-out to the harness's Workflow tool (pipeline/parallel primitives).

The orchestrator issues up to N `Agent` calls in one turn (the harness runs concurrent tool calls in a single turn in parallel), each carrying the same worker contract already defined in `run.md` Step 2 (REQ path, Issue path, prior-REQ paths, `run-worker.md` inline). As each dispatch returns its YAML report, the orchestrator enqueues it for serialized integration (decision 3) and, if backlog remains, claims and dispatches a refill (decision 2).

**Trade-off evaluation** (three concrete criteria, per acceptance criterion):

| Criterion | `Agent`-tool fan-out (chosen) | Workflow-tool fan-out (rejected) |
|---|---|---|
| **Availability across harnesses** | The `Agent` tool is the existing worker-dispatch surface — already used by serial mode (`run.md` Step 2). Zero new harness dependency; mode works wherever serial mode works. | The Workflow tool's parallel/pipeline primitives are a harness-specific surface not guaranteed on every install (and the Codex install target lacks it). Depending on it would make the mode non-portable — exactly the failure class UR-035 R10/F flags for subagent routing. |
| **Progress visibility** | Same as serial: per-REQ announce line at claim time, structured YAML on return. The orchestrator stays the single point that logs `[agent-id] Starting REQ-NNN` and `✅ REQ-NNN complete`. No new opaque layer. | A Workflow would own scheduling internally; the orchestrator loses the announce/return checkpoints that the existing logging, ledger (Step 3b), and stopper-surfacing (Stopping Rules) all hang off. Visibility regresses. |
| **Resume semantics** | A dispatched worker that dies leaves its claimed `working/` slot with a heartbeat the existing stale-detection (`scan-stale.sh`) and pre-flight reclaim path already handle. `/do-work resume REQ-NNN` re-dispatches one worker — unchanged. Resume granularity is one REQ, matching the existing recovery taxonomy. | Workflow-internal state would need its own resume/restart contract layered on top of (and possibly conflicting with) the file-based claim/heartbeat model. Two resume mechanisms for one unit of work. |

**Decisive reason:** the coordination layer is *already* file + git + bash with the `Agent` tool as the only dispatch surface (per the 2026-05-21 parallel-coordination design's explicit non-goal: "no central daemon, scheduler, or orchestrator-of-orchestrators"). A Workflow primitive reintroduces a scheduler. Hand-rolled fan-out keeps the design on its existing spine.

### 2. Claim timing — claim-as-slot-frees (NOT claim-K-up-front)

**Decision: claim one REQ immediately before each dispatch, never a batch up front. The window of N concurrent workers fills by claiming N times at start, then re-claiming one each time a slot frees.**

`claim-req.sh` is atomic per REQ (`git mv` → stamp → status → scoped commit) and `pick-req.sh` excludes any candidate whose `**Files:**` overlaps **any** `working/` slot. These two facts make claim-as-slot-frees strictly correct and claim-K-up-front strictly wrong:

- **Footprint exclusion needs the claim to be visible before the next pick.** `pick-req.sh` reads `working/` directly to build its exclusion set. If the orchestrator picked K candidates *before* claiming any of them, the picker would not yet see the earlier picks in `working/` and could hand back K candidates whose footprints overlap each other. Claiming each pick (moving it into `working/`) before the next `pick-req.sh` call is what makes overlapping candidates mutually exclude. **So: `pick-req.sh` → `claim-req.sh` → `pick-req.sh` → `claim-req.sh` …, never `pick-req.sh × K` then claim.**
- **Filling the initial window** is therefore a loop of (pick, claim) repeated until either N slots are filled or `pick-req.sh` returns empty. Each claim updates `working/`, so the next pick automatically skips overlapping and now-claimed REQs.
- **When K candidates overlap:** the first to be claimed wins the slot; the rest are excluded by the overlap filter on the next pick and stay in the backlog. They become claimable again only when the winning slot drains (its REQ is integrated and the file leaves `working/`). This is identical to the multi-terminal behaviour — single-session just runs the pick/claim loop in one process instead of racing across processes. No new arbitration logic.

A claimed-but-not-yet-dispatched gap is impossible because each claim is immediately followed by its dispatch in the same fan-out turn.

### 3. The merge queue

Workers return commits on `req/REQ-NNN` branches concurrently and **in any order** (a fast REQ dispatched second can return before a slow REQ dispatched first). But every gate after dispatch must serialize. The merge queue is a single in-orchestrator FIFO of *returned worker reports awaiting integration*.

#### Queue ordering

**Order: by arrival (the order workers return), not by REQ number.** Rationale: integration is independent per REQ (footprints are disjoint by construction, so no two queued REQs touch the same files), so any serialization order is *correct*; arrival order is *cheapest* (no head-of-line blocking — the orchestrator never holds a returned-and-ready REQ waiting for a slower lower-numbered REQ). Dependency ordering is already enforced upstream at claim time (`pick-req.sh` will not hand out a REQ whose `**Depends on:**` are unarchived), so a dependent REQ cannot even be *dispatched* until its prerequisite is archived — the queue never needs to reorder for deps.

The orchestrator drains the queue one entry at a time. For each dequeued report it runs **exactly the existing serial `run.md` Steps 3–4 in order**, with no change to their internals:

1. Step 3 — acceptance-evidence gate (`check-acceptance-evidence.sh`)
2. Step 3 — policy gate (`check-policy.sh`)
3. Step 3 — review gate (`review.md`)
4. Step 3b — ledger entry (`run-ledger.sh`)
5. Step 4a — `git merge --no-ff req/REQ-NNN` from the main working tree
6. Step 4b — archive the REQ file
7. Step 4c — tear down the worktree + delete the branch
8. Step 4d — commit the metadata change

Only after an entry finishes Step 4d (or is diverted to Recover) does the orchestrator dequeue the next. This is the serialization guarantee: **at most one merge/archive/teardown sequence touches the main working tree and `.do-work/` at any instant**, exactly as in serial mode.

#### Conflict handling mid-queue

Reuse the existing Step 4a policy verbatim — **do not invent a new retry path**:

- On text-level conflict (`<<<<<<<` in any file), `git merge --abort`, then the existing **5-retry exponential backoff** (5s / 15s / 30s / 60s), each attempt re-syncing the base branch and re-merging.
- On the 5th failure: leave the `req/REQ-NNN` branch alive, transition the REQ to `**Status:** stopped`, `**Reason:** concurrent-conflict`, surface to the user, and **continue draining the rest of the queue.** A conflict on one queued REQ must not abort the others (see decision 5). The stuck REQ is resumable via `/do-work resume REQ-NNN`.

Because footprints are disjoint by construction, a *content* conflict between two queued REQs should not occur; the retry path exists to absorb conflicts against **concurrent multi-terminal siblings or a remote** (decision 6), not against same-session peers. Disjoint footprints make most conflicts a sync artefact that the rebase-and-retry resolves.

#### May review dispatches run concurrently while merges serialize?

**Yes — review (REQ-214's independent-subagent dispatch) may run concurrently across queued REQs; merge/archive must not.** Review reads only `(REQ, diff, evidence)` with no run context and writes nothing to the base branch or `.do-work/` lifecycle state — it is a pure read-only judgment. So the orchestrator may fan out the **review** step of multiple queued reports in parallel (the same `Agent`-tool concurrency used for workers), collect each verdict, and then feed only the passed-and-ready reports into the **serialized** merge/archive tail. This keeps the expensive independent-review latency off the critical path while preserving the single-writer invariant on the base branch.

Concretely, the queue has two stages:
- **Stage A (concurrent, read-only):** acceptance-evidence check → policy check → independent review dispatch. Safe to run N-wide.
- **Stage B (serial, single-writer):** ledger → merge → archive → teardown → metadata commit. One REQ at a time.

A report only enters Stage B after passing every Stage A gate. A Stage A failure (evidence/policy/review) diverts that one report to Recover without entering Stage B and without blocking other reports.

### 4. Flag surface

**Decision: `--parallel N` on the run command. Default `N=1` (serial — byte-for-byte unchanged). Hard cap `N=10`.**

- **Shape:** `/do-work run [UR-NNN] --parallel N`. `N` is a positive integer = the maximum number of concurrently dispatched workers (the window width).
- **Default:** absent flag, or `--parallel 1`, ⇒ the existing serial loop runs unmodified. This satisfies REQ-219's acceptance criterion "serial mode behaviour is byte-for-byte unchanged": the parallel code path is entered only when `N > 1`.
- **Cap:** clamp `N` to **10**, matching the existing 10-orchestrator design bound from the parallel-coordination spec ("a backlog of 100 REQs and ten parallel orchestrators"). A request for `--parallel 20` is clamped to 10 with a one-line notice. The cap protects the shared main working tree and the git object store from contention and keeps the ledger/feedback rate-limiting (single `feedback.lock`) tractable.
- **Config key:** `parallel.max_workers` in `.do-work/config.yml` (default `1`). The flag overrides config per-run; config sets the project default. The key lives under the existing `parallel:` section (alongside `parallel.stale_threshold_seconds`), so no new top-level section is introduced. The effective `N = min(flag-or-config, 10)`.

### 5. Failure isolation

**Decision: one worker (or one queued integration) stopping must never abort its siblings. Stoppers are queued per-REQ and surfaced in arrival order, reusing REQ-204's recovery rules unchanged.**

- A worker returning `status: stopped` / `failed` (or a Stage A gate failure on its report) is handled **exactly** as serial `run.md` Step 5 (Recover): the REQ stays in `working/` with `**Status:** stopped` and a `**Reason:**` field; the orchestrator surfaces the stopper per Stopping Rules. The difference under parallelism: the orchestrator **does not halt the loop** — it records the stopper, **frees that window slot**, and (if backlog remains) claims a refill. The other N-1 workers and any queued ready reports proceed untouched.
- **Stopper surfacing batches per arrival, not per tick.** When `next_steps.enabled` is true and standalone, each stopper still surfaces via `AskUserQuestion` (Show details / Retry / Skip) as in serial mode, processed in queue-arrival order so the user sees one decision at a time. When the gate is closed (delegate mode or `next_steps.enabled=false`), each stopper prints its `details` and the loop continues — no auto-retry, matching existing behaviour.
- **No new stopper reasons.** The enum in `run.md` Stopping Rules is complete. `concurrent-conflict` (the merge-queue 5-retry exhaustion, decision 3) is already in it.
- **Drain accounting.** A stopped REQ left in `working/` is, for the empty-backlog drain check (`run.md` Step B), a slot owned by *this* `AGENT_ID` — tolerated, not a blocker (it is `mine`, not `other`). The single-session orchestrator finishes its loop when the backlog is empty **and** its window has no live workers, then runs the final-suite path (decision 6).

### 6. Coexistence with legacy multi-terminal orchestrators

**Decision: single-session mode is just one more agent-id in the existing claim arbitration. No special-casing. The claim layer already arbitrates; the final-suite lockfile already serializes the suite.**

- **Claim arbitration.** The single-session orchestrator has one `AGENT_ID = hostname.pid` like any orchestrator. Its N claimed slots carry that same id. A multi-terminal sibling's `pick-req.sh` excludes those slots by footprint just as it excludes another terminal's slots. Conversely, the single-session orchestrator's `pick-req.sh` excludes the siblings' slots. The arbitration is symmetric and already correct — N-wide claiming from one process is indistinguishable, to the picker, from N processes each claiming once.
- **Heartbeat / staleness.** Each dispatched worker keeps its own slot's heartbeat fresh (per `run-worker.md` Step 1b / REQ-204's checkpoint-stamping replacement). A multi-terminal sibling's stale scan treats a single-session worker's slot exactly like any other slot. **This design does not change the heartbeat mechanism** — it consumes whatever REQ-204 lands.
- **Merge contention.** Both a single-session orchestrator and a multi-terminal sibling merge into the same base branch. The existing Step 4a 5-retry backoff (decision 3) is precisely the mechanism that absorbs a merge that collides with a sibling's just-landed commit. Disjoint footprints mean these are sync conflicts, resolved by rebase-and-retry.
- **Final-suite lockfile.** The "last orchestrator to finish runs the suite" contract (`run.md` When the Backlog is Empty, Steps B–E) is unchanged. The single-session orchestrator runs its drain check (backlog empty + no `other`-owned slots), then races for the committed `final-suite-running.md` lockfile against any multi-terminal siblings. Whichever process commits the lockfile first runs the suite; the rest idle-exit. A single-session orchestrator is one contender in that race like any other — its internal N-way fan-out is invisible at the lockfile layer because by the time it reaches the drain check, its own workers have all returned and their slots are drained.

### 7. Out of scope

- **Milestone deploy gates stay single-flow.** `run.md` Step 7b (the deploy-gate y/n prompt) is non-delegable and owned by exactly one orchestrator. Single-session mode does **not** parallelise gate handling: when a worker reports `milestone_complete: true`, the orchestrator runs the existing first-to-detect drain check and surfaces the single y/n prompt. The N-way fan-out pauses new claims while the gate is open (the active-milestone backlog is, by definition, drained when the gate fires). No change to gate semantics.
- **The coordination lib is untouched.** `pick-req.sh`, `claim-req.sh`, `check-footprint.sh`, `scan-stale.sh`, `deadlock-check.sh`, `run-ledger.sh` keep their current contracts. This mode is a run-loop shape change, not a primitive change.
- **The heartbeat mechanism is owned by REQ-204 (R5).** This design references it but does not redesign it.
- **No cross-machine scheduling.** Single-session parallelism is within one process on one machine; multi-machine parallelism remains the multi-terminal path.

---

## Worked cycle — one full fan-out → return → gated integration → refill

The table below traces a single representative cycle with `--parallel 3` against a backlog of disjoint-footprint REQs, mapped to existing `run.md` steps. `W1/W2/W3` are dispatched workers; queue is the merge queue (decision 3).

| # | Actor | Action | Maps to `run.md` |
|---|---|---|---|
| 1 | Orchestrator | Pre-flight: branch/dir checks, `mkdir -p state/`, resolve `AGENT_ID`, scan/classify `working/` (informational). | Pre-flight §1–§3 |
| 2 | Orchestrator | **Fill the window (claim-as-slot-frees, decision 2):** `pick-req.sh`→`claim-req.sh` for REQ-A; repeat for REQ-B, REQ-C. Each claim lands in `working/` before the next pick, so footprints mutually exclude. | Step 1 (×3) |
| 3 | Orchestrator | **Fan out (decision 1):** three concurrent `Agent` dispatches W1(REQ-A), W2(REQ-B), W3(REQ-C) in one turn. Announce each. | Step 2 (×3 concurrent) |
| 4 | Workers | Each runs TDD red→green in its own worktree on `req/REQ-*`, stamps heartbeat at checkpoints, commits on its feature branch, returns YAML. They do **not** merge/archive/teardown. | `run-worker.md` Steps 1–8 |
| 5 | W2 | Returns first (`status: done`) — arrival order, not REQ order. Orchestrator enqueues W2's report. | Step 3 entry |
| 6 | Orchestrator | **Stage A (concurrent, read-only) for W2:** acceptance-evidence check → policy check → independent review dispatch. All pass. | Step 3 gates |
| 7 | Orchestrator | **Stage B (serial, single-writer) for W2:** ledger → `git merge --no-ff req/REQ-B` from main tree → archive REQ-B → teardown worktree + `git branch -d` → metadata commit. Slot B frees. | Step 3b, Step 4a–4d |
| 8 | Orchestrator | **Refill (decision 2):** `pick-req.sh`→`claim-req.sh` for REQ-D (now unblocked / no longer overlapping the freed slot); dispatch W4(REQ-D). Window back to 3 live workers. | Step 1 + Step 2 |
| 9 | W1, W3 | Return (in either order). Each enqueued; Stage A may run concurrently across both; Stage B drains them one at a time. If W3 hit a stopper, it diverts to Recover (decision 5) without blocking W1's integration; its slot frees and a refill is claimed. | Step 3 → Step 4 or Step 5 |
| 10 | Orchestrator | Loop continues: maintain ≤3 live workers, draining the merge queue serially, until `pick-req.sh` returns empty **and** no live workers remain. | Step 8 → When Backlog Empty |
| 11 | Orchestrator | Drain check (backlog empty, no `other`-owned slots) → race for committed `final-suite-running.md` lockfile → lock-holder runs the full suite → release → completion report. | When Backlog Empty, Steps B–E |

**Serialization invariant restated:** rows 7 and the Stage-B half of row 9 are the *only* places the main working tree and `.do-work/` are written, and they never overlap — the queue admits one report to Stage B at a time. Rows 3, 6, and the Stage-A half of 9 are the only concurrency, and they are all worktree-local or read-only.

---

## Why this doesn't contradict any existing coordination primitive

- **`pick-req.sh` overlap exclusion** stays the sole footprint authority; decision 2 calls it serially between claims so its `working/` view is always current.
- **`claim-req.sh` atomicity** is per-REQ; calling it N times from one process is identical to N processes calling it once.
- **`run.md` Step 4 (merge from main tree)** already serializes merges through one working tree; the merge queue makes that ordering explicit without changing the merge command, the 5-retry backoff, or the archive/teardown sequence.
- **`run.md` Rules** ("one REQ per orchestrator in `working/` at a time — multiple in-flight REQs across parallel orchestrators are normal") generalises cleanly: single-session mode is N in-flight REQs under one orchestrator, which the Rules section already anticipates as the parallel norm. REQ-221 should update that Rules bullet to read "N in-flight REQs per orchestrator under `--parallel N`" so the doc stays canonical.
- **When-the-Backlog-is-Empty drain/lock** is reused unchanged; the single-session orchestrator is one lockfile contender.

---

## Handoff to REQ-221 (implementation)

REQ-221 implements this by editing `agents/run.md` to add a `--parallel N` branch around The Loop:

1. Parse `--parallel N`, clamp to `min(N, 10)`, read `parallel.max_workers` default. `N=1` ⇒ existing serial path (no behavioural change).
2. Replace the single Step 1→Step 2 with a **window fill** (pick/claim/dispatch loop up to N) and a **merge queue** drain (Stage A concurrent, Stage B serial) plus **refill on slot free**.
3. Reuse Steps 3, 3b, 4, 5 verbatim per dequeued report — no internal changes to those steps or to any lib script.
4. Add `parallel.max_workers` to `agents/config.md` and the `--parallel` flag to the run command surface in `SKILL.md`/`commands`.
5. Update the `run.md` Rules "one REQ … at a time" bullet to state the per-orchestrator window.

No lib script changes. No new state files. No new stopper reasons.
