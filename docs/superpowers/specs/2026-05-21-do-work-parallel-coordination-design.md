# do-work: Parallel Coordination Layer

**Date:** 2026-05-21
**Status:** Design approved, awaiting implementation plan
**Scope:** Replace FIFO REQ claiming with a footprint-aware, dependency-aware coordination layer. Add deterministic bash primitives, heartbeat liveness, deadlock detection, recovery commands, and automated feedback collection. Touches `agents/run.md`, `agents/run-worker.md`, `agents/capture.md`, `agents/audit.md`, `agents/verify.md`, the REQ template, the config schema, and adds a `lib/` directory of bash scripts. No new agent .md files except the new commands documented below.

---

## Problem

`/do-work run` is "safe to launch from multiple terminals" today, but the safety is shallow. Orchestrators claim REQs in ascending order via `git mv` and trust that:

1. Two REQs claimed at the same time won't touch the same files.
2. A REQ won't reference a not-yet-archived prerequisite.
3. A worker that dies leaves a recoverable footprint.

None of those hold in practice. The current isolation heuristic (worktree iff the REQ task mentions "migration"/"rename across"/"refactor across" etc.) is a guess based on the REQ's words, not on the actual file footprint or what siblings are doing. Two siblings can take "small" same-branch REQs that quietly edit the same file and stomp each other. The 24-hour stale-slot reclaim window is useless for an agent that died ten minutes ago.

For a backlog of 100 REQs and ten parallel orchestrators, what's needed is a **coordination layer**: a small, file-based situation room every agent reads before deciding what to do, and updates as it works. Siblings know what each other is touching. Dependencies are honored. Conflicts are detected before they happen. Deadlocks are detected if they happen. Friction events become GitHub issues automatically so the system improves over time.

This spec defines that layer.

## Non-goals

- A central daemon, scheduler, or orchestrator-of-orchestrators. The design is file + git + bash, no long-running coordination process.
- Replacing the existing run loop. The orchestrator and worker agents stay; their decision steps gain bash primitives and their stamp/header schemas extend.
- Auto-resolving merge conflicts. Workers still refuse to edit files containing `<<<<<<<`.
- Hard reservation of URs to specific agents. UR scope is a *filter on what this orchestrator will claim*, not a lock that excludes others.
- Distributed locking across machines. Coordination is per-repo via git + filesystem; multi-machine parallelism works because each machine's `hostname.pid` is unique, but no special cross-machine consensus is implemented.

---

## Design

### Pipeline shape

```
backlog REQ files (.do-work/REQ-*.md)
  → orchestrator pre-flight (heartbeat, stale reclaim, scope filter)
  → orchestrator claim cycle (pick-req.sh → claim-req.sh → dispatch worker)
  → worker (TDD red→green, periodic heartbeat, structured report)
  → orchestrator drains backlog or detects deadlock
  → automated feedback for any friction event
```

Steps in **bold** are new or materially changed: pre-flight heartbeat, claim cycle, periodic worker heartbeat, deadlock detection, feedback emission.

### The coordination layer

**Three sources of truth** under `{project}/.do-work/`:

1. **Backlog REQ files** (`REQ-NNN-slug.md`) — pickable work. Header carries scope, footprint, deps.
2. **Working slots** (`working/REQ-NNN-slug.md`) — claimed work. Ownership stamp carries heartbeat.
3. **Archive** (`archive/REQ-NNN-slug.md`) — completed work. Used for dep satisfaction checks.

**No `plan.md` file is stored.** It would be a coordination hotspot — every claim would commit a plan.md change and every commit would merge-conflict with every sibling's commit. The "plan" is a *projection* synthesized on demand by `lib/synth-status.sh`.

**No separate `agents/<agent-id>.md` registry.** Heartbeat data lives in the existing claim stamp inside each working/ slot. One glob of `working/` gives every agent the complete sibling picture.

**Optional state files** (only created when relevant):

