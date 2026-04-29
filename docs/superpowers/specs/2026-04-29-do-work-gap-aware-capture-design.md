# do-work: Gap-Aware Intake & Capture

**Date:** 2026-04-29
**Status:** Design approved, awaiting implementation plan
**Scope:** Refactor `ideate.md`, `capture.md`, `verify.md`, the REQ template, and UR state storage. Introduce project-declared layers. No new artifact types between UR and REQ.

---

## Problem

Briefs the user expects to be full-stack frequently produce REQs that are backend-only, or UI-only without integration wiring into the existing app. The failure mode is invisible because the user doesn't read REQ files closely. By the time the run loop has shipped half the feature, the gap is already cost.

Capture currently has no structural check that forces coverage of the layers a project actually has, and no enforcement that a new feature is *connected* to anything. Ideate surfaces gaps in the brief itself but exits without giving the user a moment to act on them.

A first version of this spec tried to solve the layer problem with manifest-based detection (`package.json`, `composer.json`, etc.). That was theatre. The detection produced one of two web-shaped buckets — frontend or backend — and silently failed for CLIs, libraries, mobile apps, IaC, ML pipelines, and the do-work tool itself (which has no recognised manifest and would fall through every detection path). The verify checks also baked in web vocabulary like "UI element" and "endpoint." This revision drops the detection model entirely.

## Non-goals

- New artifact types between UR and REQ. No "spec" or "plan" layer.
- Replacing the existing classification heuristic in `run.md`. We share it, not rewrite it.
- Auto-detecting stack layers at runtime. The project declares its layers once, in config.

## Design

### Pipeline shape (unchanged)

```
brief
  → intake (verbatim UR file)
  → ideate (gap analysis + interactive gate)
  → capture (classification + layer assignment + REQ generation + layer-coverage prompt + integration question)
  → verify (two new checks)
  → run
```

No new commands. No new artifacts. The refactor is internal to the existing agents, the REQ template, and the UR state representation.

### Project-declared layers

The project declares its layers once in `do-work/config.yml`:

```yaml
layers: [frontend, backend]   # web app
# layers: [commands, core, output]            # CLI tool
# layers: [public_api, internal]              # library / SDK
# layers: [agents, commands, templates]       # do-work itself
```

`integration` is **not** in this list. It is universal — every project has connective tissue between layers regardless of stack — and is enforced by a separate REQ section, not by per-layer coverage.

**At install time**, `do-work install` writes a default `layers:` list into the new config. The default is best-effort (e.g. presence of `package.json` with `vue`/`react` in deps + a `composer.json` or `requirements.txt` → `[frontend, backend]`; presence of a `bin/` or `cmd/` and no UI framework → suggest `[commands, core, output]`; nothing detected → leave blank with a comment instructing the user to declare). The user owns the file from that point on. Detection never runs again.

If `layers:` is empty or missing, capture proceeds without layer-coverage checks and notes the absence in the UR state. Verify treats empty layers as opt-out, not as failure.

### Brief classification

Before any layer logic, capture classifies the brief using the same heuristic `run.md` already applies (commit `25ee3fb`). The result is recorded in UR state.

| Class | Capture behavior |
|---|---|
| **bug-fix** | Skip layer-coverage check. Produce minimal REQ(s) targeting the affected layer only. Integration block exempt. |
| **feature** | Default. Full layer-coverage check applies. Integration block required for REQs adding new surface. |
| **infra / refactor / docs / other** | Capture asks once: *"Treat this as bug-fix-style minimal capture, or feature-style full-stack capture?"* Records the answer. |

Classification logic is shared between `capture.md` and `run.md` — extracted to a helper or duplicated, decided in the plan.

### Ideate becomes an interactive gate

Today: ideate is autonomous and exits.
New: at the end of ideate's report, it prompts:

```
Ideate found N gaps:
  - <gap 1>
  - <gap 2>
  - ...

How would you like to proceed?
  (1) Grill me — interactive Q&A on these gaps before capture
  (2) Continue — proceed to capture as-is, gaps recorded
  (3) Stop — let me revise input.md, then re-run

Default: continue.
```

- **(1)** invokes `question.md` scoped to the listed gaps, then auto-continues to capture.
- **(2)** writes the gaps into UR state (`open_gaps:` list), then continues.
- **(3)** halts the flow.

This **replaces** the `--grill` flag on `start`. The flag is removed. Users decide *after seeing the gaps* whether to be grilled, which is more informed than deciding upfront.

### REQ frontmatter gains a `layer:` field

Every REQ produced by capture is tagged with one of the declared layers in its frontmatter:

```yaml
---
slug: customer-search
title: Customer search box
layer: frontend
---
```

