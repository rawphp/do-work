# Command Format Analysis: Space vs Colon vs Both

**Date:** 2026-03-22
**UR:** UR-010

---

## Background

The do-work system currently uses space-separated subcommands:

```
/do-work start [brief]
/do-work go [UR-NNN]
/do-work verify [UR-NNN] --auto-fix
```

The question: should this change to colon-joined format (`/do-work:start`), or should both be supported?

---

## How Claude Code's Skill Tool Handles Colons

The Skill tool accepts two invocation patterns:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `skill: "name"` | Invoke skill by name | `skill: "do-work"` |
| `skill: "namespace:name"` | Invoke skill from a namespace | `skill: "ms-office-suite:pdf"` |

**The colon is a namespace separator, not a subcommand separator.** When Claude Code sees `do-work:start`, it looks for a skill named `start` in the `do-work` namespace — it does not invoke the `do-work` skill with a `start` subcommand.

This means `/do-work:start` would require registering `start`, `go`, `capture`, `verify`, `run`, `intake`, `ideate`, `log`, and `install` as **separate skills** under a `do-work` namespace. Each would need its own SKILL.md. The current single-skill architecture would need to be completely restructured.

---

## Option 1: Keep Space-Separated (Current)

**Format:** `/do-work start [brief]`

### Pros

- **Already working.** 37+ REQs shipped, 12 URs processed, zero format-related issues.
- **Single SKILL.md router.** All subcommand dispatch lives in one file. Easy to maintain.
- **Aligns with Skill tool design.** Arguments are passed as a string to `args:`, which the skill parses internally. This is the intended pattern.
- **Flags work naturally.** `/do-work go UR-003 --force` — args are a flat string, easy to parse.
- **125+ references across 16 files** in the skill repo alone. No migration needed.
- **Familiar pattern.** Mimics CLI tools (`git status`, `docker compose up`, `npm run build`).

### Cons

- **No autocomplete/suggestions.** When you type `/do-work`, Claude Code doesn't suggest subcommands (addressed separately in UR-011).
- **Subcommand parsing is implicit.** SKILL.md uses markdown headers for routing, not a real parser.

---

## Option 2: Colon-Joined

**Format:** `/do-work:start [brief]`

### Pros

- **Visual distinction.** The colon signals "this is a subcommand" rather than an argument.
- **Potentially discoverable.** If Claude Code adds namespace-aware autocomplete in the future, subcommands could show up as completable names.

### Cons

- **Semantic collision with namespace convention.** Claude Code's colon means namespace:skill, not skill:subcommand. This is the wrong use of colons.
- **Requires restructuring to separate skills.** Each subcommand becomes its own skill file with its own SKILL.md. The orchestrator pattern (start = intake + ideate + capture) becomes cross-skill coordination.
- **Breaks shared state.** The single SKILL.md currently holds config loading, project root detection, and file naming conventions in one place. Splitting into 9 separate skills means duplicating or extracting this.
- **Migration cost is high.** 125+ references across 16 skill files, 44 references in the project repo, 1 external CLAUDE.md reference. All need updating.
- **Flag handling gets awkward.** `/do-work:go UR-003 --force` — the Skill tool would need to pass `UR-003 --force` as args to the `go` skill. This may or may not work depending on how namespace invocation handles args.
- **Novel pattern.** No other skills in `~/.claude/skills/` use this approach. Would be the first.

---

## Option 3: Support Both Formats

**Format:** `/do-work start` and `/do-work:start` both work

### Pros

- **No breaking change.** Existing users and references keep working.
- **Gradual migration path.** Could deprecate the old format over time if colon proves better.

### Cons

- **All the cons of Option 2, plus more.** You still need to register separate skills AND maintain the single-skill router.
- **Double the maintenance surface.** Every new subcommand needs to be added in two places.
- **Confusing for documentation.** Which format do you teach? Which shows up in examples?
- **The two formats have different semantics.** `/do-work start` = one skill with args. `/do-work:start` = separate skill in namespace. They'd use different Skill tool invocations internally.
- **Inconsistency breeds bugs.** When two paths do the same thing, they inevitably diverge over time.

---

## Migration Impact Assessment

If changing to colon format (Option 2 or 3):

| Location | References | Effort |
|----------|-----------|--------|
| `~/.claude/skills/do-work/SKILL.md` | 32 | Complete rewrite — split into 9 skill files |
| `~/.claude/skills/do-work/README.md` | 26 | Full rewrite |
| `~/.claude/skills/do-work/agents/*.md` | 48 | Update all cross-references |
| `~/.claude/skills/do-work/CHANGELOG.md` | 8 | Historical — leave as-is |
| `~/.claude/skills/do-work/CONTRIBUTING.md` | 6 | Update |
| Project SKILL.md + README + CHANGELOG | 44 | Update |
| `EA/CLAUDE.md` | 1 | Update |
| **Total** | **~165 references** | **Significant** |

---

## Recommendation

**Keep the current space-separated format (Option 1).**

Reasons:

1. **Colons mean the wrong thing.** Claude Code's colon is a namespace separator. Using it for subcommands fights the platform's design, not works with it.

2. **The problem is discoverability, not syntax.** The real friction isn't `/do-work start` vs `/do-work:start` — it's that bare `/do-work` doesn't suggest what's available. UR-011 (command suggestions) solves this directly without changing the format.

3. **Migration cost outweighs benefit.** 165+ references across 16+ files for a change that doesn't improve functionality.

4. **Supporting both is strictly worse.** It doubles maintenance and introduces semantic ambiguity without retiring the old format.

The space-separated format is working. The discoverability gap is a UX problem best solved at the UX layer (UR-011), not by restructuring the skill architecture.
