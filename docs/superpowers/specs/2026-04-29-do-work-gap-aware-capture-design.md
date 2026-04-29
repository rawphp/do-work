# do-work: Gap-Aware Intake & Capture

**Date:** 2026-04-29
**Status:** Design approved, awaiting implementation plan
**Scope:** Refactor `ideate.md`, `capture.md`, `verify.md`, plus shared layer detection. No new artifact types.

---

## Problem

Briefs that the user expects to be full-stack frequently produce REQs that are backend-only, or UI-only without integration wiring into the existing app. The failure mode is invisible because the user doesn't read REQ files closely. By the time the run loop has shipped half the feature, the gap is already cost.

Capture currently has no structural check that forces coverage of the layers a project actually has, and no enforcement that a new feature is *connected* to anything. Ideate surfaces gaps in the brief itself but exits without giving the user a moment to act on them.

## Non-goals

- New artifact types between UR and REQ. No "spec" or "plan" layer.
- Replacing the existing classification heuristic in `run.md`. We share it, not rewrite it.
- Detecting frameworks or stacks beyond what manifest files already declare.

## Design

### Pipeline shape (unchanged)

```
brief
  → intake (verbatim UR file)
  → ideate (gap analysis + interactive gate)
  → capture (classification + layer detection + REQ generation + layer-coverage prompt + integration question)
  → verify (three new checks)
  → run
```

No new commands. No new artifacts. The refactor is internal to the existing agents.

### Layer detection

A shared helper detects project layers at capture time by inspecting manifest files at the project root.

| Layer | Detected by |
|---|---|
| **frontend** | `package.json` with `vue`, `react`, `svelte`, `angular`, or `inertia` in `dependencies` or `devDependencies`; OR existence of `resources/views/`, `src/components/`, `app/components/` |
| **backend** | `composer.json`, `requirements.txt`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`, or any equivalent server-side manifest |
| **integration** | Always present. Treated as the connective tissue between layers regardless of stack. |

Detection runs once per capture invocation. Result is cached in working state for verify to read without re-detecting. If neither frontend nor backend manifest is found, capture proceeds with whatever it identified and records "single-stack project" — no layer-coverage prompts fire for layers that don't exist.

The detection helper lives in a new `agents/layers.md` (read-and-follow style, consistent with existing pattern) or inline in `capture.md` if simple enough. Implementation choice deferred to the plan.

### Brief classification

Before layer-coverage checks, capture classifies the brief using the same heuristic `run.md` already applies (commit `25ee3fb`).

| Class | Capture behavior |
|---|---|
| **bug-fix** | Skip layer expansion. Produce minimal REQ(s) targeting the broken layer only. |
| **feature** | Default. Full layer-coverage check applies. |
| **infra / refactor / docs / other** | Capture asks once: *"Treat this as bug-fix-style minimal capture, or feature-style full-stack capture?"* Records the answer. |

The classification result is recorded in the UR file's notes block so verify and run see the same call. Classification logic is a shared source — duplicated text or a `agents/classify.md` helper, decided in the plan.

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
- **(2)** appends `## Notes — Open Gaps` to the UR file (so the gaps aren't lost), then continues.
- **(3)** halts the flow.

This **replaces** the `--grill` flag on `start`. The flag is removed. Users decide *after seeing the gaps* whether to be grilled, which is more informed than deciding upfront.

### Capture's layer-coverage check

After capture writes its initial REQ list, it self-audits in a single pass.

The layer-coverage check applies to **frontend and backend only**. Integration is enforced separately by the integration question pass below — it has its own gate and its own REQ section, so it doesn't go through this matrix.

1. **Build coverage matrix.** For each detected stack layer (frontend, backend), check whether at least one REQ has acceptance criteria touching that layer.
   - "Touches frontend" = acceptance criteria reference UI components, pages, routes, or visible behavior.
   - "Touches backend" = acceptance criteria reference endpoints, jobs, models, services, or persistence.

2. **For each layer with zero coverage, prompt:**
   ```
   Project has {layer}, but no REQ covers it.
   Brief: <one-line summary>

   Is {layer} needed for this UR?
     (1) Yes — ask follow-ups, generate REQ(s)
     (2) No  — record decision, skip
     (3) Unsure — show me what I'd typically need here
   ```

3. **Yes path:** Capture asks targeted follow-ups (which screens, which existing route, which user action triggers this) and writes the missing REQ(s).

4. **No path:** Append a one-line note to the UR file's `## Notes` block: `Layer decision: no {layer} (recorded YYYY-MM-DD)`. The same `## Notes` block holds the classification result and any open gaps from ideate — it is the single source of truth for capture decisions about this UR. Verify reads this block and won't re-flag a recorded "no" decision.

5. **Bug-fix briefs skip this entire check.** Classification gates it.

### Capture's integration question (always asked for feature briefs)