Capture assigns this when generating the REQ. If a REQ genuinely spans more than one layer (rare — usually a sign it should be split), `layer: multi` is allowed and the REQ must enumerate them in the body. If capture is unsure which layer a REQ belongs to, it asks the user at generation time.

REQs from the existing backlog with no `layer:` field are treated as legacy and exempt from new checks — no migration script.

### Capture's layer-coverage check

After capture writes its initial REQ list, it self-audits in a single pass.

1. **Build coverage matrix.** For each declared layer, check whether at least one REQ has `layer: <name>` (or `layer: multi` listing it).

2. **For each layer with zero coverage, prompt:**
   ```
   Project declares layer "{layer}", but no REQ covers it.
   Brief: <one-line summary>

   Is "{layer}" needed for this UR?
     (1) Yes — ask follow-ups, generate REQ(s)
     (2) No  — record decision, skip
     (3) Unsure — show me what I'd typically need here
   ```

3. **Yes path:** Capture asks targeted follow-ups and writes the missing REQ(s), tagging them with the right `layer:`.

4. **No path:** Record the decision in UR state under `layer_decisions: { <layer>: no }`. Verify reads this and won't re-flag.

5. **Bug-fix briefs skip this entire check.** Classification gates it.

If the project has no declared layers (`layers: []` or missing), this entire pass is skipped.

### Capture's integration question (always asked for feature briefs)

The most-missed thing. A separate, non-skippable pass for every feature-class brief, in any stack.

**"Adds new surface"** means the REQ creates something callable or visible from outside its own code — a new page, route, component, command, public function, endpoint, scheduled job, library export. Modifying an existing surface (renaming a button, tightening validation, fixing a return type) does not count as adding new surface; those REQs are exempt.

For each REQ that adds new surface, capture must produce an `## Integration` block answering three sub-questions:

1. **Reachability** — How does the user (or caller) actually reach this? Nav entry, menu item, route, parent component, command name, API consumer, scheduled job trigger, library entry point.
2. **Data dependencies** — What existing data, state, or models does this read or write?
3. **Service dependencies** — What existing services, modules, or internal APIs does this depend on or extend?

These three are deliberately stack-agnostic. They apply to a Vue page, a CLI command, a Rust function, a Terraform module, or a smart contract.

Capture answers these first by inspecting the codebase (reading routes files, nav components, existing service classes, command registries, library exports). Then:

| Confidence | Behavior |
|---|---|
| **High** — concrete file path or symbol reference for all three sub-questions | Write the `## Integration` block into the REQ as fact. |
| **Partial** — answers for some, gaps for others | Write what's known; surface the gaps as a single prompt offering concrete options. |
| **Low** — can't answer at least two of three from the codebase | Surface what was checked and ask the user directly. No silent defaults. |

**Confidence bar:** "high" requires a concrete file path or symbol for each sub-question (e.g. `routes/web.php:42`, `<MainNav>` component reference, `cmd/foo/main.go:14`). Anything vaguer drops to partial.

The `## Integration` block is required for feature-class REQs that add new surface. Pure refactor / rename / test-only REQs are exempt — they add nothing to integrate.

### UR state moves to YAML frontmatter

Today the UR file is `input.md` with whatever notes accumulate as Markdown prose. Verify can't read structured decisions out of prose without regex hacks.

New: the UR has YAML frontmatter holding all capture decisions. The brief itself stays as Markdown body, verbatim.

```yaml
---
ur: UR-007
created: 2026-04-29
classification: feature
layers_in_scope: [frontend, backend]
layer_decisions:                  # only present when user opts a layer out
  backend: no                     # example: a frontend-only UR
open_gaps:
  - "How should X behave under Y?"
  - "What's the timeout for Z?"
reqs:
  - { id: REQ-100, layer: frontend, integration_confidence: high }
  - { id: REQ-101, layer: backend,  integration_confidence: partial }
---

# Original brief

<verbatim user text>
```

Verify reads structured fields. Capture writes structured fields. The `## Notes` block referenced in the previous spec is gone — its contents now live in frontmatter.

### Visibility summary at the top of the UR body

After capture runs, capture prepends a one-shot summary block to the UR body (above the brief, below the frontmatter) so the user sees what was decided at a glance without reading every REQ:

```markdown
## Capture summary (2026-04-29)

| Item | Value |
|---|---|
| Classification | feature |
| Layers in scope | frontend, backend |
| Layer decisions | (none — all covered) |
| REQs generated | 2 |

| REQ | Layer | Integration confidence |
|---|---|---|
| REQ-100 | frontend | high |
| REQ-101 | backend  | partial — service dependency unknown, asked user |
```

