# Parallel run mode + empty-backlog drain (reference)

One hop from [`agents/run.md`](../agents/run.md). Load only when effective window width `N > 1`, or when the serial loop reaches empty-backlog drain.

---

## Parallel Run Mode

> **Entered only when the effective window width `N > 1`** (see `## When Invoked → Parallel window width`). When `N == 1` this entire section is skipped and `## The Loop` runs serially, byte-for-byte unchanged.
>
> **Authority:** this section transcribes `docs/design/single-session-parallel.md` (REQ-220). Each subsection cites its design decision. If any decision proves unimplementable as written, stop with `ambiguous-criteria` naming the design section — do not improvise coordination semantics.

Single-session parallel mode is **one orchestrator dispatching up to `N` concurrent workers from one terminal**, then integrating their results through a **serialized merge queue**. Every safety primitive (`pick-req.sh` overlap exclusion, `claim-req.sh` atomicity, dependency ordering, worktree isolation, heartbeat staleness, the final-suite lockfile) is reused unchanged. What changes is only the shape of the hot path: from serial `claim → dispatch → wait → integrate` to windowed `claim K → dispatch K → integrate as each returns → refill`.

Pre-flight (`## Pre-flight Check`) runs exactly as in serial mode — branch/dir checks, `mkdir -p state/`, `AGENT_ID`, context pack, the informational `working/` scan. A non-empty `mine` bucket is resumed first (those REQs occupy window slots before any new claim).

### P1. Fan-out mechanism — concurrent `Agent` dispatches (design §1)

Fan out via **N concurrent `Agent`-tool dispatches in one turn** — the same worker-dispatch surface serial mode uses at `## The Loop` Step 2. The harness runs concurrent tool calls in a single turn in parallel. Do **not** delegate fan-out to a Workflow/scheduler primitive: the `Agent` tool is the only dispatch surface guaranteed wherever serial mode works, it keeps the announce/return checkpoints that logging, the ledger (Step 3b), and stopper-surfacing all hang off, and it keeps resume granularity at one REQ. Each dispatch carries the identical five-input worker contract from Step 2 (REQ path, UR path, prior-REQ paths, context-pack path, resolved `$SKILL_ROOT`, plus `run-worker.md` inline). Announce each at claim time exactly as Step 1's announce line.

### P2. Window fill — claim-as-slot-frees (design §2)

**Claim one REQ immediately before each dispatch — never a batch up front.** `pick-req.sh` reads `working/` directly to build its footprint-exclusion set, so a claim must be *visible in `working/`* before the next pick or two picked candidates could overlap each other.

**Fill loop** (run at start, and again on every refill):

```
while live workers < N:
    REQ_PATH = pick-req.sh "$SCOPE" "$AGENT_ID"      # Step 1 picker, unchanged
    if REQ_PATH is empty: break                       # nothing claimable right now
    claim-req.sh "$REQ_PATH" "$AGENT_ID"              # Step 1 claim, atomic, lands in working/
    classify + select model (## REQ Classification, ## Model Selection)
    dispatch worker (P1) and count it as a live worker
```

- Each `claim-req.sh` updates `working/` before the next `pick-req.sh`, so the next pick automatically skips overlapping and now-claimed REQs. **Never `pick-req.sh × K` then claim.**
- **Overlapping candidates:** the first claimed wins the slot; the rest are excluded by the overlap filter on the next pick and stay in the backlog. They become claimable again only when the winning slot drains (its REQ is integrated and leaves `working/`). Identical to multi-terminal behaviour — no new arbitration.
- A claimed-but-not-dispatched gap is impossible: each claim is immediately followed by its dispatch in the same fan-out turn.
- **Claim races / errors** are handled exactly as `## The Loop` Step 1 (`claim-req.sh` exit 2 ⇒ re-pick; other non-zero ⇒ backoff/re-pick, stop after 3 consecutive non-race failures).
- **Picker returns empty while slots are free:** do not idle-wait the way serial Step 1 does — live workers are still running and will free footprints as they integrate. Break the fill loop and go drain the merge queue (P3); refill again after each slot frees. Only when the window is fully empty **and** `pick-req.sh` returns empty do you fall through to `## When the Backlog is Empty`.