| File | When written | When deleted |
|---|---|---|
| `.do-work/state/active-milestone.md` | Milestone mode (existing) | Last milestone deployed |
| `.do-work/state/milestones.md` | Milestone mode (existing) | Never (audit trail) |
| `.do-work/state/gate-owner.md` | Orchestrator owns a deploy gate (existing) | Gate resolved |
| `.do-work/state/final-suite-*.md` | Final suite lock (existing) | Suite released |
| `.do-work/state/deadlock.md` | Deadlock detected (new) | User resolves and runs `/do-work resume` or `/do-work unblock` |
| `.do-work/state/feedback.lock` | `flock` guard for feedback emission (new) | Each call (transient) |

### REQ header schema

Capture writes a **fixed header block** at the top of every REQ. The block is regex-parseable: each field on its own line, value is plain text or comma-separated paths/ids. No multi-line values, no nested structures.

```markdown
# REQ-007: Add Foo model

**UR:** UR-002
**Layer:** backend
**Files:** app/Models/Foo.php, tests/Unit/FooTest.php
**Depends on:** REQ-005
**Status:** backlog
```

| Field | Value | Source |
|---|---|---|
| `**UR:**` | Single UR id | Existing |
| `**Layer:**` | One of the layers declared in `config.yml`, or `none` | Existing |
| `**Files:**` (new) | Comma-separated list of paths/globs the REQ will touch | Capture (judgment) |
| `**Depends on:**` (new) | Comma-separated list of REQ ids that must be archived before this REQ can be claimed; empty allowed | Capture (judgment) |
| `**Status:**` | `backlog`, `in-progress`, `done`, `stopped` | Lifecycle |

When the REQ moves to `working/`, the ownership stamp is inserted directly under the heading (before the header block):

```markdown
# REQ-007: Add Foo model

<!-- claimed-start -->
**Claimed by:** mbp-tom.42137
**Claimed at:** 2026-05-21T13:42:08Z
**Heartbeat:** 2026-05-21T14:08:12Z
<!-- claimed-end -->

**UR:** UR-002
**Layer:** backend
**Files:** app/Models/Foo.php, tests/Unit/FooTest.php
**Depends on:** REQ-005
**Status:** in-progress
```

`**Heartbeat:**` is new. It's the only field updated repeatedly during a worker's run.

### Bash script library

All deterministic operations move into `~/.claude/skills/do-work/lib/`. One responsibility per script. Exit code communicates the decision; stdout is the result the orchestrator needs; stderr is diagnostic.

| Script | Args | Output |
|---|---|---|
| `pick-req.sh` | `<scope>` (UR-NNN or `any`), `<agent-id>` | Path of next claimable REQ to stdout, or empty if none. Stderr lists categorised rejection reasons (`dep:REQ-005`, `overlap:REQ-007`, `scope:UR-001`). |
| `claim-req.sh` | `<req-path>`, `<agent-id>` | Atomic `git mv` + stamp insert + status update + scoped commit. Prints commit short hash on success. |
| `heartbeat.sh` | `<req-path>` | Updates the `**Heartbeat:**` line in the claim stamp. No commit. |
| `check-footprint.sh` | `<req-path>` | Lists working/ slots whose `**Files:**` intersect this REQ's `**Files:**`. Empty = no overlap. |
| `check-deps.sh` | `<req-path>` | Lists REQ ids from this REQ's `**Depends on:**` that are not yet in `archive/`. Empty = deps satisfied. |
| `scan-stale.sh` | (none) | Lists working/ slots whose `**Heartbeat:**` is older than the stale threshold (default 300s). |
| `cycle-check.sh` | `[UR-NNN]` | Validates that the `**Depends on:**` graph (optionally scoped to one UR) is acyclic. Exit 1 if a cycle exists. |
| `synth-status.sh` | `[UR-NNN]` | Renders the live situation as a markdown table (REQ, UR, status, claimer, heartbeat-age, deps-status, footprint). |
| `deadlock-check.sh` | (none) | Diagnoses deadlock conditions. Empty stdout = no deadlock; otherwise prints a structured diagnosis. |
| `file-feedback.sh` | `<event-type>`, `<fingerprint>`, `<context-json>` | Ensures a GitHub issue exists (or comments on the existing one). Respects `feedback.enabled` config. Silent if disabled. |
| `drain-classify.sh` | (none) | Reads stderr categories from a prior `pick-req.sh` run and classifies the backlog: `deps-blocked`, `overlap-blocked`, `scope-blocked`, `truly-empty`. |

