---
name: do-work
description: >
  Project management skill for the do-work system — a file-based autonomous loop
  that turns natural-language briefs into discrete, traceable tasks (REQ files)
  and executes them one at a time with TDD and a git commit per task.
  Triggers on: "do-work", "intake", "capture", "verify", "run the loop",
  "backlog", "user request", "REQ-", "UR-", "question", "audit".
---

# do-work

File-based project management: Start → Go. (Or granular: Intake → Capture → Verify → Run.)

## Quick Reference

| Command | What it does |
|---------|-------------|
| `/do-work start [brief]` | Records brief + decomposes into REQs in one shot. Includes ideate by default. Auto-installs if needed. |
| `/do-work start [brief] --no-ideate` | Same as start, but skips the creativity review before decomposition. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks for this UR (records `layers_in_scope: []`). |
| `/do-work go [UR-NNN]` | Verifies coverage, auto-runs if >= 90% confidence. |
| `/do-work go [UR-NNN] --force` | Verifies + runs regardless of confidence score. |
| `/do-work go [UR-NNN] --auto-fix` | Verifies, auto-fixes gaps, then runs if >= 90%. |
| `/do-work go [UR-NNN] --no-layers` | Verify + run, skipping layer-coverage checks for this UR. |
| `/do-work install` | Creates `do-work/` structure in current project. |
| `/do-work intake [brief]` | Records brief verbatim as next UR file. |
| `/do-work capture [UR-NNN]` | Decomposes a UR brief into REQ files in the backlog. |
| `/do-work question [UR-NNN]` | Grills you about your brief — extracts assumptions, gaps, constraints. |
| `/do-work audit [UR-NNN]` | Interrogates REQ quality — auto-fixes soft spots, reports changes. |
| `/do-work ideate [UR-NNN]` | Surfaces assumptions, risks, and connections in a brief. |
| `/do-work verify [UR-NNN]` | Scores REQ coverage against brief (0-100%), lists gaps. |
| `/do-work verify [UR-NNN] --auto-fix` | Verify + auto-create missing REQs. |
| `/do-work run` | Executes backlog: TDD loop, one REQ at a time, commit per REQ. |
| `/do-work log` | Generates build-in-public draft posts for configured platforms. |
| `/do-work` | Show this help. |

---

## Agent files

Detailed instructions for each phase live in separate files. Read the referenced file and follow it exactly.

- [agents/start.md](agents/start.md) — Orchestrator: intake + ideate + capture
- [agents/go.md](agents/go.md) — Orchestrator: verify + conditional run
- [agents/intake.md](agents/intake.md) — Records brief verbatim as next UR file
- [agents/question.md](agents/question.md) — Interactive brief questioning
- [agents/audit.md](agents/audit.md) — Autonomous REQ quality audit
- [agents/ideate.md](agents/ideate.md) — Surfaces assumptions, risks, and connections
- [agents/capture.md](agents/capture.md) — Decomposes brief into REQ files
- [agents/verify.md](agents/verify.md) — Scores REQ coverage against brief
- [agents/run.md](agents/run.md) — Orchestrator: dispatches a worker subagent per REQ
- [agents/run-worker.md](agents/run-worker.md) — Worker: TDD-and-commits a single REQ in a fresh subagent session
- [agents/log.md](agents/log.md) — Generates build-in-public draft posts
- [agents/config.md](agents/config.md) — Reusable config loading instructions

---

## Project Root Detection

At the start of every subcommand:

```bash
git rev-parse --show-toplevel
```

If this fails (not a git repo), use the current working directory.
All references below use `{project}` to mean this resolved root.

**Critical: skill directory is read-only at runtime.** The skill is loaded from `~/.claude/skills/do-work/` — this is a separate git clone. NEVER edit files, stage changes, or commit inside the skills directory. All edits and commits MUST happen in `{project}`. If a REQ targets agent files (e.g. `agents/log.md`), edit them at `{project}/agents/log.md`, not at the skill clone path.

---

## File Naming

- User requests: `UR-001`, `UR-002`, ... (zero-padded to 3 digits)
- Feature requests: `REQ-001-short-slug.md`, `REQ-002-short-slug.md`, ...
- Slugs are lowercase kebab-case, max 5 words

## Milestone Mode

When a UR file contains both:

1. The marker `source: /saas-thesis handoff` (in frontmatter or body)
2. A `### Milestones` heading with `#### M1` (or higher) subheadings

`/do-work` enters **milestone mode**. The differences from normal flow:

- Capture decomposes ONE milestone at a time, not the whole UR.
- REQ files are prefixed: `REQ-M1-001-<slug>.md`, `REQ-M2-001-<slug>.md`.
- Run loop halts at the end of each milestone's REQs and prompts for the deploy gate.
- Deploy-gate sign-off is non-delegable human confirmation.
- State files in `{project}/do-work/state/`:
  - `active-milestone.md` — single line, current milestone identifier (e.g. `M1`).
  - `milestones.md` — checklist of all milestones with status: `pending` / `captured` / `running` / `deployed`.

Milestone mode is **implicit** — triggered by UR shape, not a flag. URs that do not match the trigger continue to behave as before. The `/saas-thesis` skill produces UR files with the correct shape for handoff.

## Layers

do-work uses project-declared layers to gap-check feature briefs. Declare your project's layers once in `do-work/config.yml`:

```yaml
layers: [frontend, backend]   # web app
# layers: [commands, core, output]            # CLI tool
# layers: [public_api, internal]              # library / SDK
# layers: [agents, commands, templates]       # do-work itself
```

Capture and verify use this list to enforce that REQs cover every declared layer for `feature`-class briefs (or surface explicit "no" decisions). Empty `layers:` opts out — feature briefs will halt until layers are declared or `--no-layers` is passed.

