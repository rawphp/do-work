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

Add `--no-ideate` to skip the creative review.

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
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs. |
| `/do-work install` | Creates `do-work/` folder structure in current project. |
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR into REQ files. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run` | Executes backlog: TDD loop, one REQ at a time. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show help. |

---

## How It Works

1. **Intake** — Your brief is recorded verbatim as `UR-NNN/input.md`
2. **Ideate** — Surfaces assumptions, risks, and connections before decomposition
3. **Capture** — Breaks the brief into discrete `REQ-NNN-slug.md` task files
4. **Verify** — Scores REQ coverage against the original brief (0-100%)
5. **Run** — Executes each REQ with TDD: failing test first, implement, verify, commit

`start` = intake + ideate + capture. `go` = verify + run.

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

log:
  enabled: true
  platforms: [x, linkedin]
  drafts_per_platform: 2
  batch_size: 2
  audience: ""
  voice: ""

test:
  suite_command: ""

next_steps:
  enabled: false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` | Project display name |
| `log.enabled` | boolean | `true` | Whether the log step runs after `/do-work go` |
| `log.platforms` | list | `[]` | Platforms to generate draft posts for (e.g. `[x, linkedin]`) |
| `log.drafts_per_platform` | integer | `2` | Number of draft variations to generate per platform |
| `log.batch_size` | integer | `2` | Drafts to show per batch in the selection prompt (max 2 for non-final batches, 3 for final) |
| `log.audience` | string | `""` | Target audience for log posts (e.g. `"indie hackers"`, `"enterprise devs"`) |
| `log.voice` | string | `""` | Writing style for log posts (e.g. `"casual and direct"`, `"thoughtful and technical"`) |
| `test.suite_command` | string | `""` | Full test suite command (e.g. `./vendor/bin/pest`, `npx vitest run`). If empty, common defaults are attempted. |
| `next_steps.enabled` | boolean | `false` | When true, agents present next-step options via AskUserQuestion after each phase |

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

### Configuration

Set platforms in `do-work/config.yml`:

```yaml
log:
  enabled: true
  platforms: [x, linkedin]
  drafts_per_platform: 2
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
