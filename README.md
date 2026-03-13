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
git clone git@github.com:rawphp/do-work.git ~/.claude/skills/do-work
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
│   └── run.md            ← TDD execution loop
├── install.sh
└── README.md
```

---

## Per-Project Folder Structure

When you run `/do-work start` in a project, it creates:

```
your-project/
└── do-work/
    ├── user-requests/
    │   └── UR-001/
    │       ├── input.md         ← your original brief
    │       ├── ideate.md        ← creative review (optional)
    │       └── assets/          ← supporting files
    ├── working/                 ← current REQ in flight
    ├── archive/                 ← completed REQs
    └── REQ-001-slug.md          ← backlog tasks
        REQ-002-slug.md
        ...
```

Everything is auditable — the brief, decomposed tasks, and outputs all live in git history.

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
