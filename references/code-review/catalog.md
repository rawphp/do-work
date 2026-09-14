# Code-review persona catalog

Spawn gates for `/do-work code-review`. Nine personas only. Selection is agent judgment against the resolved diff, not keyword matching. Absence of a surface means skip, not "run just in case."

Persona prompt assets live in `references/code-review/personas/`.

## Always

| Persona | Prompt asset | Select when |
|---------|--------------|-------------|
| `correctness` | `correctness-reviewer.md` | Every review. Logic errors, edge cases, state bugs, error propagation, intent compliance. |

## Standards (Stage 3b)

| Persona | Prompt asset | Select when |
|---------|--------------|-------------|
| `project-standards` | `project-standards-reviewer.md` | At least one applicable `CODING_STANDARDS.md` / `CLAUDE.md` / `AGENTS.md` governs a changed file, **or** standards discovery failed (fail closed). Skip on a successful empty search. |

Discover candidates on **the tree under review** (workspace for a local branch; the PR/branch head ref when reviewing a remote). Keep files whose directory is an ancestor of a changed file. A root-level file governs the whole checkout. `CODING_STANDARDS.md` is the designated criteria source: an instruction file (`CLAUDE.md` / `AGENTS.md`) supplies criteria only for changed files that no `CODING_STANDARDS.md` governs. Pass the mapping in a `<standards-paths>` block. Search error or uncertain scope → spawn `project-standards` and state the uncertainty in Coverage.

## Generic conditional

| Persona | Prompt asset | Select when the diff touches... |
|---------|--------------|--------------------------------|
| `testing` | `testing-reviewer.md` | Test files, test infrastructure, fixtures, mocks, or harness behavior; **or** meaningful runtime behavior changed without corresponding test work. Behavioral triggers: new or changed branches, state mutation, API/control-flow behavior, error handling. Production-file presence alone and non-behavioral edits do **not** select it. |
| `maintainability` | `maintainability-reviewer.md` | Large or structural work: substantial refactors, new abstractions, file moves, coupling/type-boundary changes, or at least **200 executable changed lines**. |

## Cross-cutting conditional

| Persona | Prompt asset | Select when the diff touches... |
|---------|--------------|--------------------------------|
| `security` | `security-reviewer.md` | Auth middleware, public endpoints, user input handling, permission checks, secrets management. |
| `performance` | `performance-reviewer.md` | Concrete performance-sensitive behavior: database/ORM query shape, algorithmic complexity, large loop-heavy transforms, batching/fan-out, or cache policy with material resource impact. Async/concurrent code or a cache data structure alone does **not** select it when correctness/reliability already own the changed semantics. |
| `api-contract` | `api-contract-reviewer.md` | An externally consumed boundary changes: route/request/response definitions, serializers, published event schemas, API versioning, or a public package signature with evidenced downstream callers. A new or changed exported symbol inside one module is insufficient by itself. |
| `reliability` | `reliability-reviewer.md` | Error handling, retry logic, circuit breakers, timeouts, background jobs, async handlers, health checks. |
| `adversarial` | `adversarial-reviewer.md` | ≥50 changed **code** lines; auth/payments; persistence writes or event publication; retry/partial-failure or concurrency/ordering semantics; external APIs; **or** a silent-pass verification mechanism (CI/CD gating, merge-blocking checks, build/deploy steps, coverage/lint gates, or test infrastructure/mocks that could mask production), regardless of size. Instruction-prose-only diffs skip adversarial unless the prose describes auth, payment, or data-mutation behavior, or the change itself *is* a silent-pass guard. There is no cross-model peer: spawn this in-process persona when selected. |

## Lite roster (fail closed)

Collapse to lite only when **all** of these hold:

1. Executable changed lines are **1–39** (see counting below), **zero** uncounted files, **no** path signals (`migrations`, `frontend`, `api`, `swift-ios` from the changed paths).
2. No content-based risk in the diff (auth, payments, data mutation, external API, secrets/permissions, deserialization, crypto, concurrency/background jobs, filesystem/process execution).
3. Standards discovery completed successfully (applicable paths **or** a confirmed empty result).
4. No conditional persona other than `project-standards` was selected.

**Lite roster:** `correctness`, plus `project-standards` when Stage 3b found applicable paths.

Any uncertainty (`exec_lines` unknown, uncounted files, path signals, search failure, or a selected conditional) → full selected roster. A 12-line auth change is not lite. A code diff that also touches one `.md` is not lite (uncounted file).

### Executable-line count (no Python)

Count from `git diff --numstat <base> <head>` (the same endpoints as the three-dot review diff). Sum added+deleted for files whose suffix is one of:

`.rb .py .js .jsx .ts .tsx .go .rs .java .swift .kt .c .cc .cpp .cs .php .ex .exs .scala`

Every other changed path is an **uncounted file**. Binary/`-` numstat rows are uncounted. If `git diff` fails, treat `exec_lines` as unknown and skip lite.

Path signals (any match disqualifies lite; they are **not** automatic persona selection):

- `migrations` — `db/migrate/`, `schema.rb`, `schema.sql`, `/migrations?/`, alembic, flyway, liquibase
- `frontend` — `.tsx .jsx .vue .svelte .css .scss .html .erb .haml`, `/components?/`, stimulus, turbo
- `api` — `/(routes?|controllers?|api|serializers?|graphql)/`, `.proto`, openapi, swagger
- `swift-ios` — `.swift .kt .pbxproj .xcconfig .entitlements`

## Announce

Before dispatch, name the always-on reviewers and give a one-line reason per **conditional** (the real concern, not the keyword). Do not print model-tier labels or scope-mode codenames.