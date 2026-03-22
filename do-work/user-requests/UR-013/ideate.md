# Ideate — UR-013

**Reviewed:** 2026-03-22

## Explorer — Assumptions & Perspectives

- **The config loader already handles missing keys in-memory (line 34 of config.md)** — agents won't crash when a key is absent, they fall back to defaults. But the user's config.yml file never gets updated, so they can't see or toggle new options without manually editing the file to add keys they don't know about.
- **This affects every project that installed do-work before a new config key was added** — e.g. projects installed before `next_steps.enabled` was added have no `next_steps` section in their config.yml. The user has no way to discover or enable the feature without reading the schema docs.
- **There are two distinct audiences for config migration**: (1) the user who wants to discover and toggle new options, and (2) the agent runtime which just needs correct defaults. The current system serves (2) but not (1).

## Challenger — Risks & Edge Cases

- **Blindly overwriting config.yml could destroy user customizations** — if the migration strategy is "replace with default template," any values the user set (like `platforms: [x]` or `voice: "casual"`) would be lost. The merge must be additive-only: add missing keys with defaults, never overwrite existing values.
- **YAML comment preservation is fragile** — if we read, merge, and rewrite the file programmatically, inline comments (like `# e.g. [x, linkedin]`) may be lost or repositioned. Since this is an LLM-driven system (not a programmatic YAML parser), the agent can read the file, identify missing sections, and append them — preserving the existing content verbatim.
- **When should migration run?** — running it on every `Load Config` call is safe but noisy (commits on every invocation). Running it only during `install` means existing projects don't benefit until they re-run install. The sweet spot is: run during config load, but only write to disk if changes are actually needed.

## Connector — Links & Reuse

- **The `install` command is already idempotent** ("safe to run multiple times") — extending it to also migrate config would be natural, but it only runs when explicitly invoked. The config loader runs on every agent invocation, making it a better hook point.
- **REQ-042 just added `next_steps.enabled`** — this is the exact scenario that triggered the bug. The do-work project's own config.yml was manually updated, but other projects using do-work weren't.
- **The config loader in config.md is the single source of truth for defaults** — any migration logic should read the default template from there rather than duplicating defaults elsewhere.

## Summary

The fix is to enhance the config loader (config.md) to compare the existing config.yml against the default template and append any missing top-level sections with their defaults. This must be additive-only (never overwrite existing values), preserve the existing file content, and only write when changes are needed. The config loader is the right hook point since it runs on every agent invocation.
