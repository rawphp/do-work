# Design: UR Closure Agent (`/do-work close`)

**Status:** design — approved for implementation
**UR:** UR-035 (R1 / Gap B)
**Parent path-unit:** REQ-209
**Implements:** the end-to-end closure capability
**Children that depend on this doc:** REQ-211 (close agent), REQ-212 (SKILL.md routing), REQ-213 (coverage-rollup distinction)

---

## Problem

Proof in do-work is per-REQ, pre-merge, and produced in isolation. A worker proves its own REQ inside a worktree and writes `**Closure proof:**` (a checkpoint-log + commit reference); `lib/derive-status.sh` then marks that REQ `proven`, and `lib/coverage-rollup.sh` rolls per-Issue `intended/proven/unproven`. Nothing validates the **integrated** result: that after every REQ merges to base, each path-unit's entry point still reaches its declared terminal state in the merged app. Cross-REQ integration drift is checked at capture time (footprint/deps) but never at delivery time. The final suite runs tests only — it cannot observe a route rendering, an endpoint responding, or a CLI command exiting cleanly.

This design specifies a **Issue closure agent**: a fresh subagent that, after a run drains, re-reads the verbatim brief cold and walks every path-unit's entry point in the merged app, producing `{project}/.do-work/user-requests/UR-NNN/closure.md` — a per-path-unit verdict validating end-to-end reachability. It does not fix gaps; it surfaces them.

This layers on the existing spine — verbatim-brief invariant, per-REQ `**Closure proof:**`, the deterministic tested bash lib, evidence-not-assertion archiving. It adds an end-to-end proof tier above per-REQ proof; it replaces nothing.

---

## Decision 1 — Independence (cold dispatch)

**Decision.** The closure agent is dispatched as a **fresh `Agent` subagent** (new context) that is handed exactly three things and nothing else:

1. The verbatim brief: `{project}/.do-work/user-requests/UR-NNN/input.md`.
2. The archived path-unit REQ files for that Issue (REQs whose `**Layer:**` is `none`), read from `{project}/.do-work/archive/`. The closure agent reads each path-unit's `**Entry point:**` and `**Terminal state:**` header fields — these are the contract it validates.
3. The project root and its config (`security`, `test.suite_command`, runtime hints), loaded via [config.md](../../agents/config.md).

The closure agent is **denied** all pipeline context: no worker return reports, no verify/audit/review output, no run ledger, no orchestrator conversation. It must not read `**Closure proof:**` values — per-REQ proof is exactly the optimism it exists to re-check independently.

**Rationale.** The run's own context wants the run to be finished. Self-grading bias (Gap C, the same defect R2 fixes for review) is structural: a grader sharing the run's context inherits its optimism. A cold subagent that knows only "here is what the user asked for" and "here is the claimed entry point" cannot inherit a verdict it never saw. This is the same independence discipline R2 applies to review/verify, applied to delivery validation. It also keeps the closure verdict honest when included in archives: closure proof is observation, not assertion.

---

## Decision 2 — Walk mechanics per entry-point type

**Decision.** The closure agent classifies each path-unit's `**Entry point:**` into a **walk kind** and executes the matching probe in the merged app (base branch, post-integration — never inside a worktree). Each probe produces an *observed state* compared against the path-unit's `**Terminal state:**`.

| Entry-point kind | Detection signal in `**Entry point:**` | Walk action | Observed-state source |
|---|---|---|---|
| Web route / page | path like `/route`, "page", "screen", "UI", "renders" | Navigate with Playwright (`browser_navigate`), snapshot DOM, assert terminal-state markers present | rendered DOM + console errors |
| API endpoint | "endpoint", `GET/POST/PUT/DELETE`, "API", a URL with a verb | `curl` the endpoint (method + representative payload), capture status + body | HTTP status + JSON/body shape |
| CLI command | "run `cmd`", "command", "invokes", a shell invocation | Invoke the command via `Bash` with representative args, capture exit code + stdout/stderr | exit code + output |
| Library export | "export", "function", "module", "import", "calls `fn()`" | Call the export through the project's test harness (`test.suite_command` scoped to a targeted call, or an inline harness snippet) | return value / assertion result |

