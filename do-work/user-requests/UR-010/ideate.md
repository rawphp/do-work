# Ideate — UR-010

**Reviewed:** 2026-03-22

## Explorer — Assumptions & Perspectives

- **The user (Tom) is also the skill author and primary consumer** — this means the change affects both the developer experience of maintaining the skill and the user experience of invoking it. Both perspectives matter, but Tom likely cares most about invocation ergonomics.
- **Claude Code's Skill tool already supports colon-namespaced skills** (e.g. `skill: "ms-office-suite:pdf"`) — but this is for namespacing entire skills, not for subcommand routing within a single skill. The colon in `/do-work:start` would be a different semantic use (subcommand dispatch) than the existing colon (namespace separator).
- **Other consumers of the do-work system may exist** — if other projects or users rely on the current `/do-work start` format (via CLAUDE.md instructions or muscle memory), changing the format is a breaking change.

## Challenger — Risks & Edge Cases

- **Colon format could collide with Claude Code's namespace convention** — `/do-work:start` looks like "use the `start` skill from the `do-work` namespace." If Claude Code ever adds proper namespace support, this could cause ambiguity or breakage. The Skill tool already uses colon for `ms-office-suite:pdf` style lookups.
- **Supporting both formats doubles the routing surface** — every future subcommand addition needs to be registered in two places or parsed two ways. This adds maintenance burden for marginal gain.
- **CLAUDE.md and AGENTS.md files across multiple projects reference the space-separated format** — grep shows references like "Run `/do-work start`" in documentation. All of these would need updating or would become stale.
- **Flag handling gets ambiguous with colon format** — `/do-work:start --no-ideate my brief` vs `/do-work:go UR-003 --force` — the argument parsing is already implicit in agent markdown. Adding a second dispatch format without a real parser increases fragility.

## Connector — Links & Reuse

- **37 REQs already shipped using the current format** — the system is mature and working. The format is established convention across the codebase.
- **The Skill tool's argument passing mechanism is the real router** — when you invoke `skill: "do-work", args: "start my brief"`, Claude Code passes everything after the skill name as args. The colon format would require the Skill tool to split on colon, which it may or may not support for subcommand routing (vs namespace resolution).
- **No other skills in `~/.claude/skills/` use colon-separated subcommands** — `graphic-designer`, `landing-page-architect`, `seo-*` all use either single invocations or space-separated arguments. Adopting colons would be a novel pattern.

## Summary

The colon format (`/do-work:start`) risks conflicting with Claude Code's existing namespace convention (which uses colons for a different purpose) and adds maintenance burden without clear ergonomic gain. The space-separated format is already established across 37 shipped REQs, multiple projects, and aligns with how the Skill tool passes arguments. If the goal is cleaner invocation, the current format is already concise — the real question is whether this solves a problem Tom is actually experiencing.
