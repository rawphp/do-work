# Commands reference

Lookup for `/do-work` commands: what each one does, when to use it, and which flags exist in the skill today.

Invoke with no subcommand for help plus suggested next steps:

```text
/do-work
```

## Command map (when to use which)

| Goal | Command |
|------|---------|
| First-time project folders | `/do-work install` |
| Align old `.do-work/` with current skill | `/do-work upgrade` |
| New work end-to-end (define) | `/do-work start [brief]` |
| Execute a defined UR | `/do-work go UR-NNN` |
| Record brief only | `/do-work intake [brief]` |
| Creative review only | `/do-work ideate UR-NNN` |
| Grill the brief | `/do-work question UR-NNN` |
| Decompose only | `/do-work capture UR-NNN` |
| Score coverage only | `/do-work verify UR-NNN` |
| Sharpen REQ quality | `/do-work audit UR-NNN` |
| Run backlog (no verify gate) | `/do-work run [UR-NNN]` |
| Live situation room | `/do-work status [UR-NNN]` |
| Stuck REQ → backlog | `/do-work unblock REQ-NNN` |
| Re-dispatch stopped REQ | `/do-work resume REQ-NNN` |
| Validate integrated UR paths | `/do-work close UR-NNN` |
| Learn from run history | `/do-work retro` |
| Draft social posts | `/do-work log` |

---

## Orchestrators

### `/do-work start [brief]`

**Job:** Record a brief and build the REQ backlog in one shot.

**Pipeline:** intake → ideate (default) → capture. Does **not** run verify or implementation.

| Flag | Effect |
|------|--------|
| `--no-ideate` | Skip ideate and its Grill/Continue/Stop gate |
| `--no-layers` | Skip layer-coverage checks for this UR; records `layers_in_scope: []` |

**Notes:**

- Auto-installs `.do-work/` if missing
- Ideate gate: **Grill** / **Continue** / **Stop** (Stop halts before capture)
- After success, may offer next steps (Run Go / Verify only / Skip) when `next_steps.enabled` is true

**Example:**

```text
/do-work start Add password reset email with rate limiting
/do-work start Quick typo fix in README --no-ideate --no-layers
```

### `/do-work go [UR-NNN]`

**Job:** Verify coverage for a UR, then audit and run when the confidence gate passes.

**Pipeline:** verify → (if gate passes) audit → run → optional close offer → optional log.

| Flag | Effect |
|------|--------|
| `--force` | Run even if score &lt; threshold; verify still runs |
| `--auto-fix` | One verify pass that creates missing REQs, re-scores; run only if ≥ threshold afterward |
| `--no-layers` | Skip layer-coverage checks; passed through to capture if `--auto-fix` re-runs capture |

**Threshold:** `verify.threshold` in `.do-work/config.yml` (default **90**).

**Example:**

```text
/do-work go UR-001
/do-work go UR-001 --auto-fix
/do-work go UR-001 --force
```

---

## Setup

### `/do-work install`

Creates the per-project `.do-work/` folder structure and default `config.yml` in the current project.

Use when you want structure before the first brief. `/do-work start` also installs automatically.

### `/do-work upgrade`

Brings existing `.do-work/` state into conformance with the current skill (detectors + fixes). Destructive rows require interactive confirmation. Idempotent.

Use after upgrading the skill install when help or startup mentions pending migration / stale config keys.

---

## Define work (granular)

### `/do-work intake [brief]`

Records the brief **verbatim** as the next `UR-NNN/input.md`. No decomposition.

Use when you want the UR on disk before ideate/capture, or to script the pipeline yourself.

### `/do-work ideate [UR-NNN]`

Surfaces assumptions, risks, and connections into `UR-NNN/ideate.md`. Ends with the interactive gate when run in flows that expect it.

Use to pressure-test a brief without starting capture yet (or re-run after edits).

### `/do-work question [UR-NNN]`

Grills you one question at a time about the brief (assumptions, gaps, constraints).

Use from the ideate **Grill** path or standalone when the brief is thin.

### `/do-work capture [UR-NNN]`

Decomposes `input.md` (and `ideate.md` if present) into backlog `REQ-NNN-slug.md` files. Applies layer rules, integration blocks, dependency cycle checks.

Use to resume after a failed start-at-capture, or to re-decompose after you edited the brief.

---

## Check quality

### `/do-work verify [UR-NNN]`

Scores REQ coverage against the original brief (0–100%) and lists gaps. Includes layer, integration-block, and partial-confidence structural checks.

| Flag | Effect |
|------|--------|
| `--auto-fix` | Create missing REQs, then re-score |

Use before `run` when you are not using `go`, or after manual REQ edits.

### `/do-work audit [UR-NNN]`

Interrogates acceptance criteria quality; auto-fixes vague spots; reports changes. Always runs inside `go` when execution will proceed; does not re-score verify.

