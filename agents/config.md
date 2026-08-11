# Config Loader

This is a reusable instruction block. Other agents reference this file to load config at startup.

---

## Load Config

At the start of execution, after detecting the project root:

1. Check if `{project}/.do-work/config.yml` exists
2. If it exists, read the file and keep its values in context for subsequent steps
3. If it does not exist, create it with the default template below, then keep those values in context:

```yaml
# do-work configuration
# Edit this file to customize agent behavior.

project:
  name: ""

# Declare your project's layers, e.g. [frontend, backend] for a web app,
# [commands, core, output] for a CLI, [agents, commands, templates] for do-work.
# Capture and verify use this list to gap-check briefs. Leave empty to
# opt out of layer-coverage checks (capture will halt feature briefs
# until either a layer list is declared or --no-layers is passed).
layers: []

log:
  enabled: true
  platforms: []          # e.g. [x, linkedin]
  drafts_per_platform: 2
  batch_size: 2            # drafts per batch (2 drafts + More + Skip = 4 options in AskUserQuestion)
  audience: ""           # e.g. "indie hackers", "enterprise devs", "startup founders"
  voice: ""              # e.g. "casual and direct", "thoughtful and technical"
  max_chars:             # per-platform character ceiling the log agent must keep each draft under
    x: 280
    blog: 500
    linkedin: 1300

test:
  suite_command: ""      # e.g. "./vendor/bin/pest", "npx vitest run", "npm test"

next_steps:
  enabled: false         # when true, agents present next-step options via AskUserQuestion after each phase

feedback:
  enabled: false         # when true, agents file GitHub issues on notable events
  repo: tomkaczocha/do-work  # GitHub repo (owner/name) for system-class feedback issues
  label: auto:do-work-feedback  # label applied to every filed issue; must exist in the target repo
  project_repo: ""       # GitHub repo for project-class events; falls back to feedback.repo when empty

parallel:
  stale_threshold_seconds: 900  # seconds of heartbeat silence before a working/ slot is considered stale; workers stamp at checkpoints (per TDD cycle / verification step), so 900s (15 min) comfortably spans the gap between stamps

review:
  required: true          # post-build review gate must pass before archive
  adversarial: false      # when true AND check-policy.sh exits 2 (risk.require_review), dispatch 3 lens-scoped reviewers (correctness/security/regression) with a 2-of-3 majority gate; default false until run-level budget enforcement (REQ-226) caps multi-reviewer token cost

acceptance:
  evidence_required: true # each acceptance criterion needs passing evidence

risk:
  require_review:
    - migrations
    - auth
    - billing
    - payments
    - files_changed_over: 8
    - acceptance_criteria_over: 6

security:
  blocked_paths:
    - .env
    - .env.*
  blocked_commands:
    - rm -rf
    - git push --force
    - git push -f
    - git reset --hard
    - git checkout --

model:
  default: sonnet
  escalation: opus

cost:
  budget: ""             # optional user-defined budget/limit; empty means unset

ledger:
  enabled: true          # write .do-work/runs/RUN-NNN.yml records

delivery:
  mode: merge            # how run.md Step 4 delivers a passing REQ: "merge" (default — merge req/REQ-NNN into the integration base from lib/ensure-integration-base.sh, never main/master/remote HEAD) or "pr" (push the branch and open a GitHub PR instead of merging). pr mode requires a configured git remote and the `gh` CLI; missing either stops with a missing-creds stopper — it NEVER silently falls back to merge.
  pr:
    granularity: req     # only consulted when mode: pr. "req" (default) opens one PR per REQ off req/REQ-NNN; "ur" accumulates each REQ branch onto the shared new-work branch and opens a single PR when that UR's backlog drains. ensure-integration-base leave-default always uses new-work (scoped and unscoped); granularity: ur only controls PR open/accumulate behaviour when mode is pr.

worktree:
  link_paths: []         # extra dependency dirs to symlink from the main checkout into each
                         # worker worktree (e.g. [server/vendor, web/node_modules]). Additive
                         # to auto-detected dirs (composer.json -> vendor, package.json ->
                         # node_modules, pyproject.toml/requirements.txt -> .venv).
  setup_command: ""      # optional fallback run inside the worktree when a dependency dir is
                         # absent from the main checkout and cannot be symlinked
                         # (e.g. "composer install --no-interaction"). Empty = no fallback.

# Work-item tracker backend. Default markdown = today's .do-work/ + lib/*.sh loop.
# When backend is missing, empty, or "markdown", resolve to markdown (no Linear/sqlite tools).
# linear and sqlite are full alternate backends (no dual-write); see
# agents/tracker/{port,markdown,linear,sqlite}.md.
tracker:
  backend: markdown          # markdown | linear | sqlite — unset/empty/missing key also means markdown
  sqlite:
    path: ""                 # default .do-work/work.db (relative to project root)
    board_path: ""           # default .do-work/board/index.html
    busy_timeout_ms: 5000
  linear:
    team_id: ""              # required when backend=linear (or resolve via team_key)
    team_key: ""             # optional alternate resolve (e.g. team key string)
    default_assignee_id: ""  # human operator; set on issue create when configured
    # Shared Linear Project that holds all UR milestones + Issues (not one Project per UR).
    # Empty default — NOT the skill name. Resolve when backend=linear (Load Config step 9):
    #   explicit product_project (name|UUID) wins; if empty → project.name; if that empty →
    #   git-root directory basename; ensure_product_container create-if-missing; persist UUID.
    product_project: ""
    # Human-facing Project Milestone name for each UR.
    ur_milestone_name_pattern: "{ur_id}: {title}"
    # Deprecated aliases (still accepted if new keys missing):
    # project_name_pattern: "do-work/{ur_id}"      # ignored for UR home
    # initiative_title_pattern: "{ur_id}: {title}" # alias of ur_milestone_name_pattern
    status_map:
      backlog: "Todo"
      in_progress: "In Progress"
      stopped: "Canceled"    # override if team has a dedicated Stopped state
      done: "Done"
    labels:
      layer_prefix: "Layer/"
      path_unit: "path-unit"
      size_prefix: "Size/"
    agent_claim_marker: "<!-- do-work-claim -->"
    heartbeat_max_age_seconds: null  # null → use parallel.stale_threshold_seconds
    decisions_doc_title: "do-work/decisions"
    calibration_doc_title: "do-work/calibration"

verify:
  threshold: 90          # minimum confidence score (0-100) for go to auto-run without --force

# Subagent routing for the run orchestrator. Ordered list of {match, agent}
# rules: the classifier scans each REQ top-to-bottom and dispatches the first
# rule whose `match` fits; if none match it falls back to `general-purpose`
# silently. Ships EMPTY so the stock skill routes every REQ to the universally
# available `general-purpose` agent — portable on any machine. Add rules to
# route specialist work to your own subagents. `match` is a natural-language
# signal description or keyword list the classifier interprets against the REQ's
# Task / Context / Acceptance Criteria / Verification Steps.
routing: []

# Example routing block (commented). This reproduces do-work's original
# hard-coded classification table. Uncomment and adapt to restore specialist
# dispatch — every `agent` below must exist as a subagent_type on your machine,
# or that rule's REQs will fail to dispatch. Rules are first-match-wins, so the
# order here matters; `general-purpose` is the implicit fallback and never needs
# a rule.
#
# routing:
#   - match: "Verification Steps reference pest/phpunit/vitest/playwright/npx test AND the task is write-tests / improve-coverage / test-X"
#     agent: laravel-test-expert
#   - match: "file paths under app/ resources/ routes/, or task mentions Laravel/Eloquent/Vue/Inertia/Pinia"
#     agent: laravel-vue-architect
#   - match: "acceptance criteria mention user-sees / page-renders / form-displays / responsive / mobile / layout / CSS / Tailwind / UX / accessibility"
#     agent: saas-ux-designer
#   - match: "new feature spanning multiple layers (controller + view + model) with no specialist above matching"
#     agent: feature-dev:code-architect
#   - match: "task is find-code / search-for-X / where-is-Y-defined / pure exploration"
#     agent: Explore
#   - match: "task is a code review or 'review the implementation against the plan'"
#     agent: feature-dev:code-reviewer
#   - match: "file paths under ~/.claude/skills/ ~/.claude/agents/ .do-work/agents/, or task mentions skill / agent file / SKILL.md / slash command / trigger description"
#     agent: skill-author
#   - match: "file imports anthropic / @anthropic-ai/sdk / openai / a vector DB client (pinecone/qdrant/weaviate/chroma/pgvector), or task mentions prompt / eval / RAG / embeddings / tool use / function calling / LLM / agent loop"
#     agent: llm-app-engineer
```