The most-missed thing. A separate, non-skippable pass for every feature-class brief, even single-layer ones.

For each REQ that adds new UI surface or new backend surface, capture must produce an `## Integration` block answering three sub-questions. (REQs that are pure refactors, internal renames, or test-only changes are exempt — they add no new surface to integrate.)

1. **Reachability** — How does the user (or caller) actually reach this? Nav entry, menu item, route, parent component, API consumer, scheduled job trigger.
2. **Data dependencies** — What existing data, state, or models does this read or write?
3. **Service dependencies** — What existing services, APIs, or internal modules does this depend on or extend?

Capture answers these first by inspecting the codebase — reading routes files, nav components, existing service classes, existing models. Then:

| Confidence | Behavior |
|---|---|
| **High** — concrete file path or symbol reference for all three sub-questions | Write the `## Integration` block into the REQ as fact. |
| **Partial** — answers for some, gaps for others | Write what's known; surface the gaps as a single prompt offering concrete options. |
| **Low** — can't answer at least two of three from the codebase | Surface what was checked and ask the user directly. No silent defaults. |

**Confidence bar:** "high" requires a concrete file path or symbol for each sub-question (e.g. `routes/web.php:42`, `<MainNav>` component reference). Anything vaguer drops to partial.

The `## Integration` block is a required REQ section for feature-class REQs.

### Verify gets three new checks

Verify already scores REQ coverage 0–100% against the brief. Three additional pass/fail checks layer on top.

1. **Layer-coverage check.** Pull detected layers from cached state. For each *stack* layer (frontend, backend), confirm at least one REQ touches it OR the UR's `## Notes` block contains a `Layer decision: no {layer}` line. Anything else is a gap.

2. **Integration block check.** Every feature-class REQ that adds new UI or backend surface must have a non-empty `## Integration` block with all three sub-questions answered. Missing or empty → gap. (Pure refactor / rename / test-only REQs are exempt.)

3. **Acceptance-criteria-touches-layers check.** A REQ that claims to touch frontend must have at least one acceptance criterion phrased in frontend terms (UI element, route, visible behavior). Same for backend. Catches "frontend REQ" that's secretly just a backend task with a misleading title.

**`--auto-fix` extensions:**
- Missing layer → re-run capture's layer-coverage prompt for that layer.
- Missing Integration block → re-run capture's integration question scoped to that REQ.
- Missing layer-aligned acceptance criteria → flag for user, **do not auto-write**. Too easy to fabricate a meaningless criterion.

Bug-fix briefs get only check (3) applied, scoped to the single layer they target.

### REQ template change

A new required section is added to the REQ template for feature-class REQs:

```markdown
## Integration

**Reachability:** <how this is reached, with concrete file/symbol references>
**Data dependencies:** <existing data this reads/writes, with file references>
**Service dependencies:** <existing services this extends or depends on, with file references>
```

Bug-fix REQs may omit this section.

### SKILL.md changes

- Remove `--grill` from the `start` command's flag list.
- Document the new ideate gate (the three-option prompt).
- Document the Integration block as a required REQ section for feature-class REQs.
- Update the agent files list with `agents/layers.md` if added.

## Files affected

| File | Change |
|---|---|
| `agents/ideate.md` | End with interactive 3-option gate; remove `--grill` precondition logic |
| `agents/capture.md` | Add classification step, layer-detection call, layer-coverage prompt, integration question pass |
| `agents/verify.md` | Add three new checks; extend `--auto-fix` for layer and integration gaps |
| `agents/run.md` | Reuse classification heuristic (no behavior change, just shared source) |
| `agents/layers.md` (new, optional) | Layer detection helper if extracted |
| `agents/classify.md` (new, optional) | Brief classification helper if extracted |
| `agents/start.md` | Remove `--grill` handling |
| REQ template (wherever it lives) | Add required `## Integration` section |
| `SKILL.md` | Drop `--grill` flag, document new ideate gate, document Integration block requirement |
| `CHANGELOG.md` | Document the refactor |

## Open questions for the plan

- Whether to extract `agents/layers.md` and `agents/classify.md` as separate files or inline in capture. (Style question — matches existing helper pattern e.g. `agents/config.md`.)
- Where the REQ template currently lives and how it's referenced. May need a single source of truth if duplicated.
- Whether `--grill` removal is breaking enough to warrant a deprecation cycle (warn → remove) or a hard cut. Defaults to hard cut given low usage.

## Success criteria

- A full-stack feature brief produces REQs covering frontend, backend, and integration — with verify failing if any are missing.
- Every feature REQ contains an `## Integration` block with concrete file references.
- Ideate stops being a write-only step; the user always has a chance to act on surfaced gaps.
- Bug-fix briefs are not slowed down by full-stack prompts.
- No new commands, no new artifact types — refactor is invisible to anyone who only uses `start` and `go`.