> **JUDGMENT:** J8 — when the window has free slots but the picker returns empty, prefer draining ready workers over blocking. A footprint freed by an integrating peer may unblock the next pick. Surface to the user only via the existing empty-backlog / deadlock paths once **no** workers are live.

### P3. The merge queue (design §3)

Workers return on `req/REQ-NNN` branches concurrently and **in any order** (a fast REQ dispatched second can return before a slow one dispatched first). Every gate after dispatch must serialize the single-writer tail. The merge queue is one in-orchestrator **FIFO of returned worker reports awaiting integration, ordered by arrival** — not by REQ number.

Arrival order is correct because footprints are disjoint by construction (no two queued REQs touch the same files) and dependency ordering is already enforced upstream at claim time (`pick-req.sh` will not hand out a REQ whose `**Depends on:**` are unarchived). The queue never needs to reorder for deps, and arrival order avoids head-of-line blocking.

Each dequeued report runs **exactly the existing serial Steps 3–4, internals unchanged**, split into two stages:

**Stage A — concurrent, read-only (safe N-wide).** May run across multiple queued reports in parallel; writes nothing to the base branch or `.do-work/` lifecycle state:
1. Step 3 — acceptance-evidence gate (`check-acceptance-evidence.sh`)
2. Step 3 — policy gate (`check-policy.sh`)
3. Step 3a/3b — **independent review dispatch** (`review.md` as a fresh subagent; adversarial mode per Step 3b when `review.adversarial` + policy exit 2). Review reads only `(REQ, diff, evidence)` with no run context, so its dispatches may be fanned out concurrently — the same `Agent`-tool concurrency used for workers — keeping review latency off the critical path.

**Stage B — serial, single-writer (one REQ at a time).** A report enters Stage B only after passing **every** Stage A gate. Run the existing Step 3b ledger + Step 4 substeps in order:
4. Step 3b — ledger entry (`run-ledger.sh`)
5. Step 4a — `git merge --no-ff req/REQ-NNN` from the **main working tree** (never a worktree)
6. Step 4b — archive the REQ file (closure-proof + path-unit guards unchanged)
7. Step 4c — tear down the worktree + `git branch -d`
8. Step 4d — commit the metadata change

**Serialization invariant:** at most one Stage B sequence touches the main working tree and `.do-work/` at any instant — exactly as serial mode. This invariant is enforced by a **real, self-healing lock** (not prose-only). The lock is acquired before Step 4a and released after Step 4d (or immediately on any diversion to Recover). Only after an entry finishes Step 4d (or diverts to Recover) do you admit the next report to Stage B. After each Stage B completion the freed slot triggers a P2 refill.

**Stage B lock implementation.** The lock is provided by `lib/stage-b-lock.sh` with the `with-lock` subcommand:

```bash
lib/stage-b-lock.sh with-lock <command> [args...]
```

Runs `<command>` while holding an exclusive lock. The lock uses `python3`'s `fcntl.flock(LOCK_EX)`, which:
- Is portable across macOS and Linux (no hard `flock(1)` dependency)
- Auto-releases when the holding process exits (kernel guarantee — no stale locks)
- Is held in the lock file `$STATE_DIR/stage-b.lock` (runtime-only, gitignored)

**Usage for Stage B:** wrap the 4a–4d sequence (and any diversion to Recover) in the lock wrapper:

```bash
lib/stage-b-lock.sh with-lock bash -c "
  git merge --no-ff req/REQ-NNN || exit \$?
  # ... 4b, 4c, 4d ...
"
```

If acquisition fails because another Stage B holds the lock, the wrapper blocks until the lock is available (serialization is enforced). Because the lock auto-releases on process death, an orchestrator crash mid-Stage-B cannot strand the lock — no manual cleanup is needed.

