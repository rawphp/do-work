# Contributing to Do Work

Thanks for your interest in contributing! This guide covers how the skill is structured, how to develop locally, and how to submit changes.

## Skill Structure

Do Work is a Claude Code skill — a set of Markdown agent files that Claude reads and follows as instructions.

```
.do-work/
├── SKILL.md          ← entrypoint, command router
├── agents/
│   ├── start.md      ← orchestrator: intake + ideate + capture
│   ├── go.md         ← orchestrator: verify + run
│   ├── intake.md     ← records brief verbatim
│   ├── ideate.md     ← surfaces assumptions & risks
│   ├── capture.md    ← decomposes into REQ files
│   ├── verify.md     ← scores coverage
│   └── run.md        ← TDD execution loop
├── install.sh
└── README.md
```

Each agent file in `agents/` defines a role with specific steps, rules, and output formats. `SKILL.md` routes slash commands to the appropriate agent.

## Local Development

1. Clone the repo to the Claude Code skills directory:

```bash
git clone https://github.com/rawphp/do-work.git ~/.claude/skills/do-work
```

2. Make your changes to agent files or `SKILL.md`.

3. Test by running `/do-work` commands in any Claude Code project. Changes take effect immediately — no build step required.

4. To test without affecting your main install, clone to a temporary location and symlink:

```bash
git clone https://github.com/rawphp/do-work.git ~/do-work-dev
ln -sf ~/do-work-dev ~/.claude/skills/do-work
```

## Submitting Changes

1. Fork the repo and create a feature branch.
2. Make your changes — keep them focused and minimal.
3. Test your changes by running the relevant `/do-work` commands.
4. Open a PR with a clear description of what changed and why.

## Commit Convention

```
feat(REQ-NNN): short title       ← new feature
fix(REQ-NNN): short title        ← bug fix
docs: short title                ← documentation only
```

If your change isn't tied to a REQ, use `feat:`, `fix:`, or `docs:` without a REQ reference.

## Guidelines

- Keep agent files clear and imperative — they are instructions for Claude, not documentation for humans.
- Every agent step should be unambiguous. If Claude could interpret it two ways, rewrite it.
- Don't add features that aren't needed yet. The skill is intentionally minimal.
- Test with real `/do-work` commands before submitting.

## Completeness model

`do-work` treats feature completeness as a proof problem, not a confidence report. The system should make dropped wiring and unproven work visible by construction.

| Principle | Mechanism |
|---|---|
| Human is not the completeness detector | `/do-work status` and coverage rollups show intended vs proven work automatically. |
| Prevent by construction | Capture groups feature work into reachable path-units with entry points, terminal states, and child layer REQs. |
| Derived, not declared | Writable `**Status:**` remains coordination state; `proven` is derived from `**Closure proof:**`. |
| Localize failures | Verification steps are ordered checkpoints that report the last good step and failing handoff. |
| Human owns the oracle | `**Criteria approved:** agent-drafted` cannot silently become trusted; a human approval gate flips it to `human`. |

When changing capture, verify, run, or status behavior, preserve these invariants. A REQ should not be treated as complete merely because a worker reports `done`; it needs approved criteria, checkpointed evidence, closure proof, and derived proof visibility.

## Worker / Orchestrator Boundary

`/do-work run` enforces a strict separation between two layers of responsibility.

**Worker (`agents/run-worker.md`) — owns code.**

- Operates in a git worktree on a feature branch (`req/REQ-NNN`).
- Implements + tests + commits to that branch.
- **Never** touches `.do-work/` (no working→archive move, no metadata edits).
- **Never** merges back to the base branch.
- **Never** tears down its worktree.
- Returns a YAML report. Done.

**Orchestrator (`agents/run.md`) — owns `.do-work/`.**

- Lives in the main checkout.
- After the worker returns `status: done`: merges `req/REQ-NNN` into the base branch, moves the REQ file from `working/` to `archive/`, sets `**Status:** done`, writes the `## Outputs` section from the worker's YAML report, tears down the worktree, commits the metadata change.

This separation makes parallelism safe by construction. Workers cannot wipe each other's working trees because each one has its own checkout. Merge conflicts surface explicitly at the orchestrator's integration step rather than silently corrupting another worker's in-flight edits.

