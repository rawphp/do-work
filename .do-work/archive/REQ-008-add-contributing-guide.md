# REQ-008: Add CONTRIBUTING.md

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Create a CONTRIBUTING.md at the repo root covering: how the skill is structured (agent files in `agents/`), how to test changes locally (clone to `~/.claude/skills/do-work`), how to submit PRs, and the commit convention.

## Context

Public contributors need guidance on how the skill works internally and how to propose changes. Without this, PRs will be inconsistent or people won't know where to start.

## Acceptance Criteria

- [x] `CONTRIBUTING.md` exists at repo root
- [x] Covers: skill structure, local development, PR process, commit convention
- [x] Concise — under 100 lines (71 lines)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `test -f CONTRIBUTING.md && echo "exists"`
   - Expected: "exists"

## Outputs

- CONTRIBUTING.md — Contribution guide covering skill structure, local dev, PRs, and commit convention