Use standalone to sharpen REQs without starting the run loop.

---

## Execute and observe

### `/do-work run [UR-NNN]`

Executes the backlog: claim REQ → worker TDD loop → evidence validation → policy checks → post-build review → archive/ledger. Optional `UR-NNN` limits work to that UR’s REQs.

Does **not** run the verify confidence gate (unlike `go`).

| Flag | Effect |
|------|--------|
| `--parallel N` | One terminal dispatches up to N concurrent workers (default serial; capped at 10). Uses `parallel.max_workers` defaults when applicable |
| `--budget <amount>` | Cap estimated model spend for this run; overrides `cost.budget`. Stops at the next REQ boundary after the in-flight REQ finishes integration. Empty budget = unlimited |

**Parallelism without flags:** open multiple terminals and run `/do-work run` in each; claims coordinate via the filesystem/`git mv`.

### `/do-work status [UR-NNN]`

Read-only situation room: live REQs first (working + backlog), claimers (`hostname.pid`), heartbeats, deadlock warnings, coverage rollup. Unscoped archive is capped to recent completed rows; pass `UR-NNN` to list every matching archived REQ.

Use whenever something looks stuck or you are running parallel workers.

### `/do-work unblock REQ-NNN`

Forces a REQ out of `working/` back to the backlog: strips claim stamp, resets status. Includes judgment when partial commits exist.

Use when a worker died, heartbeat is stale, or you need to break a deadlock after triage with `status`.

Requires a REQ id (example: `/do-work unblock REQ-042`).

### `/do-work resume REQ-NNN`

Re-dispatches a fresh worker for a **stopped** REQ while preserving the claim and refreshing the heartbeat.

Use after `concurrent-conflict` or a transient worker failure—not as a substitute for `unblock` when the claim should be cleared.

Requires a REQ id (example: `/do-work resume REQ-042`).

### `/do-work close UR-NNN`

Validates the integrated result of a UR against the verbatim brief: walks path-unit entry points to terminal states and writes a closure report under the UR folder.

Requires a UR id. `go` may offer close after a clean drain when path-unit REQs exist and no `closure.md` yet. Closure gaps do not block the log step.

---

## Learn and publish drafts

### `/do-work retro`

Mines the run ledger (and related feedback signals) into a human report and regenerates `.do-work/state/calibration.md` as advisory capture guidance.

Use after several runs when you want capture to learn from history.

### `/do-work log`

Generates build-in-public **draft** posts for platforms listed in `log.platforms` (for example `x`, `linkedin`, `blog`). You choose drafts; history is recorded so the same work is not re-prompted forever.

Skipped when `log.enabled` is false or `platforms` is empty. `go` can trigger log automatically after a clean run.

---

## Quick reference table

Same surface as README / SKILL quick reference:

| Command | What it does |
|---------|--------------|
| `/do-work start [brief]` | Brief + REQs; ideate on by default |
| `/do-work start [brief] --no-ideate` | Skip creative review |
| `/do-work start [brief] --no-layers` | Skip layer checks for this UR |
| `/do-work go [UR-NNN]` | Verify; auto-run if ≥ threshold |
| `/do-work go [UR-NNN] --force` | Verify + run regardless of score |
| `/do-work go [UR-NNN] --auto-fix` | Verify, fix gaps once, run if ≥ threshold |
| `/do-work go [UR-NNN] --no-layers` | Verify + run; skip layer checks |
| `/do-work install` | Create `.do-work/` |
| `/do-work upgrade` | Conformance fixes for `.do-work/` |
| `/do-work intake [brief]` | Verbatim UR only |
| `/do-work capture [UR-NNN]` | UR → REQ files |
| `/do-work question [UR-NNN]` | Interactive grilling |
| `/do-work audit [UR-NNN]` | REQ quality pass |
| `/do-work ideate [UR-NNN]` | Assumptions and risks |
| `/do-work verify [UR-NNN]` | Coverage score + gaps |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + create missing REQs |
| `/do-work run [UR-NNN]` | Execute backlog (optional UR scope) |
| `/do-work run --parallel N` | Single-session parallel workers |
| `/do-work run --budget <amount>` | Spend cap for the run |
| `/do-work status [UR-NNN]` | Situation room |
| `/do-work close UR-NNN` | Integrated UR closure report |
| `/do-work unblock REQ-NNN` | Stuck REQ → backlog |
| `/do-work resume REQ-NNN` | Re-dispatch stopped REQ |
| `/do-work retro` | Ledger → calibration report |
| `/do-work log` | Build-in-public drafts |
| `/do-work` | Help |

## Related

- [Getting started](getting-started.md)
- [Concepts](concepts.md)
- [Troubleshooting](troubleshooting.md)
- Config schema: [`agents/config.md`](../agents/config.md)