**Stage B MUST NOT be fanned out.** Stage B is a sequence of self-run git/DB ops the orchestrator issues sequentially — it **MUST NOT be fanned out** across parallel Agent/tool dispatches the way Stage A reviews may (see Stage A, item 3, which explicitly allows concurrent review dispatches). Only one Stage B sequence may run at a time, and it must run in the orchestrator's own process (not delegated). The lock enforces this; any attempt to run Stage B concurrently will serialize at the lock.

**Git's index lock is the structural backstop.** Even if the lock were bypassed (e.g., by manual intervention or a bug), git's `.git/index.lock` provides a loud, recoverable failure mode. Any accidental double-admission that reaches `git merge` will fail at the index lock, and the existing 5-retry path (Step 4a conflict handling) will recover. This is not the primary enforcement — the lock is — but it guarantees that a concurrency bug cannot cause silent corruption.

**Why the final-suite lockfile is the wrong model here.** The final-suite committed lockfile (Step C, ~lines 120–148) solves a **cross-orchestrator** race: two orchestrators both passing the drain check and racing to run the suite. That pattern needs a committed lockfile because the lock must be visible to sibling processes (different machines or different terminal sessions). Stage B is **intra-orchestrator** — a single orchestrator's own merge queue. A process-scoped lock (flock) is the right primitive: it auto-releases on crash, avoiding the stale-lock failure mode that a committed lockfile would introduce for intra-process use. The final-suite lockfile would be the wrong model for Stage B because:
1. It requires explicit release → stale-lock risk if the orchestrator crashes mid-Stage-B
2. It's designed for cross-orchestrator visibility, which Stage B doesn't need
3. A process-scoped flock is simpler and safer for single-writer, intra-process serialization

**Conflict handling mid-queue — reuse Step 4a verbatim, do not invent a new retry path.** On text-level conflict (`<<<<<<<`): `git merge --abort`, then the existing **5-retry exponential backoff** (5s / 15s / 30s / 60s), each attempt re-syncing the base branch and re-merging. On the 5th failure: leave the `req/REQ-NNN` branch alive, transition the REQ to `**Status:** stopped`, `**Reason:** concurrent-conflict`, surface to the user, and **continue draining the rest of the queue** — a conflict on one queued REQ must not abort the others. Resumable via `/do-work resume REQ-NNN`. Because footprints are disjoint, a content conflict between two queued REQs should not occur; the retry path absorbs conflicts against concurrent multi-terminal siblings or a remote (P5).

> **JUDGMENT:** J9 — admit reports to Stage B in arrival order, one at a time; never hold a ready report waiting for a slower lower-numbered REQ. A Stage A failure or a Stage B 5-retry exhaustion on one report diverts only that report to Recover (P4) and never blocks its siblings.

### P4. Failure isolation (design §5)

**One worker (or one queued integration) stopping must never abort its siblings.**

- A worker returning `status: stopped` / `failed`, or a Stage A gate failure on its report, is handled **exactly** as serial Step 5 (Recover) and `## Stopping Rules`: the REQ stays in `working/` with `**Status:** stopped` + `**Reason:**`; the orchestrator surfaces the stopper. The difference under parallelism: **do not halt the loop** — record the stopper, **free that window slot**, and (if backlog remains) claim a refill (P2). The other workers and any queued ready reports proceed untouched.
- **Stoppers are queued per-REQ and surfaced in arrival order**, one decision at a time. When `next_steps.enabled` is true **and** standalone, each stopper surfaces via `AskUserQuestion` (Show details / Retry / Skip) as in serial mode. When the gate is closed (delegate mode or `next_steps.enabled=false`), each stopper prints its `details` and the loop continues — no auto-retry. The per-REQ retry counter and ambiguous-criteria feedback (`## Stopping Rules`) apply per REQ, unchanged.
- **No new stopper reasons.** The `## Stopping Rules` enum is complete; `concurrent-conflict` (P3 5-retry exhaustion) is already in it.
- **Drain accounting.** A stopped REQ left in `working/` is, for the empty-backlog drain check (`## When the Backlog is Empty` Step B), a slot owned by *this* `AGENT_ID` — `mine`, tolerated, not a blocker. The single-session orchestrator finishes its loop when the backlog is empty **and** its window has no live workers, then runs the final-suite path (P5).