This is the visibility surface. The user reviews this, not the REQs themselves, to know whether capture got it right.

### Verify gets two new checks

Verify already scores REQ coverage 0–100% against the brief. Two additional pass/fail checks layer on top.

1. **Layer-coverage check.** Pull declared layers from project config. For each declared layer, confirm at least one REQ in the UR has `layer:` matching it (or `layer: multi` listing it) — OR `layer_decisions[<layer>] == no` is set in UR state. Anything else is a gap.

2. **Integration block check.** Every feature-class REQ that adds new surface must have a non-empty `## Integration` block with all three sub-questions answered. Missing or empty → gap. (Pure refactor / rename / test-only REQs are exempt; bug-fix REQs are exempt.)

**No vocabulary check.** The previous spec's check #3 ("acceptance criteria phrased in frontend terms") is dropped. With `layer:` tagging, capture is the source of truth for which layer a REQ belongs to; verify doesn't second-guess by sniffing keywords.

**`--auto-fix` extensions:**
- Missing layer → re-run capture's layer-coverage prompt for that layer.
- Missing Integration block → re-run capture's integration question scoped to that REQ.

If the project has no declared layers, check 1 is skipped. Check 2 still runs.

### REQ template change

REQ frontmatter gains a required `layer:` field. The body adds a required `## Integration` section for feature-class REQs that add new surface:

```markdown
---
slug: customer-search
title: Customer search box
layer: frontend
---

# Customer search box

## Acceptance criteria
- ...

## Integration

**Reachability:** <how this is reached, with concrete file/symbol references>
**Data dependencies:** <existing data this reads/writes, with file references>
**Service dependencies:** <existing services this extends or depends on, with file references>
```

Bug-fix and pure-refactor REQs may omit the Integration section.

### SKILL.md changes

- Remove `--grill` from the `start` command's flag list.
- Document the new ideate gate (the three-option prompt).
- Document the `layers:` config field and how to declare it per project.
- Document the `layer:` field as required REQ frontmatter.
- Document the Integration block as a required REQ section for feature-class REQs that add new surface.

## Files affected

| File | Change |
|---|---|
| `agents/ideate.md` | End with interactive 3-option gate; remove `--grill` precondition logic; write `open_gaps` to UR frontmatter on Continue |
| `agents/capture.md` | Add classification step, read declared layers from config, assign `layer:` to each REQ, layer-coverage prompt, integration question pass, write capture summary block, populate UR frontmatter |
| `agents/verify.md` | Replace check vocabulary with frontmatter reads; add layer-coverage check + integration-block check; drop the keyword-sniffing check; extend `--auto-fix` |
| `agents/run.md` | Reuse classification heuristic (no behavior change, just shared source) |
| `agents/install` step (in `SKILL.md`) | Write default `layers:` into new config based on best-effort detection at install time only |
| `agents/start.md` | Remove `--grill` handling |
| REQ template (wherever it lives) | Add required `layer:` frontmatter field; add required `## Integration` section for new-surface feature REQs |
| UR template / `intake.md` | Switch to YAML frontmatter on `input.md`; preserve the verbatim brief in the body |
| `do-work/config.yml` template | Add `layers:` field with comment explaining declaration |
| `SKILL.md` | Drop `--grill` flag, document new ideate gate, document `layers:` config, document `layer:` REQ field, document Integration section requirement |
| `CHANGELOG.md` | Document the refactor |

## Open questions for the plan

- Whether to extract `agents/layers.md` and `agents/classify.md` as separate files or inline in capture. (Style question — matches existing helper pattern e.g. `agents/config.md`.)
- Where the REQ template currently lives and how it's referenced. May need a single source of truth if duplicated.
- Whether `--grill` removal warrants a deprecation cycle. Defaults to hard cut given low usage.
- Whether the install-time layer guess should attempt to populate at all, or always leave empty with a comment. (Safer to leave empty and force a deliberate user decision.)

## Success criteria

- A full-stack feature brief produces REQs covering each declared layer (or records an explicit "no" decision) — with verify failing if any are missing.
- Every feature REQ that adds new surface contains an `## Integration` block with concrete file references.
- Ideate stops being a write-only step; the user always has a chance to act on surfaced gaps.
- Bug-fix briefs are not slowed down by full-stack prompts.
- Verify never misfires on stacks it doesn't understand — because it doesn't understand any stack. It reads `layer:` tags and `layers:` config, both of which are project-declared.
- **do-work dogfoods on itself.** The implementation plan declares do-work's own layers in its own `do-work/config.yml` and runs the new flow against a synthetic UR for do-work. If the design can't gap-check its own work, it ships broken.
- No new commands, no new artifact types — the refactor is invisible to anyone who only uses `start` and `go`.