**Format rules the scripts depend on** (load-bearing):

- Header fields appear exactly on their own line, in the form `**Field:** value`.
- Path lists are comma-separated, with optional spaces after commas.
- Paths are project-relative.
- Globs are supported in `**Files:**` (e.g. `app/Models/Foo*.php`); overlap check expands globs against the working tree.
- Timestamps are ISO-8601 UTC (`Z` suffix).

Capture is the only writer of the new fields. Audit and verify enforce them.

### Decision logic: the orchestrator claim cycle

```
1. heartbeat.sh <current-slot>         # if we hold a slot, refresh it
2. result=$(pick-req.sh <scope> <agent-id> 2> /tmp/picker-stderr.$$)
3. if [ -n "$result" ]; then
     hash=$(claim-req.sh "$result" "<agent-id>")
     # dispatch worker (LLM step: classification + dispatch via Agent tool)
     # process worker report (existing logic)
     # loop
   else
     classification=$(drain-classify.sh < /tmp/picker-stderr.$$)
     case "$classification" in
       truly-empty)    # fall through to drain check
       deps-blocked|overlap-blocked|scope-blocked)
         # idle-wait: poll 30s, max 30min
         # on each tick: heartbeat.sh on own slot (if any), re-run pick-req.sh
         # if 30min elapsed with no progress: deadlock-check.sh → surface
     esac
   fi
```

The hot path is three bash calls. The model only thinks at three points per cycle: classify subagent_type, select model, dispatch the worker. Everything else is mechanical.

**Pre-flight changes from current `run.md`:**

- The 24h stale window collapses to 5 minutes (configurable via `parallel.stale_threshold_seconds`). Detection is heartbeat-based, not commit-timestamp-based.
- `scan-stale.sh` replaces the inline staleness check.
- The "scan and classify working slots" step in the existing run.md is unchanged in spirit; the implementation moves into the script.

### Heartbeat mechanism

The orchestrator is blocked waiting for a worker to return. It cannot keep a heartbeat fresh on the slot it just dispatched. So heartbeat runs **inside the worker**.

The worker, in its initialization, spawns a background loop:

```bash
( while sleep 60; do lib/heartbeat.sh "$REQ_PATH" || break; done ) &
HEARTBEAT_PID=$!
trap "kill $HEARTBEAT_PID 2>/dev/null" EXIT
```

- Interval: 60 seconds.
- Stale threshold: 300 seconds (5× interval — robust against transient delays).
- The loop self-terminates if `heartbeat.sh` fails (e.g. file vanished after archive).
- The `EXIT` trap kills the loop on clean worker exit.

Heartbeat commits are intentionally avoided — `heartbeat.sh` writes the file via `sed`/`awk` only. Frequent commits would inflate history and amplify merge contention. Sibling orchestrators see heartbeat freshness by reading the working/ file directly, which is filesystem-current without a commit.

### Deadlock detection

`deadlock-check.sh` triggers on any of:

| Signal | Bash check |
|---|---|
| No pickable REQ + working/ non-empty + no `.do-work/` commits in 5 minutes | `git log --since="5 minutes ago" -- .do-work/` returns empty |
| All live slots have stale heartbeats AND backlog non-empty | `scan-stale.sh` returns ≥ count of working/ slots |
| Dependency cycle observed at runtime | `cycle-check.sh` exit 1 (defensive — capture should catch it) |

When triggered:

1. `flock` `.do-work/state/feedback.lock` (so only one agent reacts).
2. Write `.do-work/state/deadlock.md` with the diagnosis.
3. Call `file-feedback.sh deadlock <fingerprint>` with the structured context.
4. Orchestrator surfaces to user via `AskUserQuestion`:
   - Reset stale slots and retry
   - Show situation room (runs `synth-status.sh`)
   - Unblock a specific REQ (`/do-work unblock REQ-NNN`)
   - Abort