Every REQ written by capture carries a `**Layer:**` field naming one of the declared layers, or `none` for bug-fix / pure-refactor / test-only REQs.

Feature REQs that add new surface (anything callable or visible from outside their own code) include an `## Integration` section answering three sub-questions:

- **Reachability** — How does the user (or caller) reach this?
- **Data dependencies** — What existing data does this read or write?
- **Service dependencies** — What existing services or modules does this extend?

Capture inspects the codebase to draft answers and verifies each cited file/symbol exists before claiming high confidence. Verify enforces the Integration block on every non-`none` feature REQ.

## Commit Convention

```
feat(REQ-NNN): short title

REQ: do-work/archive/REQ-NNN-slug.md
UR: do-work/user-requests/UR-NNN/input.md
Output: path/to/primary/output
```

---

## Subcommand Instructions

### No subcommand

Print the Quick Reference table, then read and follow [agents/help.md](agents/help.md) to display contextual suggestions.

---

### install

Create the do-work folder structure. Idempotent — safe to run multiple times.

1. Detect `{project}`.
2. Create directories if they do not already exist:
   - `{project}/do-work/user-requests/`
   - `{project}/do-work/working/`
   - `{project}/do-work/archive/`
   - `{project}/do-work/logs/`
3. Create `{project}/do-work/config.yml` if it does not already exist, using the default template below:

```yaml
# do-work configuration
# Edit this file to customize agent behavior.

project:
  name: ""

log:
  enabled: true
  platforms: []          # e.g. [x, linkedin]
  drafts_per_platform: 2
```

4. Report what was created vs already existed. Example:

```
do-work installed at /path/to/project/do-work/

Created:
  do-work/user-requests/
  do-work/working/
  do-work/archive/
  do-work/logs/
  do-work/config.yml

Ready. Run `/do-work start` to record your first brief.
```

If already installed, report "Already installed." and stop.

---

### start [brief] [--no-ideate] [--no-layers]

Record a brief and decompose it into REQ files in one shot. Ideate runs by default and ends with an interactive gate (Grill / Continue / Stop).

1. Detect `{project}`.
2. Check if `{project}/do-work/` exists. If not, run install automatically first, then continue.
3. Determine the brief:
   - If text was provided after `start`, use it as the brief.
   - If not, ask the user to paste their brief and wait.
4. Note whether `--no-ideate` or `--no-layers` are present in the arguments.
5. Read [agents/start.md](agents/start.md) in full.
6. Follow the start agent instructions exactly. Ideate runs by default unless `--no-ideate` was present. Pass `--no-layers` through to capture if present.

---

### go [UR-NNN] [--force] [--auto-fix]

Verify REQ coverage and conditionally execute the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--force` or `--auto-fix` are present in the arguments.
4. Read [agents/go.md](agents/go.md) in full.
5. Follow the go agent instructions exactly. Pass through any flags.

---

### intake [brief]

Record a natural-language brief as the next UR file. Never skip to planning or implementation.

1. Detect `{project}`.
2. Check if `{project}/do-work/` exists. If not, run install automatically first, then continue.
3. Determine the brief:
   - If text was provided after `intake`, use it as the brief.
   - If not, ask the user to paste their brief and wait.
4. Read [agents/intake.md](agents/intake.md) in full.
5. Follow the intake agent instructions exactly.

---

### capture [UR-NNN]

Decompose a UR brief into discrete REQ files in the backlog.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to capture.
3. Confirm `{project}/do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/capture.md](agents/capture.md) in full.
5. Follow the capture agent instructions exactly.

---

### ideate [UR-NNN]

Surface assumptions, risks, and connections in a brief before decomposition.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to review.
3. Confirm `{project}/do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/ideate.md](agents/ideate.md) in full.
5. Follow the ideate agent instructions exactly.

---

### question [UR-NNN]

Grill the user about their brief — extract assumptions, gaps, and constraints through one-at-a-time questioning.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to question.
3. Confirm `{project}/do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/question.md](agents/question.md) in full.
5. Follow the question agent instructions exactly.

---

### audit [UR-NNN]

Interrogate REQ quality for a given UR — auto-fix soft spots and report changes.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to audit.
3. Confirm `{project}/do-work/user-requests/{UR-NNN}/input.md` exists. If not, report error and stop.
4. Read [agents/audit.md](agents/audit.md) in full.
5. Follow the audit agent instructions exactly.

---

### verify [UR-NNN] [--auto-fix]

Score REQ coverage against the original brief. List gaps and issues.

1. Detect `{project}`.
2. Determine the UR:
   - If `UR-NNN` was provided, use it.
   - If not, list `{project}/do-work/user-requests/` and ask which UR to verify against.
3. Note whether `--auto-fix` is present in the arguments.
4. Read [agents/verify.md](agents/verify.md) in full.
5. Follow the verify agent instructions. If `--auto-fix` was present, follow the auto-fix section.

---

### run

Execute the backlog autonomously — one REQ at a time — until empty or a stopper is hit. The orchestrator dispatches a fresh worker subagent per REQ (see [agents/run-worker.md](agents/run-worker.md)) and reads its structured return report.

1. Detect `{project}`.
2. Pre-flight checks:
   - If a REQ file exists in `{project}/do-work/working/`, report it and ask the user: resume or abort?
   - If no `REQ-NNN-*.md` files exist in `{project}/do-work/` (backlog root), report "Backlog is empty." and stop.
3. Read [agents/run.md](agents/run.md) in full.
4. Follow the run agent instructions exactly.

---

### log

Generate build-in-public draft posts for configured social media platforms.

1. Detect `{project}`.
2. Read [agents/log.md](agents/log.md) in full.
3. Follow the log agent instructions exactly.
