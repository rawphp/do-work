# Contributing to Do Work

Thanks for your interest in contributing! This guide covers how the skill is structured, how to develop locally, and how to submit changes.

## Skill Structure

Do Work is a Claude Code skill — a set of Markdown agent files that Claude reads and follows as instructions.

```
do-work/
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

## Questions?

Open an issue — we're happy to help.
