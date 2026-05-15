# Do Work

A Claude Code skill that turns natural-language briefs into discrete, traceable tasks and executes them autonomously — with TDD and a git commit per task.

Two commands: `/do-work start` to define the work, `/do-work go` to execute it.

---

## Installation

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/rawphp/do-work/main/install.sh | bash
```

### Or clone manually

```bash
git clone https://github.com/rawphp/do-work.git ~/.claude/skills/do-work
```

That's it. Claude Code picks up the `/do-work` slash command automatically.

---

## Quick Start

### Step 1 — Start

```
/do-work start I need a user settings page with email and password change
```

This records your brief, runs a creative review (ideate), and decomposes it into REQ files — all in one shot.

Add `--no-ideate` to skip the creative review. Add `--no-layers` to skip layer-coverage checks for this UR (records the choice in UR state for audit).

Ideate now ends with an interactive gate — after surfacing gaps, it asks whether you want to be **grilled** with one-at-a-time questions, **continue** to capture as-is, or **stop** to revise the brief yourself.

### Step 2 — Go

```
/do-work go UR-001
```

Verifies REQ coverage against your brief. If confidence >= 90%, auto-executes the backlog. Each REQ gets TDD'd and committed individually.

Flags:
- `--force` — run regardless of confidence score
- `--auto-fix` — auto-create missing REQs before checking the threshold

---

## All Commands

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Records brief + decomposes into REQs. Includes ideate by default. |
| `/do-work start [brief] --no-ideate` | Same, but skips the creative review. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks (records `layers_in_scope: []` for this UR). |
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs. |
| `/do-work go [UR-NNN] --no-layers` | Verifies + runs, but skips layer-coverage checks for this UR. |
| `/do-work install` | Creates `do-work/` folder structure in current project. |
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR into REQ files. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run` | Executes backlog: TDD loop, one REQ at a time. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show help. |

---

## How It Works

1. **Intake** — Your brief is recorded as `UR-NNN/input.md` (with YAML frontmatter for capture state)
2. **Ideate** — Surfaces assumptions, risks, and connections; ends with an interactive gate (Grill / Continue / Stop)
3. **Capture** — Classifies the brief (bug-fix vs feature), assigns each REQ to one of the project's declared layers, prompts on uncovered layers, and writes an `## Integration` block on every new-surface REQ with codebase-verified file references
4. **Verify** — Scores REQ coverage against the original brief, plus three structural checks: layer coverage, Integration block presence, and partial-confidence acknowledgement
5. **Audit** *(always-on)* — Interrogates every REQ's acceptance criteria, auto-fixes vague spots, reports what changed
6. **Run** — Executes each REQ with TDD: failing test first, implement, verify, commit

`start` = intake + ideate (with gate) + capture. `go` = verify + audit + run.

---

## Skill Structure

This skill is multi-file. `SKILL.md` is the entrypoint and routes commands to agent files:

```
do-work/
├── SKILL.md              ← entrypoint and command router
├── agents/
│   ├── start.md          ← orchestrator: intake + ideate + capture
│   ├── go.md             ← orchestrator: verify + run
│   ├── intake.md         ← records brief verbatim
│   ├── question.md       ← interactive brief questioning (opt-in)
│   ├── audit.md          ← autonomous REQ quality audit (always-on)
│   ├── ideate.md         ← surfaces assumptions & risks
│   ├── capture.md        ← decomposes into REQ files
│   ├── verify.md         ← scores coverage
│   ├── run.md            ← TDD execution loop
│   ├── log.md            ← build-in-public draft posts
│   └── config.md         ← reusable config loading
├── install.sh
└── README.md
```

---

## Per-Project Folder Structure

When you run `/do-work start` in a project, it creates:

```
your-project/
└── do-work/
    ├── config.yml               ← project configuration
    ├── user-requests/
    │   └── UR-001/
    │       ├── input.md         ← your original brief
    │       ├── ideate.md        ← creative review (optional)
    │       └── assets/          ← supporting files
    ├── working/                 ← current REQ in flight
    ├── archive/                 ← completed REQs
    ├── logs/                    ← build-in-public log drafts
    └── REQ-001-slug.md          ← backlog tasks
        REQ-002-slug.md
        ...
```

Everything is auditable — the brief, decomposed tasks, and outputs all live in git history.

---

## Configuration

Each project gets a `do-work/config.yml` file, auto-created on first `/do-work start` or `/do-work install`. Edit it to customize agent behavior.

```yaml
# do-work configuration
project:
  name: "my-project"

# Project layers — capture and verify use these to gap-check briefs.
# Examples: [frontend, backend], [commands, core, output],
#           [public_api, internal], [agents, commands, templates].
# Empty list = opt out of layer-coverage checks (feature briefs will
# halt until either a list is declared or --no-layers is passed).
layers: []

log:
  enabled: true
  platforms: [x, linkedin]
  drafts_per_platform: 2
  batch_size: 2
  audience: ""
  voice: ""
  max_chars:
    x: 280
    blog: 500
    linkedin: 1300

test:
  suite_command: ""

next_steps:
  enabled: false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` | Project display name |
| `layers` | list of strings | `[]` | Project's declared layers for gap-aware capture. Capture and verify check that REQs cover each declared layer. Empty = opt out (feature briefs will halt until declared or `--no-layers` is passed). |
| `log.enabled` | boolean | `true` | Whether the log step runs after `/do-work go` |
| `log.platforms` | list | `[]` | Platforms to generate draft posts for (e.g. `[x, linkedin, blog]`) |
| `log.drafts_per_platform` | integer | `2` | Number of draft variations to generate per platform |
| `log.batch_size` | integer | `2` | Drafts to show per batch in the selection prompt (max 2 for non-final batches, 3 for final) |
| `log.audience` | string | `""` | Target audience for log posts (e.g. `"indie hackers"`, `"enterprise devs"`) |
| `log.voice` | string | `""` | Writing style for log posts (e.g. `"casual and direct"`, `"thoughtful and technical"`) |
| `log.max_chars` | map | `{x: 280, blog: 500, linkedin: 1300}` | Per-platform character ceiling the log agent enforces on every draft. Keys are platform slugs; values are integer char limits. Drafts exceeding the ceiling are rewritten, then truncated if still over. |
| `test.suite_command` | string | `""` | Full test suite command (e.g. `./vendor/bin/pest`, `npx vitest run`). If empty, common defaults are attempted. |
| `next_steps.enabled` | boolean | `false` | When true, agents present next-step options via AskUserQuestion after each phase |

---

## Layers and Integration

Feature briefs frequently produce REQs that miss the frontend, miss the wiring, or both. do-work's gap-aware capture prevents this by enforcing two structural checks.

**Declared layers.** Each project declares its layers in `do-work/config.yml` — `[frontend, backend]` for a web app, `[commands, core, output]` for a CLI, whatever fits your stack. Capture tags each REQ with one of the declared layers (or `none` for bug-fixes / pure refactors). If a brief looks full-stack but capture didn't write a REQ for a declared layer, you're prompted: *"Project has layer X, no REQ covers it. Needed?"* Yes generates the missing REQ; No records the decision so verify doesn't keep flagging it.

**Integration block.** Every feature REQ that adds new surface (a new page, route, command, endpoint, etc.) must have an `## Integration` section answering three questions, with concrete file references:
- **Reachability** — How does the user/caller reach this?
- **Data dependencies** — What existing data does it read or write?
- **Service dependencies** — What existing services or modules does it extend?

Capture inspects the codebase to draft the answers, verifies cited files actually exist before claiming high confidence, and asks you when it can't tell. Verify enforces the block on every new-surface REQ.