### P5. Coexistence with multi-terminal orchestrators (design §6)

Single-session mode is **just one more agent-id in the existing claim arbitration — no special-casing.**

- **Claim arbitration.** This orchestrator has one `AGENT_ID = hostname.pid`; its N claimed slots all carry it. A multi-terminal sibling's `pick-req.sh` excludes those slots by footprint just as it excludes any terminal's slots, and vice-versa. N-wide claiming from one process is indistinguishable, to the picker, from N processes each claiming once.
- **Heartbeat / staleness.** Each dispatched worker keeps its own slot's heartbeat fresh (`run-worker.md` checkpoint-stamping). A sibling's stale scan treats a single-session worker's slot like any other. This mode does **not** change the heartbeat mechanism.
- **Merge contention.** Both this orchestrator and a multi-terminal sibling merge into the same base branch. The Step 4a / P3 5-retry backoff is precisely what absorbs a merge that collides with a sibling's just-landed commit — a sync conflict resolved by rebase-and-retry.
- **Final-suite lockfile.** `## When the Backlog is Empty` (Steps B–E) is reused unchanged. The single-session orchestrator runs its drain check (backlog empty + no `other`-owned slots) only after its own N workers have all returned and drained, then races for the committed `final-suite-running.md` lockfile like any other contender. Its internal N-way fan-out is invisible at the lockfile layer.

### P6. Out of scope — deploy gates stay single-flow (design §7)

- **Milestone deploy gates are NOT parallelised.** Step 7b (the deploy-gate y/n prompt) is non-delegable and owned by exactly one orchestrator. When a worker reports `milestone_complete: true`, run the existing first-to-detect drain check (Step 7b) and surface the single y/n prompt. The N-way fan-out **pauses new claims while the gate is open** (the active-milestone backlog is, by definition, drained when the gate fires). No change to gate semantics.
- **The coordination lib is untouched.** `pick-req.sh`, `claim-req.sh`, `check-footprint.sh`, `scan-stale.sh`, `deadlock-check.sh`, `run-ledger.sh` keep their current contracts. This mode is a run-loop shape change, not a primitive change. No new state files, no new stopper reasons.

---

## When the Backlog is Empty

The final cross-REQ test suite must run exactly once per drained backlog — fired by the **last orchestrator to finish**, not whichever orchestrator happens to observe the empty backlog first. Under N-way parallelism, this section guarantees that property via an explicit drain check and a committed lockfile.

### Step A — Trigger

Reached when the claim step (Step 1, REQ-114) returns no claimable REQ **and** this orchestrator has just archived its previous REQ. (Pre-flight empty-backlog also lands here — see `## Pre-flight Check` Step 5.)

### Step B — Drain check (am I the last?)

Before running the suite, classify the live state by reading ownership stamps (per `## Agent Identity` and REQ-113):

1. **Backlog root:** glob `{project}/.do-work/REQ-*.md`. Must be empty.
   - In milestone mode (`{project}/.do-work/state/active-milestone.md` exists), glob `{project}/.do-work/REQ-M<active>-*.md` instead.
2. **Working slots:** glob `{project}/.do-work/working/REQ-*.md` (milestone mode: `working/REQ-M<active>-*.md`). For each slot file, read its `<!-- claimed-start --> … <!-- claimed-end -->` block and classify by `**Claimed by:**`:

   | Classification | Condition |
   |---|---|
   | `mine` | Stamp's `**Claimed by:**` equals local `AGENT_ID`. Tolerated — at most one, the just-archived REQ's transient state. Not a blocker. |
   | `other` | Stamp's `**Claimed by:**` differs from local `AGENT_ID`. A sibling is still in flight — drain check **fails**. |
   | `other` (defensive) | No stamp present (legacy / malformed slot). Treat as `other` — the local agent must not run the suite without checking with siblings. |

