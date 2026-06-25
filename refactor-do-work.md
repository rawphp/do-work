# Refactor: do-work — test/tooling architecture

Branch: `fix/prod-data-quality-loop` → working further on it, PR into `main` when done.
Live-test harness: run every `lib/tests/*.test.sh` + `*.bats`; all must pass.
Autoreview: `/code-review` on each step's diff before commit.

## Baseline (2026-06-25)

- 22 plain-bash `*.test.sh` + 2 `*.bats` — **all green.**
- Captured before any change.

## Architectural assessment

The agent layer (`SKILL.md` router → `agents/*.md` → `lib/*.sh` primitives, file-based
state) is well-designed and well-documented. **Not touching it** — that's the system's
strength, it's prose-instruction for a model, and there's no test coverage to catch a
behavioral regression from splitting it. Same reasoning defers the 1329-line `run.md`.

The genuine, bounded structural debt is in the **test/tooling layer**:

1. **Two test homes.** Most tests live in `lib/tests/`, but `coverage-rollup.test.sh`
   and `derive-status.test.sh` live only at `lib/` top-level. No single home.
2. **Drifted duplicates.** `lib/check-deps.test.sh` (11 cases) and `lib/pick-req.test.sh`
   (9 cases) duplicate richer `lib/tests/` versions (16 / 23 cases) — drifted, unclear
   which is canonical, double-run.
3. **Two frameworks.** `cycle-check` + `deadlock-check` use `.bats` (external `bats`
   binary); the other 22 tests are plain-bash. Plan docs say plain-bash under `lib/tests`
   is the intended style and bats is "if available" — bats is the outlier.
4. **No aggregate runner.** No single command runs the suite; the zero-tolerance test
   policy has nothing to invoke. "Live-test the system" had no entrypoint.
5. **Per-file harness duplication.** Each `*.test.sh` reimplements `fail`/`assert_eq`/
   counters/summary (~15 lines × ~18 files).
6. **No CI.** Nothing enforces the suite on push/PR.

Canonical direction (doc-confirmed): all tests in `lib/tests/`, plain-bash `.test.sh`,
single runner, bats removed, CI runs the runner.

## Plan & progress

- [x] **S1 — Aggregate runner.** `lib/tests/run-all.sh`: run all `*.test.sh` (+ `*.bats`
      if present), summary, non-zero on any fail. The new live-test command.
      Verified: exit 0 green / exit 1 on fail (names suite) / bats-skip graceful.
- [x] **S2 — Single home.** Moved `coverage-rollup.test.sh` + `derive-status.test.sh`
      into `lib/tests/` (LIB_DIR convention); updated `ur-closure.md` path refs.
      Runner now at 22 green. doc-lint clean.
- [x] **S3 — Reconcile duplicates.** Investigation overturned the "stale duplicate"
      premise: the top-level `check-deps`/`pick-req` files are **pending-validation**
      suites the `lib/tests/` versions don't cover at all, and run-all.sh wasn't running
      them. Relocated as `check-deps-pending.test.sh` / `pick-req-pending.test.sh`
      (distinct names avoid the basename collision). No coverage lost; runner 22→24.
- [x] **S4 — Converge to plain-bash.** `cycle-check.test.sh` was already a strict
      superset of `cycle-check.bats` (8 bats cases + 4 more) → dropped the bats.
      Ported `deadlock-check.bats` → plain-bash `deadlock-check.test.sh` (all 7 cases,
      reviewer-confirmed faithful). Both `.bats` removed. Suite (23) now green with
      **bats absent** — external dependency eliminated.
- [~] **S5 — Shared harness — DEFERRED (deliberate).** Extracting `fail`/`assert_*`
      would touch ~23 files for a benign 15-line duplication, and the assert sets differ
      per file (`assert_age_ge`, `assert_not_contains`, …) so a single harness needs a
      superset + per-file exceptions. Cosmetic DRY, not structural debt; conflicts with
      the minimal-changes rule. Not worth the churn/risk. Left as-is.
- [x] **S6 — CI.** `.github/workflows/test.yml` runs `run-all.sh` + `doc-lint.sh` on
      push to main and every PR. No bats install needed (dependency removed in S4).
      YAML validated; both steps simulated green locally.
- [x] **S7 — Docs sync.** Added a "Running the tests" section to CONTRIBUTING
      (runner command, single-home rule, plain-bash/no-bats, CI parity). No doc-lint
      guard added: there was no doc *conflict* (normative docs were already bats-free),
      and a `lib/*.test.sh` location guard would false-positive on legit retro examples
      — adding a speculative pattern violates the project's UR-029 over-broad caution.
- [ ] **S8 — Final.** Full suite green, `/code-review` whole diff, open PR.

Each step: live-test → `/code-review` → commit.
