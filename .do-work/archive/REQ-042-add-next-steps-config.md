# REQ-042: Add next_steps config toggle

**UR:** UR-012
**Status:** done
**Created:** 2026-03-22

## Task

Add a `next_steps.enabled` key to `config.yml` and the config schema in `agents/config.md`. Default value: `false`. When `true`, agents should present next-step options via `AskUserQuestion` at the end of their report. When `false` (or missing), agents behave exactly as they do today.

## Context

The user wants an on/off switch in config for presenting next steps using AskUserQuestion after every agent step. This REQ adds the config key only — subsequent REQs wire it into each agent.

## Acceptance Criteria

- [x] `config.yml` default template includes `next_steps.enabled: false`
- [x] `agents/config.md` schema reference table includes `next_steps.enabled` with type boolean, default `false`, and description
- [x] Config loader handles missing `next_steps` section gracefully (defaults to `false`)

## Outputs

- agents/config.md — Added `next_steps.enabled` to default template and schema reference
- do-work/config.yml — Added `next_steps.enabled: false`

## Verification Steps

> Execute these after implementation to confirm the feature actually works at runtime. Each must pass before committing.

1. **test** Read `agents/config.md` and confirm `next_steps.enabled` appears in the schema reference table
   - Expected: Row for `next_steps.enabled` with type boolean, default `false`
2. **test** Read `agents/config.md` default template and confirm `next_steps` section exists
   - Expected: `next_steps.enabled: false` in the default YAML block
