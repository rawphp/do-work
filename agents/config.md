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
  mode: merge            # how run.md Step 4 delivers a passing REQ: "merge" (default — merge req/REQ-NNN into base locally, as today) or "pr" (push the branch and open a GitHub PR instead of merging). pr mode requires a configured git remote and the `gh` CLI; missing either stops with a missing-creds stopper — it NEVER silently falls back to merge.
  pr:
    granularity: req     # only consulted when mode: pr. "req" (default) opens one PR per REQ off req/REQ-NNN; "ur" accumulates each REQ branch onto a shared ur/UR-NNN branch and opens a single PR when that UR's backlog drains.

verify:
  threshold: 90          # minimum confidence score (0-100) for go to auto-run without --force

notifications:
  on_pending_validation: ""  # shell command to run when a REQ parks as pending-validation.
                             # Placeholders: {req} = REQ id (e.g. REQ-234), {title} = first line
                             # of the REQ's Task section, {checks} = newline-joined outstanding
                             # Post-merge validation items. Empty = disabled (no execution, no overhead).
                             # Example (Telegram via curl):
                             #   on_pending_validation: >
                             #     curl -s -X POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage
                             #     -d chat_id=$TELEGRAM_CHAT_ID
                             #     -d text="⏳ {req} pending validation: {checks}"
                             # Example (macOS notification):
                             #   on_pending_validation: "osascript -e 'display notification \"{checks}\" with title \"do-work: {req} pending\"'"

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

4. **Migrate missing keys to disk.** Compare the existing config.yml against the default template above. For each top-level section (`project`, `log`, `next_steps`, `feedback`, `parallel`, `review`, `acceptance`, `risk`, `security`, `model`, `cost`, `ledger`, `delivery`, `verify`, `notifications`, `routing`) and each key within those sections:

   - If a **top-level section is entirely missing** from the file (e.g. `next_steps:` does not appear), append the full section block — including all keys, default values, and inline comments — to the end of the file.
   - If a **top-level section exists but is missing individual keys** (e.g. `log:` exists but `batch_size` is absent), append the missing keys with their default values to that section. This applies to nested-map keys too — e.g. if `log:` exists but `log.max_chars` is absent, append it with its default map (`{x: 280, linkedin: 1300}`) and inline comment.
   - **Never overwrite existing values.** If a key exists in the file, keep the user's value regardless of what the default says. For nested maps, treat presence of the parent key as "existing" — if `log.max_chars:` is present, do not overwrite any of its entries or add missing platform entries, even if the default template has more.
   - If **no keys are missing**, do not write to the file. Skip this step silently.
   - If keys were added, report: `Config updated: added [list of added keys/sections]`

5. Keep the final merged values (file values + defaults for anything still missing) in context for subsequent steps.

**Never fail or stop because of a missing or incomplete config.** If config creation or migration fails for any reason, proceed with in-memory defaults.

---

## Config Schema Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` | Project display name |
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
| `delivery.mode` | string | `merge` | How `agents/run.md` Step 4 delivers a passing REQ. `merge` (default) reproduces today's behaviour byte-for-byte: merge `req/REQ-NNN` into the base branch locally, archive, tear down the worktree, delete the branch. `pr` replaces the local merge with a GitHub PR: push the branch, open a PR via `gh pr create`, record the PR URL in the archived REQ's `## Outputs` and the ledger entry, archive, tear down the worktree — but leave the branch alive (the PR owns it). `pr` mode requires a configured git remote and the `gh` CLI; if either is missing the run stops with a `missing-creds` stopper and the REQ stays in `working/` — it **never** silently falls back to `merge`. Consumers: `agents/run.md`. |
| `delivery.pr.granularity` | string | `req` | Only consulted when `delivery.mode` is `pr`. `req` (default) opens one PR per REQ directly off `req/REQ-NNN`. `ur` accumulates each completed REQ branch onto a shared `ur/UR-NNN` integration branch and opens a single PR when that UR's backlog drains, so a whole UR ships as one reviewable PR. Consumers: `agents/run.md`. |
| `verify.threshold` | integer | `90` | Minimum confidence score (0-100) that `agents/go.md` requires before auto-running without `--force`. Consumers: `agents/verify.md`, `agents/go.md`. |
| `notifications.on_pending_validation` | string | `""` | Shell command template executed once when a REQ parks as `pending-validation`. Supports three placeholders: `{req}` (REQ id, e.g. `REQ-234`), `{title}` (first line of the REQ's Task section), `{checks}` (newline-joined outstanding `## Post-merge validation` items). Placeholders are substituted before execution. Empty or absent = disabled — no command runs and no warning prints. A non-zero exit or missing binary produces at most a one-line warning and never stops the loop. Typical uses: Telegram ping via `curl`, macOS `osascript` alert, webhook `curl`. Consumers: `agents/run.md` Step 4 park sequence. |
| `routing` | list of `{match, agent}` maps | `[]` | Ordered subagent-routing rules for the run orchestrator's REQ classification. Each entry is `{match: <signal description or keyword list>, agent: <subagent_type>}`. The classifier scans rules top-to-bottom (first match wins) and dispatches the matching `agent`; if no rule matches — or the list is empty — it falls back to `general-purpose` silently. Ships empty so the stock skill is portable (no machine-specific agents). A commented example block in the template above reproduces the original specialist table for users who want to restore it. Consumers: `agents/run.md`, `agents/resume.md`. |