3. **Drain check passes** iff backlog glob is empty AND no slot is classified `other`. Proceed to Step C.
4. **Drain check fails** (one or more `other` slots): proceed to Step E (sibling idle exit).

### Step C — Lockfile acquisition (sibling-also-drained race)

Two orchestrators can both pass the drain check at near-the-same instant (each just archived its own REQ, neither sees the other's slot). The lockfile is the tiebreaker.

Lockfile path:
- Non-milestone mode: `{project}/.do-work/state/final-suite-running.md`
- Milestone mode: `{project}/.do-work/state/final-suite-M<active>-running.md`

Acquisition sequence (first-to-commit wins):

1. Check whether the lockfile already exists. If yes, another orchestrator already holds the suite — proceed to Step E (sibling idle exit), substituting "Sibling is running the final suite" framing.
2. Write the lockfile with a single block:

   ```markdown
   **Held by:** <agent-id>
   **Started at:** <ISO-8601 UTC>
   ```

3. Stage and commit atomically:

   ```bash
   git add {project}/.do-work/state/final-suite-running.md      # or final-suite-M<n>-running.md
   git commit -m "chore: final-suite lock"
   ```

   - **Commit succeeds:** this orchestrator holds the lock. Proceed to Step D.
   - **Commit fails** (e.g. sibling won the race, working tree shows their lockfile already committed, or merge conflict on the lockfile): treat as lost race. Discard local lockfile changes (`git checkout -- <lockfile>` then `rm -f <lockfile>` if still present), then proceed to Step E.

The lockfile is intentionally committed *before* running the suite so other orchestrators can observe the lock even if the suite hangs.

### Step D — Run the suite (lock-holder only)

This orchestrator holds the lockfile. Run the project's full test suite as a cross-REQ safety net.

1. **Suite command resolution** — unchanged. Use `config.test.suite_command` if set; otherwise try defaults in order (`npm test`, `npx vitest run`, `./vendor/bin/pest`), checking the runner exists before executing. If none found, log `No test suite configured or detected — skipping full suite run` and skip to Step D.4.
2. **Execute** the suite command.
3. **On failure** — apply the existing failure-attribution + 3-attempt fix loop unchanged: map failing test files to REQ commits via `git diff-tree --no-commit-id --name-only -r <hash>`, report the likely responsible REQ, fix the implementation, re-run; after 3 failed attempts, stop and report to the user.
4. **Release the lockfile** (regardless of pass/fail):

   ```bash
   git rm {project}/.do-work/state/final-suite-running.md      # or final-suite-M<n>-running.md
   git commit -m "chore: final-suite lock released"
   ```

5. Proceed to the completion report below.

### Step E — Sibling idle exit (drain check failed OR lockfile already held)

This orchestrator does NOT run the suite. Emit exactly one idle log line, then exit cleanly:

```
[<agent-id>] Backlog drained for this orchestrator. <N> sibling slot(s) still in flight ([<sibling-agent-id>, ...]).
Sibling will run the final suite when it finishes.
```

The user will see one final-suite report from whichever sibling finishes last. No further work, no polling, no lockfile writes.

### Completion report and prompt

Output the completion report:

```
Do Work loop complete.

Processed: N REQs
Full suite: [passed / skipped — no test runner found]
All outputs committed.
Archive: {project}/.do-work/archive/
```

When the effective budget is armed (non-empty), append a budget line to this report: `Estimated spend: $<SPENT> / budget $<BUDGET> (tier-weighted estimate)`. This is the natural-exhaustion case (backlog emptied before the budget was hit); the **budget-stop report** (Step 3b.1) is the distinct early-stop case where the budget was reached with REQs still remaining.

**Then, immediately after the report**, check whether to present next-step options:

If `config.next_steps.enabled` is `true` **and** this agent is running standalone (not as a delegate inside the go agent):

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Start new work"** — Run intake for a new UR
2. **"Review outputs"** — List archived REQs and their output paths
3. **"Skip"** — End the interaction

If `config.next_steps.enabled` is `false`, missing, or this agent is running as a delegate inside go: skip the AskUserQuestion and stop.

---

