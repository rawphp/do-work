# REQ-012: Create v1.0.0 git tag and GitHub release

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

After all other UR-004 REQs are committed, create a `v1.0.0` git tag and a GitHub release with release notes summarizing the skill's capabilities.

## Context

Users need a stable version to reference. Without tags, everyone is on `main` HEAD with no way to pin to a known-good version.

## Acceptance Criteria

- [x] `v1.0.0` git tag exists
- [x] GitHub release created with title "v1.0.0" and release notes
- [x] Release notes cover: what do-work is, key commands, installation

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `git tag -l "v1.0.0"`
   - Expected: "v1.0.0"

## Outputs

- v1.0.0 git tag
- GitHub release with release notes
