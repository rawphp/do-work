# REQ-007: Fix manual clone URL to use HTTPS

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Change the manual clone command in README.md from SSH (`git@github.com:rawphp/do-work.git`) to HTTPS (`https://github.com/rawphp/do-work.git`). Public users won't have SSH keys configured for the rawphp org.

## Context

The install.sh already uses HTTPS correctly. The README's "Or clone manually" section uses SSH, which will fail for most public users.

## Acceptance Criteria

- [x] Manual clone command in README uses HTTPS URL
- [x] install.sh remains unchanged (already correct)

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `grep -c "git@github.com" README.md`
   - Expected: 0 (no SSH URLs remain)

## Outputs

- README.md — Updated manual clone URL from SSH to HTTPS
