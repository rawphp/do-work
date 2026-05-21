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

## Questions?

Open an issue — we're happy to help.