If `config.next_steps.enabled` is false or this orchestrator is running as a delegate, print the diagnosis and exit without the question — same pattern as existing stopping rules.

### Recovery taxonomy

| Stuck state | Recovery |
|---|---|
| Heartbeat stale, slot abandoned | Existing batch-prompt: reclaim into this run, return to backlog, or abort |
| Worker `stopped`, reason `concurrent-conflict` | REQ stays in `working/` with `**Status:** stopped` and a `**Reason:**` field. `/do-work resume REQ-NNN` re-dispatches a fresh worker on it. |
| Worker `stopped`, reason `ambiguous-criteria` / `scope-creep` | Surface to user. No auto-retry. User edits REQ or `unblock`s it. File feedback. |
| Worker `stopped`, reason `dependency-missing` | Diagnostic: capture missed a dep. File feedback with the inferred missing dep. User edits `**Depends on:**`. |
| Worktree merge failed after 5 retries | Feature branch stays alive; REQ stopped with `**Reason:** concurrent-conflict`. `/do-work resume REQ-NNN` re-dispatches a worker that checks out the existing feature branch and continues from there. |
| Footprint-miss (worker touched files outside declared `**Files:**`) | At commit-time, the worker diffs `git diff --name-only --cached` against its declared `**Files:**`. Differences are logged + fed back. Does NOT block the commit, but the REQ's `**Files:**` is updated in place to the actual touched paths so future overlap checks are accurate. |

### New commands

| Command | Job | Implementation |
|---|---|---|
| `/do-work status [UR-NNN]` | Render the situation room: REQs + status + claimers + heartbeats + deadlock warnings | `synth-status.sh` |
| `/do-work unblock REQ-NNN` | Force-return a stuck REQ to backlog. Strip ownership stamp, reset status, `git mv` back. If implementation commits exist for this REQ, surface them and ask the user whether to revert, keep, or fold into a new commit. | mostly mechanical; one judgment point (partial-commit handling) |
| `/do-work resume REQ-NNN` | Re-dispatch a worker on a `working/` REQ in `stopped` state. Fresh subagent session. For worktree-mode REQs, checks out the existing `req/REQ-NNN` branch in place. | reuses existing dispatch path |

Existing commands gain small extensions:

- `/do-work go [UR-NNN]` — pre-flight calls `synth-status.sh` and shows the user a snapshot before dispatching. If `deadlock-check.sh` reports a deadlock, `go` halts and surfaces it.
- `/do-work capture` — writes the new `**Files:**` and `**Depends on:**` header fields. Calls `cycle-check.sh` after generation; halts on cycle.
- `/do-work audit` — adds a check that `**Files:**` paths plausibly match the REQ's stated task (e.g. a REQ whose task mentions `app/Models/Foo` should list it in `**Files:**`).
- `/do-work verify` — adds a check that all `**Depends on:**` ids exist in the same UR's REQ set (no dangling references).
- `/do-work run [UR-NNN]` (new optional arg) — UR scope filter for this orchestrator's claims. Passed to `pick-req.sh` as `<scope>`.

### Feedback collection

**One new script:** `lib/file-feedback.sh`. Triggered from specific friction events with a stable fingerprint.

| Event | Fingerprint format | Where it fires |
|---|---|---|
| Deadlock | `deadlock:<signal>:<live-slot-count>:<hash>` | `deadlock-check.sh` consumer |
| Footprint miss | `footprint-miss:<diff-hash>` | Worker Step 8 commit prep |
| Concurrent-conflict after 5 retries | `concurrent-conflict:<files-hash>` | Worker exit path |
| Cycle detected at capture | `cap-cycle:<UR-id>` | `cycle-check.sh` |
| Stale slot reclaim (no recent commit) | `stale-slot:<reason-class>` | Pre-flight reclaim handler |
| Ambiguous-criteria stop, 2nd occurrence on same REQ | `ambiguous-req:<REQ-NNN>` | Orchestrator stopping-rules path |
| Verification-failing after 3 retries | `verify-fail:<step-type>` | Worker exit path |