**Rationale.** A path-unit's terminal state is only meaningfully observed through the surface the user actually touches. Tests assert internal contracts; a walk exercises the real entry point. Detection is keyword-driven off the already-structured `**Entry point:**` field (defined in SKILL.md's REQ Header Schema) so the agent does not invent surfaces — it routes the surface capture already recorded. The merged-app constraint is load-bearing: walking a worktree would re-prove isolation, not integration.

---

## Decision 3 — Degraded mode (the ideate requirement)

**Decision.** When an entry point is **not automatable** — a human workflow step, or a slash command / skill that runs in a *different harness* than the one executing the closure agent (do-work closing itself is the canonical case) — the agent does not silently skip and does not auto-fail. It records a degraded verdict of one of two kinds:

- **`degraded:evidence-by-test`** — the integrated test suite covers this path-unit's behaviour. The agent runs `test.suite_command` and cites the specific passing test(s) as the closure evidence. Used when a real automated proof exists, just not at the live entry-point surface.
- **`degraded:human-confirmed`** — no automatable surface and no covering test. The agent emits one explicit `AskUserQuestion` prompt describing the path-unit, the entry point, and what "reached terminal state" would look like, and records the human's confirm/deny as evidence. Never assumed; always an explicit prompt.

A degraded verdict is a **first-class outcome**, not a failure. It is surfaced in the report and in coverage (Decision 5/Decision on rollup), so the user sees exactly which path-units were proven live vs. by-test vs. by-human.

**Degraded-mode routing table** (the minimum coverage the children must implement):

| Entry-point kind | Automatable in closure harness? | Verdict path |
|---|---|---|
| Web route / page | Yes (Playwright) | live walk → `closed` / `not-reached` / `terminal-mismatch` |
| API endpoint | Yes (curl) | live walk → `closed` / `not-reached` / `terminal-mismatch` |
| CLI command | Yes (Bash) | live walk → `closed` / `not-reached` / `terminal-mismatch` |
| Library export | Yes (test harness) | live walk → `closed` / `not-reached` / `terminal-mismatch` |
| Slash command / skill (different harness) | No | `degraded:evidence-by-test` if a covering suite test exists, else `degraded:human-confirmed` |
| Human workflow step | No | `degraded:human-confirmed` (explicit prompt) |

**Rationale.** ideate flagged that do-work itself — and any CLI tool or skill — has no automatable live surface from inside the closure run. A naive design either skips these (silently lowering the bar) or fails them (penalising correct work). Degraded mode names the gap explicitly and demands the strongest *available* evidence: a real test run, or an explicit human attestation. This preserves the evidence-not-assertion invariant for the un-walkable case while keeping the verdict auditable.

---

## Decision 4 — Report format (`closure.md` schema)

**Decision.** The closure agent writes `{project}/.do-work/user-requests/UR-NNN/closure.md`. It is a YAML front-matter summary plus one markdown verdict row per path-unit REQ.

**Front matter (required fields):**

| Field | Type | Meaning |
|---|---|---|
| `ur` | `UR-NNN` | the Issue being closed |
| `closed_at` | ISO-8601 timestamp | when the walk completed |
| `branch` | string | the merged branch walked (e.g. `main`) |
| `path_units` | int | count of path-unit REQs found |
| `verdict_summary` | map | counts keyed by verdict (`closed`, `not-reached`, `terminal-mismatch`, `degraded:evidence-by-test`, `degraded:human-confirmed`) |
| `overall` | enum | `closed` (all path-units closed or degraded-with-evidence) / `gaps` (≥1 not-reached or terminal-mismatch) / `no-path-units` |

**Per-path-unit verdict row (required fields, one per path-unit REQ):**

| Field | Type | Meaning |
|---|---|---|
| `req` | `REQ-NNN` | the path-unit REQ id |
| `entry_point` | string | verbatim copy of the REQ's `**Entry point:**` |
| `terminal_state` | string | verbatim copy of the REQ's `**Terminal state:**` |
| `walk_kind` | enum | `web` / `api` / `cli` / `library` / `slash-command` / `human` (Decision 2/3) |
| `action_taken` | string | the exact probe run (e.g. the curl line, the navigate target, the test name) |
| `observed_state` | string | what the probe actually observed |
| `verdict` | enum | `closed` / `not-reached` / `terminal-mismatch` / `degraded:evidence-by-test` / `degraded:human-confirmed` |
| `evidence_ref` | string | pointer to the proof: command output snippet, screenshot path, test name + suite result, or the human-confirm prompt id |

