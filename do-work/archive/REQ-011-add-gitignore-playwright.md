# REQ-011: Add .playwright-mcp to .gitignore

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Add `.playwright-mcp/` to the `.gitignore` file. This directory was created during local testing and shows as untracked. It should not be committed to the public repo.

## Context

Clean repo for public release — no local testing artifacts should be visible.

## Acceptance Criteria

- [x] `.playwright-mcp/` is listed in `.gitignore`
- [x] `git status` no longer shows `.playwright-mcp/` as untracked

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `grep -c "playwright-mcp" .gitignore`
   - Expected: 1

## Outputs

- .gitignore — Added .playwright-mcp/ to ignored paths