4. **Migrate missing keys to disk.** Compare the existing config.yml against the default template above. For each top-level section (`project`, `log`, `next_steps`, `feedback`, `parallel`, `review`, `acceptance`, `risk`, `security`, `model`, `cost`, `ledger`, `delivery`, `worktree`, `tracker`, `verify`, `routing`) and each key within those sections:

   - If a **top-level section is entirely missing** from the file (e.g. `next_steps:` does not appear), append the full section block — including all keys, default values, and inline comments — to the end of the file.
   - If a **top-level section exists but is missing individual keys** (e.g. `log:` exists but `batch_size` is absent), append the missing keys with their default values to that section. This applies to nested-map keys too — e.g. if `log:` exists but `log.max_chars` is absent, append it with its default map (`{x: 280, linkedin: 1300}`) and inline comment.
   - **Never overwrite existing values.** If a key exists in the file, keep the user's value regardless of what the default says. For nested maps, treat presence of the parent key as "existing" — if `log.max_chars:` is present, do not overwrite any of its entries or add missing platform entries, even if the default template has more. In particular, never replace a non-empty `tracker.linear.product_project` (name or UUID) with the template empty default or with the skill name `do-work`.
   - If **no keys are missing**, do not write to the file. Skip this step silently.
   - If keys were added, report: `Config updated: added [list of added keys/sections]`