**Verdict semantics:**

- `closed` — entry point reached, observed state matches terminal state.
- `not-reached` — entry point could not be exercised at all (route 404s, command not found, import fails).
- `terminal-mismatch` — entry point reached but observed state ≠ declared terminal state (the integration drift case this whole feature exists to catch).
- `degraded:*` — per Decision 3.

**Empty case.** A UR with zero path-unit REQs writes a valid `closure.md` with `path_units: 0`, `overall: no-path-units`, and a one-line body explaining that this Issue declared no reachable paths to close (REQ-209 AC3). It does not error.

### Worked example (`closure.md`)

```markdown
---
ur: UR-042
closed_at: 2026-06-12T14:20:05Z
branch: main
path_units: 2
verdict_summary:
  closed: 1
  terminal-mismatch: 1
overall: gaps
---

# Closure report — UR-042

## REQ-051 — closed
- req: REQ-051
- entry_point: "GET /api/invoices/:id returns the invoice as JSON"
- terminal_state: "200 with {id, total, status:'paid'} for a paid invoice"
- walk_kind: api
- action_taken: "curl -s -o - -w '%{http_code}' http://localhost:8000/api/invoices/9"
- observed_state: "200; body {id:9,total:120.00,status:'paid'}"
- verdict: closed
- evidence_ref: "curl-output:closure-evidence/req-051.txt"

## REQ-052 — terminal-mismatch
- req: REQ-052
- entry_point: "User visits /invoices and sees the paid badge on row 9"
- terminal_state: "Row 9 shows a green 'Paid' badge"
- walk_kind: web
- action_taken: "browser_navigate http://localhost:8000/invoices; snapshot row[data-id=9]"
- observed_state: "Row 9 renders but badge is absent (status cell empty)"
- verdict: terminal-mismatch
- evidence_ref: "screenshot:closure-evidence/req-052.png"
```

**Validation of the example against the schema (field-by-field):** both rows carry every required per-path-unit field (`req`, `entry_point`, `terminal_state`, `walk_kind`, `action_taken`, `observed_state`, `verdict`, `evidence_ref`); the front matter carries every required field; `verdict_summary` counts (1 closed, 1 terminal-mismatch) match the two rows; `overall: gaps` is correct because one row is `terminal-mismatch`. The example demonstrates the headline value: REQ-052 passed per-REQ proof in isolation but the integrated UI does not show the badge — exactly the drift no existing gate catches.

**Rationale.** The schema separates *what was claimed* (`entry_point`, `terminal_state`, copied verbatim from the REQ) from *what was observed* (`action_taken`, `observed_state`, `verdict`, `evidence_ref`). That separation is what makes the report adversarial rather than a restatement of the run's optimism. Every verdict carries a concrete `evidence_ref` so closure is auditable, matching the evidence-not-assertion invariant.

---

## Decision 5 — Wiring (invocation + failure behaviour)

**Decision.**

- **Standalone:** `/do-work close UR-NNN` routes through a new SKILL.md subcommand section (REQ-212), mirroring the `status` block: detect `{project}`, resolve `UR-NNN`, confirm `{project}/.do-work/user-requests/UR-NNN/input.md` exists (else report and stop), read `agents/close.md` in full, follow it exactly. The closure agent itself is `agents/close.md` (REQ-211).
- **Offered by go after a clean run:** go's post-run flow (`agents/go.md` Step 4 archive area / Step 6 report) gains a closure offer. After run drains without a stopper, go reports completion and — when closure is applicable (the Issue has ≥1 path-unit REQ now archived) — offers to run `close` for that Issue. The offer is **workflow-relevant, not cosmetic**: per R9, it must not be gated behind `next_steps.enabled`; it is gated only on delegate-vs-standalone (go is top-level, so it presents the offer). If the user declines, go reports the Issue as run-complete-but-not-closed.
- **Failure behaviour:** closure gaps (`not-reached`, `terminal-mismatch`) are **surfaced, not auto-fixed**. The closure agent never edits source, never re-runs the loop, never reopens REQs. A `gaps` overall verdict prints the failing rows and recommends the user capture follow-up work (e.g. intake a new brief or re-open via a new REQ). This matches the system's non-delegable-gate discipline: closure observes and reports; remediation is an explicit, user-initiated act.