**Skip per-UR with `--no-layers`** when the checks don't apply (e.g. internal one-shot scripts). The choice is recorded in UR state, so it's auditable.

---

## Parallel Execution

do-work supports parallel execution across multiple terminals. Open two or three terminals, run `/do-work run` in each, and the orchestrators pick disjoint REQs from the backlog and work in parallel. No flag is needed — parallel mode is implicit when a second terminal joins.

Three guarantees keep the parallel terminals from stepping on each other:

1. **Atomic claim.** Two orchestrators racing for the same REQ resolve via `git mv` — the loser sees the source file gone and falls through to the next REQ. No double-work, no manual coordination.
2. **Visible ownership.** Each claimed REQ in `working/` carries a `**Claimed by: <agent-id>**` stamp at the top of the file so it's clear who is doing what. `agent-id` is `hostname.pid` of the owning `/do-work run` process.
3. **Wait-and-retry on conflicts.** Workers whose commits collide on shared files wait with exponential backoff (5 retries over ~110 seconds), then surface the conflict to the user via `status: stopped`, `reason: concurrent-conflict`. No silent auto-resolve.

**When parallel mode shines.** Backlogs of 5+ independent REQs — the work-sharing payoff grows with the backlog size. For single-REQ work, tightly-coupled REQs, or milestone deploy gates (which stay single-agent by design), the simplicity of one terminal is often the better trade-off.

**Isolation per REQ.** Large REQs (migrations, refactors, schema changes) automatically use `git worktree` on a `req/REQ-NNN` branch and merge back when done; small REQs (most of them) work directly on the base branch.

See `SKILL.md` `## Parallel Execution` for the full behavioural reference, including state files (`gate-owner.md`, `final-suite-running.md`) and the worktree-vs-same-branch heuristic.

---

## Build in Public (Log)

The log feature generates draft social media posts based on work you've completed — so you can share progress without writing posts from scratch.

### How it works

1. Scans `do-work/archive/` for REQs completed since the last log entry
2. Generates multiple draft posts per configured platform (different angles, not minor rewrites)
3. Presents all drafts for you to review
4. You pick one per platform — the selection is recorded in `do-work/logs/log-history.yml` so the same work isn't re-prompted

### Usage

Run it manually:

```
/do-work log
```

Or let it run automatically — `/do-work go` triggers the log step after a clean run (all REQs executed, no stoppers).

### Supported platforms

| Platform | Format |
|----------|--------|
| **X** | 280-char tweets. Threads if content exceeds one tweet. |
| **LinkedIn** | 1-3 short paragraphs, professional tone, ~1300 chars. |
| **Blog** | 1-3 short paragraphs or a single tight idea, ~500 chars default. Plain prose, no markdown headings in the body. No hashtags. Inline links, used sparingly. |

### Length enforcement

Every draft is hard-capped at `log.max_chars[platform]` before being written to disk. If a generated draft exceeds the ceiling, the agent rewrites it once; if it still exceeds, it truncates at the last sentence boundary that fits, falling back to a hard character truncation with an ellipsis if no boundary is available. The ceiling is mechanical, not aspirational — you can tune it per platform in `do-work/config.yml`.

### Configuration

Set platforms in `do-work/config.yml`:

```yaml
log:
  enabled: true
  platforms: [x, linkedin, blog]
  drafts_per_platform: 2
  max_chars:
    x: 280
    blog: 500
    linkedin: 1300
```

### Disabling the log

If you don't want build-in-public posts, set `log.enabled: false` in your project's `do-work/config.yml`:

```yaml
log:
  enabled: false
```

The log step will be skipped entirely — both for `/do-work log` and the automatic step after `/do-work go`.

---

## Commit Convention

Each completed REQ produces a commit:

```
feat(REQ-001): short title

REQ: do-work/archive/REQ-001-slug.md
UR: do-work/user-requests/UR-001/input.md
Output: path/to/primary/output
```

---

## License

MIT