4b. **Seed `project.name` from directory basename when empty (install / first load).** After create (step 3) or migrate (step 4):

   - Let `name` = current `project.name` (treat missing, null, empty, or whitespace-only as empty).
   - If `name` is **non-empty** → leave it alone; do **not** overwrite.
   - If `name` is **empty** → set `project.name` to the **git-root directory basename** (the basename of the detected project root from startup) and **write** that value to `{project}/.do-work/config.yml`.
   - This runs on create and on every load where `project.name` is still blank (e.g. operator cleared it, or an older template left it empty). It never replaces a deliberate non-empty name.

5. Keep the final merged values (file values + defaults for anything still missing, plus any seed from step 4b) in context for subsequent steps.

6. **Resolve tracker backend (markdown-default).** After the merged config is in context, set the effective work-item backend:

   - If `tracker.backend` is **missing**, **null**, **empty**, or **whitespace-only** → effective backend = **`markdown`**.
   - If `tracker.backend` is **`markdown`** (case-sensitive value as stored) → effective backend = **`markdown`**.
   - If `tracker.backend` is **`linear`** → effective backend = **`linear`**.
   - If `tracker.backend` is **`sqlite`** → effective backend = **`sqlite`**.
   - Otherwise → hard-stop with a config error naming the unknown backend; do not guess.

   When the effective backend is **`markdown`**: load `agents/tracker/port.md` then `agents/tracker/markdown.md` for work-item ops; **do not** require Linear MCP, `sqlite3`, credentials, or dual-write. Existing `lib/*.sh` + `.do-work/` behavior remains the implementation. `tracker.linear.*` and `tracker.sqlite.*` keys may still be migrated onto disk as defaults, but they are **inert** while backend resolves to markdown (no Linear or sqlite validation).

7. **Validate Linear config when effective backend is `linear`.** Run these checks **before** any work-item op. On failure, **hard-stop** — never silent-fallback to markdown or sqlite, never invent team ids or workflow states.

   | Check | Hard-fail when | Operator message must include |
   |-------|----------------|-------------------------------|
   | Team resolve | Neither `tracker.linear.team_id` nor `tracker.linear.team_key` resolves to a live team on Linear | How to set `team_id` / `team_key` in `.do-work/config.yml`; do not guess a team |
   | Linear MCP tools | Linear skill/MCP tools are missing, unauthenticated, or undiscoverable | How to connect Linear (Linear skill setup / MCP auth) — not fabricated data |
   | `status_map` states | Any mapped workflow state name is missing on the resolved team's workflow | List the missing do-work status → expected state name; instruct rename of the team state **or** override `tracker.linear.status_map.<key>` to an existing state name |

   **status_map defaults** (design §7): `backlog → "Todo"`, `in_progress → "In Progress"`, `stopped → "Canceled"`, `done → "Done"`. Override per-team when the team's workflow uses different labels; missing states are never invented.

   **Heartbeat age:** when `tracker.linear.heartbeat_max_age_seconds` is `null` or missing, use `parallel.stale_threshold_seconds` (default `900`).

   **Interaction with other keys:** `ledger`, `parallel`, `delivery`, `review`, `layers` remain valid under Linear. Authoritative run/cost notes are Linear Issue comments via port op `append_run_note`. If `ledger.enabled: true`, the orchestrator may **also** append local `.do-work/runs/RUN-NNN.yml` for offline retro tooling — local runs are telemetry only, not a second work-item store. Retro prefers Linear run notes when `backend: linear`, falling back to local runs if comments are unavailable.

   When the effective backend is **`linear`**: load `agents/tracker/port.md` then `agents/tracker/linear.md` for work-item ops after the validations above pass. If `agents/tracker/linear.md` is **missing or unreadable**, **hard-stop** with setup instructions (restore the backend doc from the skill install / Linear skill setup) — **never** fall through to `markdown.md` / `sqlite.md` or invent Linear tool sequences.

7b. **Validate SQLite config when effective backend is `sqlite`.** Run these checks **before** any work-item op. On failure, **hard-stop** — never silent-fallback to markdown or Linear, never invent a parallel REQ tree.

   | Check | Hard-fail when | Operator message must include |
   |-------|----------------|-------------------------------|
   | `sqlite3` on PATH | `sqlite3` CLI is missing or not executable | Install hint (`brew install sqlite` / distro package); do not fall back to markdown |
   | Backend doc | `agents/tracker/sqlite.md` is missing or unreadable | Restore the backend doc from the skill install; do not invent SQL sequences |
   | DB unusable (after first ensure/open) | Corrupt DB, unreadable file, or unsupported `PRAGMA user_version` | Current vs supported version; recreate-empty option; **never** markdown fallback |

   **Do not** run Linear validation or `product_project` bind when backend is `sqlite`.

   When the effective backend is **`sqlite`**: load `agents/tracker/port.md` then `agents/tracker/sqlite.md` for work-item ops after the `sqlite3` + backend-doc checks pass. Defer DB ensure/create to the first `ensure_product_container` / `lib/dw-db.sh ensure` call (empty greenfield DB on switch — no history migration). If `sqlite.md` is missing/unreadable → **hard-stop** — **never** fall through to `markdown.md` or `linear.md`.

   **Defaults:** empty `tracker.sqlite.path` → `{project}/.do-work/work.db`; empty `tracker.sqlite.board_path` → `{project}/.do-work/board/index.html`; empty/invalid `busy_timeout_ms` → `5000`.