**Dedup:** body always embeds `<!-- fingerprint: <value> -->`. `gh issue list --search "fingerprint:<value> in:body"` finds priors. Existing issue → `gh issue comment`. No issue → `gh issue create`.

**Rate limiting:** `flock -n .do-work/state/feedback.lock` guards every call. First agent files; siblings exit silently.

**Privacy / sanitization:** every body strips absolute paths, replaces `{project}` with `<project>`, omits commit messages and code diffs. Keeps event type, REQ id, file globs, retry counts, agent count, timestamps. The narrative title and "expected vs actual" body lines are written by the model (one judgment point), constrained by an inline checklist that lists what must NOT appear.

**Config additions** (`{project}/.do-work/config.yml`):

```yaml
feedback:
  enabled: false                              # opt-in
  repo: tomkaczocha/do-work                   # default points at the skill upstream
  label: auto:do-work-feedback
  project_repo: ""                            # optional: route project-class events here
```

**Default routing:**
- *System-class* (deadlock, footprint-miss, concurrent-conflict, cap-cycle, stale-slot) → `feedback.repo`.
- *Project-class* (ambiguous-criteria, verify-fail) → `feedback.project_repo` if set, otherwise `feedback.repo`.

**Self-targeting default:** when running inside the do-work skill's own source repo (detected by `git remote get-url origin` matching the upstream URL pattern), `feedback.enabled` defaults to true.

### Token economy notes

The design's hot path is bash. The orchestrator's per-claim LLM cost is:

- Read the picked REQ's header (when subagent_type/model classification needs it): ~15 lines
- Dispatch the worker via `Agent` tool: classification heuristic + the worker prompt (existing)
- Read the worker's return report: ~15 lines YAML

The synthesized status view (`synth-status.sh` output, rendered to the user, not the model) can be hundreds of lines, but that's a leaf — it doesn't feed back into a model decision.

Compared to a plan.md design: no per-claim plan.md edit, no per-claim plan.md merge, no per-claim plan.md commit. One fewer commit per claim across all agents.

Compared to the current implementation: roughly equal LLM-token cost per claim (the existing stale-slot scan + classification dominate), plus the added cost of one bash invocation. The savings come from *avoiding redo*: footprint-aware claims mean fewer concurrent-conflict retries and fewer stomp-driven re-implementations.

### Judgment points (indexed)

Every agent file gains a top-of-file index of where model judgment is required. The convention is documented once in `CONTRIBUTING.md` and applied across all agent files.

| Agent | Judgment points |
|---|---|
| `capture.md` | Choosing `**Files:**` footprint per REQ; choosing `**Depends on:**` per REQ |
| `audit.md` | Plausibility check that `**Files:**` matches the REQ's stated task |
| `run.md` | Subagent_type classification (existing); model selection (existing); deadlock diagnosis narrative; partial-commit handling in `unblock` |
| `run-worker.md` | Scope-creep vs continue-and-correct decision when a step requires touching a file outside `**Files:**`; narrative title + body for any feedback event filed by the worker |

Marker convention inside an agent file:

```markdown
### 3.2 Write the Files: footprint

> **JUDGMENT:** This is a design decision, not a check. Read the REQ task and predict
> which paths the implementation will touch. List concrete paths and globs. If you're
> unsure, list more not fewer — overlap blocks claims, missing entries cause stomps.
```

### Cycle detection at capture

Capture writes a new REQ's `**Depends on:**` field based on which previously-captured REQs in the same UR introduce data or behavior the new REQ extends. After every capture write, `cycle-check.sh <UR-NNN>` runs.

- Empty stdout, exit 0: graph acyclic, continue.
- Non-empty stdout, exit 1: the script prints the cycle (`REQ-007 → REQ-009 → REQ-007`), capture halts, surfaces to the user.

This catches a class of bug where capture invents a circular dependency — currently impossible because the field doesn't exist, but mandatory to guard against once the field is load-bearing.

### Worktree decisions

