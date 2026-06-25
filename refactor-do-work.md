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
- [ ] **S3 — Reconcile duplicates.** Merge any unique top-level cases into the `lib/tests/`
      versions of `check-deps`/`pick-req`, then delete the stale top-level copies.
- [ ] **S4 — Converge to plain-bash.** Drop redundant `cycle-check.bats`; port
      `deadlock-check.bats` → `deadlock-check.test.sh`. Suite runs with no external dep.
- [ ] **S5 — Shared harness (optional).** Extract `_harness.sh`; source from each test.
      Only if it's a clear win without losing single-file runnability.
- [ ] **S6 — CI.** `.github/workflows/test.yml` runs the runner on push/PR.
- [ ] **S7 — Docs sync.** CONTRIBUTING/README test layout; doc-lint clean.
- [ ] **S8 — Final.** Full suite green, `/code-review` whole diff, open PR.

Each step: live-test → `/code-review` → commit.