8. **Resolve skill-root (`$SKILL_ROOT` / `{skill-root}`).** Once per agent turn, resolve the absolute path of the do-work skill install root — a directory that contains `lib/` **and** at least one skill marker (`SKILL.md` **or** `agents/`). **Token definition:** `{skill-root}` means this resolved absolute path for **all later steps in the same agent turn**. Keep `$SKILL_ROOT` in context; substitute it wherever docs or bash lines write `{skill-root}` (especially `{skill-root}/lib/...`).

   **Single home:** this step is the only place that defines the resolve recipe. `references/run-loop.md` §2a and the run-worker **Skill root** input are thin consumers — they must not invent a second folklore recipe.

   **Markers (valid skill install root):** a candidate directory is valid iff **both**:
   1. it contains a `lib/` directory, **and**
   2. it contains `SKILL.md` **or** an `agents/` directory (or both).

   Requiring a co-marker with `lib/` avoids monorepo false roots that happen to have a bare `lib/` higher in the tree.

   **Inherit rule:** If `$SKILL_ROOT` is already set in this agent turn's context (orchestrator-passed **Skill root**, or resolved earlier in the same turn) **and** that path is an absolute directory that satisfies the markers above, **keep it — do not re-resolve**. If missing, empty, non-absolute, or invalid (fails markers), clear it and run the walk-up recipe below. Nested agents inherit the entry-resolved root this way.

   **Recipe (walk-up from loaded instruction file — no env / hub / CWD fallback):**

   One-level `dirname/..` is **not** the algorithm — nested paths (e.g. `agents/tracker/linear.md`) and `SKILL.md` at the skill root need more than a single parent hop.

   ```bash
   # Start at the directory of the loaded instruction file; walk parents until
   # markers match (lib/ AND (SKILL.md OR agents/)). Hard-stop at filesystem
   # root if none found. No env/hub/CWD fallback.
   d="$(cd "$(dirname "<absolute path of the loaded agent or reference file>")" && pwd)"
   SKILL_ROOT=""
   while true; do
     if [ -d "$d/lib" ] && { [ -f "$d/SKILL.md" ] || [ -d "$d/agents" ]; }; then
       SKILL_ROOT="$d"
       break
     fi
     [ "$d" = "/" ] && break
     d="$(dirname "$d")"
   done
   # non-empty $SKILL_ROOT required — else hard-stop (see below)
   ```

   **Examples** (all resolve to the skill install root):

   | Loaded file | Walk starts at | Resolves to |
   |-------------|----------------|-------------|
   | `{skill}/agents/run.md` | `…/agents` | `{skill}` (parent has `lib/` + markers) |
   | `{skill}/agents/tracker/linear.md` | `…/agents/tracker` | `{skill}` (walk past `tracker` → `agents` → skill root; one-level `..` would wrongly stop at `agents/`) |
   | `{skill}/references/run-loop.md` | `…/references` | `{skill}` |
   | `{skill}/SKILL.md` | `{skill}` itself | `{skill}` (start directory already matches markers) |

   - Prefer the absolute path of the instruction file the agent is currently executing when walk-up is needed (e.g. `agents/run.md`, `agents/config.md`, `agents/run-worker.md`, `agents/tracker/linear.md`, a loaded `references/*.md`, or `SKILL.md`).
   - Use the walk-up result as `$SKILL_ROOT` only when it satisfies the markers.
   - When this project **is** the do-work skill itself, `$SKILL_ROOT` equals the project root and lib calls work directly. When the project is any other consumer repo, `$SKILL_ROOT` points at the skill clone where `lib/` actually lives — not at the consumer project root.
   - Orchestrators that dispatch workers pass the same absolute `$SKILL_ROOT` as the worker **Skill root** input and substitute it into pasted `run-worker.md` instructions (see `agents/run-worker.md` When Invoked #5 and `references/run-loop.md` Step 2 dispatch). Workers and nested agents **inherit** that value when it still satisfies markers.

   **Hard-stop when the path cannot be determined.** If any of the following is true, **stop immediately** with a clear operator message — do not guess:

   - Inherit failed (missing/invalid `$SKILL_ROOT`) **and** the harness did not provide an absolute path for the loaded instruction file
   - Walk-up from the loaded file reaches the filesystem root without finding a directory that satisfies the markers (`lib/` **and** (`SKILL.md` **or** `agents/`))
   - The path is empty or otherwise unknown after the recipe

   Operator message (example):

   `skill-root unknown: cannot resolve $SKILL_ROOT (walk-up from loaded file; no env/hub/CWD fallback). Provide an absolute path to the loaded instruction file under the skill install root, or a valid pre-resolved $SKILL_ROOT that contains lib/ and (SKILL.md or agents/).`

   **Do not** fall back to process CWD, hub paths (`~/.agents/skills/do-work`, `~/.claude/skills/do-work`), or invent a path from `DO_WORK_SKILL_ROOT` / other env vars when inherit markers fail. **Do** inherit a **valid** `$SKILL_ROOT` already set in this turn's context (see inherit rule above).

9. **Resolve and bind `tracker.linear.product_project` when effective backend is `linear`.** Run after step 7 validations pass and the Linear backend docs are loaded — **before** any work-item CRUD that needs the product Project. When effective backend is **`markdown`** or **`sqlite`**, skip this step entirely (`product_project` is inert).

   **Resolve order (name/lookup key only — does not rewrite an already-set value):**

   1. Let `pp` = current `tracker.linear.product_project` (missing, null, or whitespace-only → treat as empty).
   2. If `pp` is **non-empty** (name **or** UUID) → **lookup key = `pp`**. Explicit config wins. Do **not** replace it with `project.name`, the git-root basename, or the skill name `do-work`. Existing product UUIDs (and explicit names) are left untouched by this fallback chain.
   3. If `pp` is **empty** → lookup key = `project.name` when that is non-empty; else the **git-root directory basename** (same basename as step 4b). Never fall back to a hard-coded skill name.
   4. Call port op **`ensure_product_container`** with that lookup key: resolve the Linear Project by name or UUID; **create-if-missing** when the key is a name and no Project matches.
   5. On success, **always persist** the resolved Project **UUID** back to `tracker.linear.product_project` in `{project}/.do-work/config.yml` and in the in-memory config. If the file already stores that same UUID, skip the write (idempotent).
   6. On failure (unresolved after create attempt, MCP missing, permission error) → **hard-stop** with operator instructions; never invent a product Project and never silent-fallback to markdown.

   **Rewrite rules:** The empty → `project.name` → basename chain runs **only** when `product_project` is truly empty. It must never overwrite an explicit existing value. The only write after a non-empty start is ensure's **UUID bind** (e.g. name → UUID once resolved). After a true empty state, ensure binds and step 5 persists the UUID so subsequent loads take the explicit-UUID path.

**Phase-agent contract:** every phase agent that touches work items follows the **Tracker load path** (config → resolve `tracker.backend` → `port.md` → `agents/tracker/<backend>.md` → only named port ops). The shared load path is defined once here and in `agents/tracker/port.md`; each phase agent restates a short copy so a missing wire cannot cause split-brain storage. Every phase agent that invokes skill `lib/` scripts also depends on step 8 (`$SKILL_ROOT` / `{skill-root}`) from this same Load Config block.

**Never fail or stop because of a missing or incomplete config file** (steps 1–5, including 4b seed). If config creation or migration fails for any reason, proceed with in-memory defaults (including `tracker.backend: markdown`). **Exceptions (deliberate hard-stops, not config-file completeness problems):** step 6 unknown backend string; step 7 Linear validation (and missing `linear.md`) and step 9 product_project ensure/bind when the operator has opted into `backend: linear`; step **7b** sqlite unusable (`sqlite3` missing, missing `sqlite.md`, corrupt DB / bad `user_version` after ensure attempts) when the operator has opted into `backend: sqlite`; step 8 skill-root resolve when walk-up (or inherit) cannot determine an absolute skill install root.

---

## Config Schema Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` (seeded from git-root directory basename when empty on create/first load — Load Config step 4b; never overwrites a non-empty name) | Project display name. Also the preferred empty-`product_project` fallback when `backend: linear` (Load Config step 9). |
| `layers` | list of strings | `[]` | Project's declared layers for gap-aware capture. Capture and verify check that REQs cover each declared layer. Empty = opt out (feature briefs will halt until declared or `--no-layers` is passed). |
| `log.enabled` | boolean | `true` | Whether the log step runs after Go |
| `log.platforms` | list | `[]` | Platforms to generate draft posts for (e.g. `[x, linkedin]`) |
| `log.drafts_per_platform` | integer | `2` | Number of draft posts to generate per platform |
| `log.batch_size` | integer | `2` | Drafts to show per batch in the AskUserQuestion selection prompt. Default 2 because AskUserQuestion has a 4-option limit: `batch_size` drafts + "More approaches" + "Skip" must fit in 4 slots. Max 2 for non-final batches; final batch can show up to 3 (replacing "More" with a draft). |
| `log.audience` | string | `""` | Target audience for log posts (e.g. "indie hackers", "enterprise devs"). Shapes framing and references. |
| `log.voice` | string | `""` | Writing style for log posts (e.g. "casual and direct", "thoughtful and technical"). Shapes tone and word choice. |
| `log.max_chars` | map | `{x: 280, blog: 500, linkedin: 1300}` | Per-platform character ceiling the log agent must keep each draft under. Keys are platform slugs (`x`, `blog`, `linkedin`, etc.); values are integer char limits. Missing platforms fall back to the defaults shown here. |
| `test.suite_command` | string | `""` | Full test suite command to run at end of the do-work loop (e.g. `./vendor/bin/pest`, `npx vitest run`). If empty, the run agent attempts common defaults. |
| `next_steps.enabled` | boolean | `false` | When true, agents present next-step options via AskUserQuestion after each phase completes. When false or missing, agents report as they do today without prompting. |
| `feedback.enabled` | boolean | `false` | Master switch for GitHub issue feedback. When `false`, `lib/file-feedback.sh` exits silently without making any `gh` calls. **Self-targeting default:** if the running repo's `git config --get remote.origin.url` matches the do-work upstream pattern (a `github.com` URL ending in `/do-work` or `/do-work.git`), this key is treated as `true` even when the config.yml value is `false` or absent. Consumers: `lib/file-feedback.sh`. |
| `feedback.repo` | string | `"tomkaczocha/do-work"` | Target GitHub repo (`owner/name`) for **system-class** events: `deadlock`, `footprint-miss`, `concurrent-conflict`, `cap-cycle`, `stale-slot`. Must exist and have the label specified in `feedback.label`. Consumers: `lib/file-feedback.sh`. |
| `feedback.label` | string | `"auto:do-work-feedback"` | GitHub issue label applied to every issue filed by `lib/file-feedback.sh`. The label must exist in the target repo before the first event fires; the script will not create it automatically. Consumers: `lib/file-feedback.sh`. |
| `feedback.project_repo` | string | `""` | Target GitHub repo (`owner/name`) for **project-class** events: `ambiguous-criteria`, `verify-fail`. When non-empty, these events are filed here instead of `feedback.repo`. When empty, falls back to `feedback.repo`. Consumers: `lib/file-feedback.sh`. |
| `parallel.stale_threshold_seconds` | integer | `900` | Number of seconds of heartbeat silence after which a `working/REQ-*.md` slot is declared stale. Workers stamp the heartbeat at checkpoints (after each TDD cycle and verification step), not on a fixed timer, so the default is `900` s (15 min) to comfortably span the gap between stamps. Must be a positive integer; non-integer or absent values fall back to the default. Consumers: `lib/scan-stale.sh` (called by `agents/run.md` pre-flight and `lib/deadlock-check.sh`). |
| `review.required` | boolean | `true` | When true, post-build review must pass before a REQ archives. Consumers: `agents/run.md`, `agents/review.md`. |
| `review.adversarial` | boolean | `false` | When true **and** `lib/check-policy.sh` exits `2` (a `risk.require_review` signal), `agents/run.md` dispatches three lens-scoped reviewers (correctness, security, regression) instead of one and applies a 2-of-3 majority gate; any reviewer's blocker finding still fails the gate regardless of the majority. Defaults `false` to contain multi-reviewer token cost until run-level budget enforcement (REQ-226) lands — that REQ adds the cost ceiling that makes adversarial mode safe to enable by default. Consumers: `agents/run.md`. |
| `acceptance.evidence_required` | boolean | `true` | When true, every acceptance criterion needs passing evidence in the worker report before integration. Consumers: `lib/check-acceptance-evidence.sh`, `agents/run.md`. |
| `risk.require_review` | list | `[migrations, auth, billing, payments, files_changed_over: 8, acceptance_criteria_over: 6]` | Signals that force explicit review even if implementation checks pass. Consumers: `lib/check-policy.sh`, `agents/review.md`. |
| `security.blocked_paths` | list | `[.env, .env.*]` | Paths that must not be modified by workers. Consumers: `lib/check-policy.sh`. |
| `security.blocked_commands` | list | `[rm -rf, git push --force, git push -f, git reset --hard, git checkout --]` | Commands that must stop the run/review path when they appear in a worker's command evidence. **Matching semantics (REQ-205):** each entry is matched as an extended regex (ERE) anchored on **shell-token boundaries** — the entry must appear bounded by whitespace or line start/end, so `production` blocks the standalone token `production` but **not** the `production-notes` path fragment. Short-flag clusters are normalised for flag order: `rm -rf` also blocks `rm -fr` and `rm -r -f`. To match a raw literal substring instead (the pre-REQ-205 behaviour), prefix the entry with `substr:` — e.g. `substr:production` blocks any command merely containing that text, including `deploy-production.sh`; metacharacters after `substr:` are treated literally. **Migration note:** the default semantics changed from substring to token-anchored regex. Existing configs that relied on substring behaviour (e.g. a bare `production` entry matching `deploy-production.sh`) must adopt the `substr:` form, since the word `production` alone no longer blocks commands that merely contain it as a path fragment unless configured with `substr:`. Consumers: `lib/check-policy.sh`. |
| `model.default` | string | `sonnet` | Default worker model for ordinary REQs. Consumers: `agents/run.md`. |
| `model.escalation` | string | `opus` | Escalation model for high-risk or failed REQs. Consumers: `agents/run.md`. |
| `cost.budget` | string | `""` | Optional user-defined model/cost budget. Empty means no configured budget. Consumers: `agents/run.md`, `lib/run-ledger.sh`. |
| `ledger.enabled` | boolean | `true` | When true, write structured run records under `.do-work/runs/`. Consumers: `lib/run-ledger.sh`, `agents/run.md`. |
| `delivery.mode` | string | `merge` | How `agents/run.md` Step 4 delivers a passing REQ. `merge` (default): merge `req/REQ-NNN` into the **integration base** from go/run pre-flight (`lib/ensure-integration-base.sh` — never `main`/`master`/remote HEAD), archive, tear down the worktree, delete the branch. `pr` replaces the local merge with a GitHub PR: push the branch, open a PR via `gh pr create`, record the PR URL in the archived REQ's `## Outputs` and the ledger entry, archive, tear down the worktree — but leave the branch alive (the PR owns it). `pr` mode requires a configured git remote and the `gh` CLI; if either is missing the run stops with a `missing-creds` stopper and the REQ stays in `working/` — it **never** silently falls back to `merge`. Consumers: `agents/run.md`, `lib/ensure-integration-base.sh`. |
| `delivery.pr.granularity` | string | `req` | Only consulted when `delivery.mode` is `pr`. `req` (default) opens one PR per REQ directly off `req/REQ-NNN`. `ur` accumulates each completed REQ branch onto the shared `new-work` integration branch and opens a single PR when that UR's backlog drains, so a whole UR ships as one reviewable PR. **Naming note:** go/run leave-default already create-or-checkout `new-work` via `ensure-integration-base` (and merge the protected tip when reusing) even when `delivery.mode` is `merge` — the `new-work` name does **not** require pr mode; `granularity: ur` only controls PR open/accumulate behaviour when mode is `pr`. Consumers: `agents/run.md`, `lib/ensure-integration-base.sh`. |
| `verify.threshold` | integer | `90` | Minimum confidence score (0-100) that `agents/go.md` requires before auto-running without `--force`. Consumers: `agents/verify.md`, `agents/go.md`. |
| `routing` | list of `{match, agent}` maps | `[]` | Ordered subagent-routing rules for the run orchestrator's REQ classification. Each entry is `{match: <signal description or keyword list>, agent: <subagent_type>}`. The classifier scans rules top-to-bottom (first match wins) and dispatches the matching `agent`; if no rule matches — or the list is empty — it falls back to `general-purpose` silently. Ships empty so the stock skill is portable (no machine-specific agents). A commented example block in the template above reproduces the original specialist table for users who want to restore it. Consumers: `agents/run.md`, `agents/resume.md`. |
| `worktree.link_paths` | list of strings | `[]` | Extra dependency directories to symlink from the main checkout into each worker worktree (e.g. `[server/vendor, web/node_modules]`). Additive to auto-detected dirs: `composer.json` → `vendor`, `package.json` → `node_modules`, `pyproject.toml` / `requirements.txt` → `.venv`. Use this for monorepo or subdir layouts where the auto-detection misses a directory. Consumers: `lib/provision-worktree.sh`. |
| `worktree.setup_command` | string | `""` | Optional fallback command run inside the worktree when a dependency directory is absent from the main checkout and cannot be symlinked (e.g. `"composer install --no-interaction"`). The provisioner tries symlinking first (symlink-first semantics); this command runs only when a required dir is missing and symlinking fails. Empty = no fallback (the worktree is used as-is). Consumers: `lib/provision-worktree.sh`, `agents/run-worker.md`. |
| `tracker.backend` | string | `"markdown"` | Work-item store backend: `markdown` (default — local `.do-work/` + `lib/*.sh`), `linear` (Linear as sole work-item store), or `sqlite` (`.do-work/work.db` via `lib/dw-db.sh` as sole store). **Unset, empty, or missing key resolves to `markdown`** — no hard-stop, no Linear/`sqlite3` required. No dual-write between backends. When `linear`, Load Config step 7 hard-fails if team cannot be resolved, Linear MCP tools are undiscoverable, or any `status_map` state is missing on the team. When `sqlite`, Load Config step 7b hard-fails if `sqlite3` is missing, `sqlite.md` is missing/unreadable, or the DB is corrupt / bad `user_version` after ensure — **never** fall back to markdown. Consumers: all phase agents that touch URs/REQs via `agents/tracker/port.md` + `agents/tracker/<backend>.md`. |
| `tracker.sqlite.path` | string | `""` | Path to the work-item SQLite DB when `backend: sqlite`. Empty → `{project}/.do-work/work.db`. Gitignored binary; not a second store when backend is markdown/linear. Consumers: `lib/dw-db.sh`, `agents/tracker/sqlite.md`, Load Config step 7b. |
| `tracker.sqlite.board_path` | string | `""` | Path for the static HTML board snapshot (`/do-work board`, sqlite-only). Empty → `{project}/.do-work/board/index.html`. Consumers: board command, `agents/tracker/sqlite.md`. |
| `tracker.sqlite.busy_timeout_ms` | integer | `5000` | SQLite `busy_timeout` in milliseconds for `dw-db` open. Consumers: `lib/dw-db.sh`. |
| `tracker.linear.team_id` | string | `""` | Linear team UUID. **Required when `backend: linear`** unless `team_key` alone resolves the team. Empty + unresolvable team_key → hard-fail (do not guess). Consumers: `agents/tracker/linear.md`, Load Config step 7. |
| `tracker.linear.team_key` | string | `""` | Optional alternate team resolve (Linear team key string). Used when `team_id` is empty. Consumers: `agents/tracker/linear.md`, Load Config step 7. |
| `tracker.linear.default_assignee_id` | string | `""` | Human operator Linear user id set as issue **assignee** on create when non-empty. Agents claim via workflow status + claim comments — they do not steal assignee. Consumers: `agents/tracker/linear.md` create/claim ops. |
| `tracker.linear.product_project` | string | `""` | Shared Linear Project (**name or UUID**) that holds all UR Project Milestones + Issues — **not** one Project per UR. **Default is empty**, not the skill name `do-work`. When `backend: linear`, Load Config step 9 resolve order: (1) explicit non-empty `product_project` (name\|UUID) wins and is never replaced by the empty-fallback chain; (2) if empty/missing → `project.name`; (3) if that empty → git-root directory basename; (4) `ensure_product_container` create-if-missing; (5) **always persist** the resolved Project **UUID** back to this key. Explicit existing values (including a bound UUID) are left alone by the fallback chain; only ensure's UUID bind may update the field after a true empty (or name→UUID bind). Consumers: `agents/tracker/linear.md`, `ensure_product_container`, intake/`create_ur`. |
| `tracker.linear.ur_milestone_name_pattern` | string | `"{ur_id}: {title}"` | Human-facing Project Milestone name pattern for each UR. `{ur_id}` is the sequential UR slug; `{title}` is the brief title. Consumers: `agents/tracker/linear.md` create_ur / list_urs. |
| `tracker.linear.project_name_pattern` | string | `"do-work/{ur_id}"` | **Deprecated** pattern for per-UR Linear Project name (ignored for UR home; URs are Project Milestones on `product_project`). Kept for migrate compatibility. Consumers: legacy notes only. |
| `tracker.linear.initiative_title_pattern` | string | `"{ur_id}: {title}"` | Pattern for Initiative title. `{title}` is the human-facing brief title. Consumers: `agents/tracker/linear.md` intake. |
| `tracker.linear.status_map.backlog` | string | `"Todo"` | Team workflow state name for unclaimed/backlog REQs. **Hard-fail** if this state is missing on the team when `backend: linear` — rename the team state or override this key. Consumers: claim/list/status ops in `agents/tracker/linear.md`. |
| `tracker.linear.status_map.in_progress` | string | `"In Progress"` | Team workflow state for claimed/in-progress REQs. Same missing-state hard-fail as other status_map keys. Consumers: claim/heartbeat/resume. |
| `tracker.linear.status_map.stopped` | string | `"Canceled"` | Team workflow state for stopped REQs. Override if the team has a dedicated Stopped state. Same missing-state hard-fail. Consumers: set_req_status, resume. |
| `tracker.linear.status_map.done` | string | `"Done"` | Team workflow state for archived/done REQs. Same missing-state hard-fail. Consumers: archive_req. |
| `tracker.linear.labels.layer_prefix` | string | `"Layer/"` | Prefix for layer labels (e.g. `Layer/agents`). Consumers: create_req / update_req on Linear. |
| `tracker.linear.labels.path_unit` | string | `"path-unit"` | Label applied to path-unit parent Issues. Consumers: create_req. |
| `tracker.linear.labels.size_prefix` | string | `"Size/"` | Prefix for size labels (e.g. `Size/M`). Consumers: create_req. |
| `tracker.linear.agent_claim_marker` | string | `"<!-- do-work-claim -->"` | HTML comment marker at the start of agent claim-protocol comments. Consumers: claim_req, heartbeat_req, unblock_req, list_claimable_reqs. |
| `tracker.linear.heartbeat_max_age_seconds` | integer or null | `null` | Max age of latest active claim heartbeat before the claim is stale. **`null` → use `parallel.stale_threshold_seconds`** (default `900`). Consumers: claim eligibility, scan-stale equivalent on Linear. |
| `tracker.linear.decisions_doc_title` | string | `"do-work/decisions"` | Team Doc title for standing decisions (create-if-missing). Consumers: append_decision, capture/ideate readers. |
| `tracker.linear.calibration_doc_title` | string | `"do-work/calibration"` | Team Doc title for calibration body. Consumers: retro write; capture read. |
