# REQ-006: Add MIT LICENSE file

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Create a standard MIT LICENSE file at the repo root. The README already claims MIT license but no actual LICENSE file exists, which means GitHub won't detect the license and the code isn't properly licensed.

## Context

Prepping for public GitHub release. A LICENSE file is the minimum legal requirement for open-source distribution.

## Acceptance Criteria

- [x] `LICENSE` file exists at repo root with full MIT license text
- [x] Copyright holder is set to "rawphp" (matching the GitHub org)
- [x] Year is 2026

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `cat LICENSE | head -5`
   - Expected: Contains "MIT License" and copyright line with 2026

## Outputs

- LICENSE — MIT license file at repo root