**Rationale.** Two entry points cover both the autonomous path (go offers it as the natural last step of delivery) and the deliberate path (a user closing an older UR by hand). Gating the go offer on `next_steps.enabled` would hide the system's most important delivery signal behind a default-off cosmetic flag — exactly the Gap G mistake R9 corrects. Auto-fixing on gaps would re-introduce the self-correcting optimism this agent exists to break; surfacing keeps the human in the loop for integration failures, which are precisely the failures most likely to need judgment.

---

## Decision 6 — How closure relates to `**Closure proof:**` and coverage

**Decision.** Closure operates **above** the existing per-REQ proof tier; it does not write or alter `**Closure proof:**`.

- `**Closure proof:**` stays exactly as today: written by run.md Step 4 from the worker's `closure_proof` YAML value (a checkpoint-log + commit reference), and read by `lib/derive-status.sh` to derive per-REQ `proven`/`unproven`. The closure agent does not touch it.
- The Issue-level closure verdict lives only in `UR-NNN/closure.md`. Per-path-unit `evidence_ref` values in that file are the closure analogue of `**Closure proof:**` — they reference observed end-to-end evidence (command output, screenshot, test name, human-confirm id) rather than a per-REQ checkpoint log.
- **Coverage distinction (REQ-213):** `lib/coverage-rollup.sh` gains an end-to-end tier. Today it prints `intended=N proven=N unproven=N` per Issue by aggregating `derive-status.sh`. REQ-213 extends it: when `UR-NNN/closure.md` exists, the rollup reads `overall` and the `verdict_summary` and appends a closure column, e.g. `closed=1 gaps=1` or `closure=none` when no `closure.md` exists yet. This lets `status` (which already prints the rollup under its `Coverage` heading) distinguish "proven per-REQ" from "proven end-to-end" without changing the existing per-REQ math — the new field is additive, preserving the existing line format and the lib's test contract (`lib/tests/coverage-rollup.test.sh`).

**Rationale.** Two proof tiers answer two different questions: `**Closure proof:**` answers "was this REQ correctly built and committed?"; closure answers "does the merged whole do what the user asked?". Keeping them separate preserves the meaning of every existing field and the determinism of the lib scripts, while making the end-to-end signal visible in the one place users already look (`status` Coverage). Folding closure into `**Closure proof:**` would conflate per-REQ correctness with integration reachability and silently change what `proven` means across the whole system.

---

## Implementation children — files each will touch

| Child REQ | Layer | Files | Scope |
|---|---|---|---|
| REQ-211 | agents | `agents/close.md` (new) | The closure agent: cold dispatch (Decision 1), walk mechanics + degraded routing (Decisions 2–3), writes `closure.md` per the schema (Decision 4), surfaces gaps without fixing (Decision 5). Loads config via config.md. |
| REQ-212 | commands | `SKILL.md` | New `### close [UR-NNN]` subcommand section mirroring the `status` block; add `close` to the Quick Reference. Wire the go offer note if it lives in SKILL.md routing; the go-side change itself is `agents/go.md`. |
| REQ-213 | agents | `lib/coverage-rollup.sh` (+ `lib/tests/coverage-rollup.test.sh`) | Add the additive end-to-end closure column read from `UR-NNN/closure.md`; extend the test to cover the `closure=none` / `closed=N gaps=N` / `no-path-units` cases. |

**go wiring note for REQ-211/212:** the post-run closure offer (Decision 5) is an edit to `agents/go.md` Step 4/6 area. Whichever child owns the go edit must keep it ungated by `next_steps.enabled` (R9) and gated only on go being top-level (it always is).

**Out of scope for these children:** any change to `lib/derive-status.sh`, `agents/run.md` Step 4, or the `**Closure proof:**` field — Decision 6 explicitly keeps the per-REQ tier untouched.
