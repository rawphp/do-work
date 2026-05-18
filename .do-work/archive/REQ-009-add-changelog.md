# REQ-009: Add CHANGELOG.md

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Create a CHANGELOG.md at the repo root documenting the initial release. Use Keep a Changelog format. Document the existing features as v1.0.0.

## Context

Users and contributors need a way to track what changed between versions, especially once updates start flowing.

## Acceptance Criteria

- [x] `CHANGELOG.md` exists at repo root
- [x] Uses Keep a Changelog format
- [x] Documents v1.0.0 with existing features (start, go, intake, capture, ideate, verify, run, install)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `grep -c "1.0.0" CHANGELOG.md`
   - Expected: At least 1 match

## Outputs

- CHANGELOG.md — Initial changelog with v1.0.0 release notes