Isolation mode stays a per-REQ decision but the signals shift. The existing heuristics in `run-worker.md` (`migration`, `schema change`, `rename across`, `**Layer:** none` ⇒ same-branch, etc.) remain. Two additions:

1. **Overlap-driven worktree.** If `check-footprint.sh` finds overlap at claim-time and the REQ is still desired (e.g. it's the only pickable REQ in scope and would otherwise idle-wait), the orchestrator forces `worktree` mode for the dispatch. This is the only path where worktree mode is chosen based on *live* state rather than REQ content.
2. **Force flag.** Users can add `**Isolation:** worktree` to a REQ explicitly to force worktree mode; capture writes this when the design clearly requires it.

`run-worker.md`'s isolation heuristic gains a check: if the dispatch passed `--isolation=worktree`, honour it regardless of the REQ's content signals.

---

## Files to change

### Skill source (`~/.claude/skills/do-work/`)

| File | Change |
|---|---|
| `SKILL.md` | Document new subcommands (`status`, `unblock`, `resume`), updated REQ header schema, feedback config |
| `agents/run.md` | Replace inline claim/staleness logic with calls to `pick-req.sh`, `claim-req.sh`, `scan-stale.sh`, `heartbeat.sh`. Add deadlock detection path. Add judgment-point index. |
| `agents/run-worker.md` | Add heartbeat background loop. Add footprint-miss check at commit. Add overlap-driven worktree honoring. Add judgment-point index. |
| `agents/capture.md` | Write `**Files:**` and `**Depends on:**` fields. Call `cycle-check.sh`. Add judgment-point index. |
| `agents/audit.md` | Add footprint plausibility check. |
| `agents/verify.md` | Add dangling-dep check. |
| `agents/status.md` (new) | Wraps `synth-status.sh` + `deadlock-check.sh`. |
| `agents/unblock.md` (new) | Reset-a-REQ command with partial-commit judgment. |
| `agents/resume.md` (new) | Re-dispatch worker on a stopped working/ slot. |
| `agents/config.md` | Add `feedback`, `parallel.stale_threshold_seconds` keys. |
| `lib/` (new directory) | All bash scripts listed above. |
| `CONTRIBUTING.md` | Document the judgment-point marker convention. |

### Project state schema (`{project}/.do-work/`)

| File / dir | Change |
|---|---|
| `config.yml` | New `feedback:` and `parallel:` sections |
| `state/deadlock.md` | New file, written on deadlock detection |
| `state/feedback.lock` | New transient lockfile |
| REQ files | New `**Files:**`, `**Depends on:**` header fields; ownership stamp gains `**Heartbeat:**` |

---

## Open questions

1. **REQ retry budget.** Should a REQ that hits `concurrent-conflict` more than N times across separate `/do-work resume` invocations be auto-stopped pending user intervention? Currently the design leaves retries unbounded. Likely answer: track a `**Retries:**` counter in the REQ header, escalate to user after 3.
2. **Cross-machine heartbeat.** ISO timestamps assume clock skew is bounded. For multi-machine setups, NTP is implicit. Not solving until it becomes a problem.
3. **Footprint glob expansion.** When `**Files:**` contains a glob like `app/Models/*.php`, do we expand it once at claim time (snapshot) or every overlap check (live)? Live is more correct but slower. Probably live with a small in-script cache keyed by `(slot-mtime, glob)`.
4. **`/do-work unblock` partial-commit revert.** When implementation commits exist for a REQ being unblocked, the design surfaces them but doesn't auto-revert. Should there be a `--revert-commits` flag for the user who knows they want a clean slate? Likely yes, but defer to implementation.

## Non-decisions

- We do NOT introduce a "queue" file the user manually edits. The backlog *is* the queue. User direction comes through `/do-work run UR-NNN` scope flags, `/do-work unblock`, and editing REQ files directly.
- We do NOT introduce a coordinator process. Every orchestrator is symmetric.
- We do NOT change the existing commit convention (`feat(REQ-NNN): ...`). The new claim commit (`chore(REQ-NNN): claim by <agent-id>`) is the only new commit shape, and it already exists in the current parallel-execution implementation.
