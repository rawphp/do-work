# REQ-010: Add GitHub issue and PR templates

**UR:** UR-004
**Status:** done
**Created:** 2026-03-14

## Task

Create `.github/` directory with:
- `ISSUE_TEMPLATE/bug_report.md` — bug report template
- `ISSUE_TEMPLATE/feature_request.md` — feature request template
- `pull_request_template.md` — PR template

Keep templates minimal and focused on what's needed for a Claude Code skill project.

## Context

Standard GitHub community scaffolding helps public contributors submit well-structured issues and PRs.

## Acceptance Criteria

- [x] `.github/ISSUE_TEMPLATE/bug_report.md` exists with title, description, and repro steps sections
- [x] `.github/ISSUE_TEMPLATE/feature_request.md` exists with use case and proposal sections
- [x] `.github/pull_request_template.md` exists with summary and test plan sections

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **build** `ls .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md .github/pull_request_template.md`
   - Expected: All three files listed without errors

## Outputs

- .github/ISSUE_TEMPLATE/bug_report.md — Bug report template
- .github/ISSUE_TEMPLATE/feature_request.md — Feature request template
- .github/pull_request_template.md — PR template