Same-branch mode has been retired. All workers — single-agent or parallel — run in worktrees.

## REQ Header Schema

Every REQ file starts with a **fixed header block** that is regex-parseable by bash scripts. Each field appears on its own line in the form `**Field:** value`. Values are plain text or comma-separated lists. No multi-line values, no nested structures.

This schema is load-bearing. Scripts in `lib/` depend on it. Capture is the only writer of these fields; audit and verify enforce them.

### Fields (in order)

| Field | Required | Value |
|---|---|---|
| `**UR:**` | yes | Single UR id (e.g. `UR-030`). |
| `**Status:**` | yes | One of `backlog`, `in-progress`, `done`, `stopped`. |
| `**Created:**` | yes | ISO-8601 date (`YYYY-MM-DD`). |
| `**Layer:**` | yes | One of the layers declared in `config.yml`, or `none`. |
| `**Files:**` | yes | Comma-separated list of project-relative paths or globs the REQ will touch. Optional spaces after commas. May be empty for pure-discussion REQs but the line must still exist. |
| `**Depends on:**` | optional value | Comma-separated list of REQ ids that must be archived before this REQ can be claimed. The line is mandatory; the value may be empty. |

### Format rules (load-bearing)

- Each header field appears **exactly once**, on its own line, in the form `**Field:** value`.
- Path lists in `**Files:**` and id lists in `**Depends on:**` are **comma-separated**, with **optional spaces after commas**.
- Paths are **project-relative**. No leading `/`, no `~`.
- **Globs are supported** in `**Files:**` (e.g. `app/Models/Foo*.php`). The overlap check expands globs against the working tree.
- Timestamps are **ISO-8601 UTC with `Z` suffix** (e.g. `2026-05-21T13:42:08Z`).
- Field ordering above is canonical. Scripts use `grep`/`sed` line-anchored patterns, not field-order assumptions, but humans and templates should follow the order.

### Claim stamp (working/ only)

When a REQ moves from `backlog/` to `working/`, the orchestrator inserts an **ownership stamp** directly under the heading, **before** the header block. The stamp is wrapped in HTML comments so it is trivially strippable on archive:

```markdown
<!-- claimed-start -->
**Claimed by:** <agent-id>
**Claimed at:** <ISO-8601 UTC>
**Heartbeat:** <ISO-8601 UTC>
<!-- claimed-end -->
```

| Field | Required | Value |
|---|---|---|
| `**Claimed by:**` | yes | Agent id (e.g. `mbp-tom.42137`). |
| `**Claimed at:**` | yes | ISO-8601 UTC timestamp with `Z` suffix. Set once at claim, never updated. |
| `**Heartbeat:**` | yes | ISO-8601 UTC timestamp with `Z` suffix. Updated repeatedly by the worker (every 60s) for liveness detection. |

`**Heartbeat:**` is the only field updated repeatedly during a worker's run. It is updated by `lib/heartbeat.sh` via `sed` — **no commit** — so siblings see freshness by reading the working/ file directly.

### Example — backlog REQ header

```markdown
# REQ-007: Add Foo model

**UR:** UR-002
**Status:** backlog
**Created:** 2026-05-21
**Layer:** backend
**Files:** app/Models/Foo.php, tests/Unit/FooTest.php
**Depends on:** REQ-005
```

### Example — working/ REQ header (with claim stamp)

```markdown
# REQ-007: Add Foo model

<!-- claimed-start -->
**Claimed by:** mbp-tom.42137
**Claimed at:** 2026-05-21T13:42:08Z
**Heartbeat:** 2026-05-21T14:08:12Z
<!-- claimed-end -->

**UR:** UR-002
**Status:** in-progress
**Created:** 2026-05-21
**Layer:** backend
**Files:** app/Models/Foo.php, tests/Unit/FooTest.php
**Depends on:** REQ-005
```

### Regex patterns used by scripts

Scripts in `lib/` use these line-anchored patterns to extract field values:

| Field | Regex (POSIX ERE) |
|---|---|
| `**UR:**` | `^\*\*UR:\*\* (.+)$` |
| `**Status:**` | `^\*\*Status:\*\* (.+)$` |
| `**Created:**` | `^\*\*Created:\*\* (.+)$` |
| `**Layer:**` | `^\*\*Layer:\*\* (.+)$` |
| `**Files:**` | `^\*\*Files:\*\* (.+)$` |
| `**Depends on:**` | `^\*\*Depends on:\*\*[[:space:]]*(.*)$` (value may be empty) |
| `**Claimed by:**` | `^\*\*Claimed by:\*\* (.+)$` |
| `**Claimed at:**` | `^\*\*Claimed at:\*\* (.+)$` |
| `**Heartbeat:**` | `^\*\*Heartbeat:\*\* (.+)$` |
| Claim block start | `^<!-- claimed-start -->$` |
| Claim block end | `^<!-- claimed-end -->$` |

After extraction, comma-separated values are split on `,` and trimmed of surrounding whitespace.

## Judgment Points

Agent files in `agents/` mark places where the model must make a judgment call that cannot be reduced to a deterministic rule. The convention has two parts: a **top-of-file index** and **inline markers**.

### Table of Contents Entry

Add `## Judgment Points` to the table of contents (or a "Sections" list) at the top of any agent file that contains judgment points, so readers can scan them before diving in.

### Top-of-File Index

Each agent file that requires model judgment SHOULD open with a `## Judgment Points in this Agent` section immediately after the intro paragraph. The index lists every judgment point in the file as a table:

```markdown
## Judgment Points in this Agent

The following steps require model judgment that cannot be reduced to a rule. Each is marked inline with a `> **JUDGMENT:**` block at the relevant step.

| # | Step | Decision |
|---|------|----------|
| J1 | Step N — <field name> | One-sentence description of what the model must decide. |
| J2 | Step N — <field name> | One-sentence description. |
```

Rules:
- Each row corresponds to exactly one inline `> **JUDGMENT:**` marker elsewhere in the file.
- The `Step` column names the heading and subheading where the marker appears (e.g. `Step 4 — Files`).
- Rows are numbered `J1`, `J2`, … in the order they appear in the file.

### Inline Markers

At the exact step where the model must exercise judgment, insert a blockquote marker immediately before the relevant instruction:

```markdown
> **JUDGMENT:** [J<n> — <label>] <What decision must be made. What inputs to use. What the failure mode of getting it wrong looks like.>
```

Rules:
- The label in brackets (`[J1 — Files]`) matches the `#` and `Step` columns in the top-of-file index.
- The body explains three things: (1) what choice the model is making, (2) what inputs or signals should guide the choice, (3) what goes wrong if the model chooses badly.
- Keep it to 1-3 sentences. If more is needed, the step itself should be split or the rule should be made explicit.

### Worked Example

The following shows both parts of the convention. It is drawn from `agents/capture.md`.

**Top-of-file index (in `agents/capture.md`):**

```markdown
## Judgment Points in this Agent

The following steps require model judgment that cannot be reduced to a rule. Each is marked inline with a `> **JUDGMENT:**` block at the relevant step.

| # | Step | Decision |
|---|------|----------|
| J1 | Step 4 — Files | Which files will this REQ touch? List paths relative to the project root. Err toward specificity; vague globs are less useful than named files. |
| J2 | Step 4 — Depends on | Which other REQs must be committed before this one can start? Only hard ordering constraints (not soft "nice to have" ordering). Empty list is valid and common. |
```

**Inline markers (inside Step 4 of `agents/capture.md`):**

```markdown
> **JUDGMENT:** [J1 — Files] Before writing the `**Files:**` line, enumerate the project-relative paths this REQ will touch. For agents: list the specific `agents/*.md` file(s). Globs are allowed but prefer named paths. A blank `**Files:**` line is a signal the REQ is under-specified — think harder before leaving it empty.

> **JUDGMENT:** [J2 — Depends on] Before writing the `**Depends on:**` line, scan the decomposition for hard ordering constraints: does this REQ assume another REQ's output file exists, or call a function another REQ will write? If yes, list those REQ ids. If independently implementable from HEAD, write an empty value. Do not add soft ordering preferences — only blocking dependencies.
```

**Why this matters:** without explicit markers, future edits to agent files silently lose the judgment context. New agent authors see a step but not the decision it asks for. The index makes them impossible to miss; the inline marker makes them impossible to edit around.

## Questions?

Open an issue — we're happy to help.
