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

**At install time**, `do-work install` writes `layers: []` into the new config with a comment explaining declaration:

```yaml
# Declare your project's layers, e.g. [frontend, backend] for a web app,
# [commands, core, output] for a CLI, [agents, commands, templates] for do-work.
# Capture and verify use this list to gap-check briefs.
layers: []
```

Install does **not** auto-populate. Best-effort guesses introduce silent miscalls — explicit declaration forces the user to think about it once.

**Empty layers fails closed for feature briefs.** If `layers:` is empty or missing when capture runs on a feature-class brief, capture halts and reports:

```
Project has not declared layers in do-work/config.yml.
Declare them (e.g. `layers: [frontend, backend]`) and re-run,
or pass `--no-layers` to skip layer-coverage checks for this UR only.
```

`--no-layers` is a per-invocation escape hatch; it does not modify config, and it records `layers_in_scope: []` explicitly in the UR's frontmatter so the choice is auditable. Bug-fix briefs proceed without layers regardless — they don't run the layer-coverage check.

**Existing URs without YAML frontmatter are treated as legacy.** Verify skips all new checks for them; they continue to behave as before this spec lands. The new behaviour applies only to URs created (or re-captured) after the install writes the `layers:` config field.

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

**Prompt input convention** (applies to every interactive prompt in this spec): typing the option number (`1`, `2`, `3`) picks that option. An empty response — just hitting enter — picks the documented default. Anything else gets a one-line clarification and a re-prompt. There is no idle timeout in Claude Code; "default" is concretely "what empty input selects," nothing else.

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

Capture assigns this when generating the REQ. **A REQ has exactly one layer** — there is no `multi`. If a REQ feels like it spans multiple layers, that's a signal to split it; capture splits rather than concatenates. The two REQs share the same UR and may reference each other in their bodies. This keeps the layer-coverage check honest: a single `multi` REQ would credit every layer it lists and silently re-introduce the original failure mode (a feature that "covers" frontend on paper but never actually does).

If capture is unsure which layer a REQ belongs to, it asks the user at generation time rather than guessing.

REQs from the existing backlog with no `layer:` field are treated as legacy and exempt from new checks — no migration script.

### Capture's layer-coverage check

After capture writes its initial REQ list, it self-audits in a single pass.

1. **Build coverage matrix.** For each declared layer, check whether at least one REQ has `layer: <name>` in its frontmatter.

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

This pass only runs when there are declared layers to check against. The empty-`layers:` case is already handled upstream — feature briefs halt before reaching capture, bug-fix briefs skip layer logic by classification, and `--no-layers` invocations record `layers_in_scope: []` in UR state and bypass this pass.

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

**Confidence bar:** "high" requires a concrete file path or symbol reference for each sub-question (e.g. `routes/web.php:42`, `<MainNav>` component reference, `cmd/foo/main.go:14`). **Capture must verify each reference exists before accepting "high"** — file existence via Read, symbol existence via grep. Any unverifiable reference drops the rating to "partial." This catches the failure mode where the agent self-rates high confidence but the cited file or symbol doesn't actually exist; "high" must mean *checked*, not *felt confident*.

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
acknowledged_partials: []           # REQ ids whose partial confidence the user has reviewed and waved through
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

**Frontmatter is canonical for state.** The summary block is a regeneratable view: capture re-runs rebuild it from the frontmatter `reqs:` list and the REQ files. Edits made by hand to the summary block will be overwritten on the next capture run; meaningful edits should go into the frontmatter or the REQ files themselves.

### Verify gets two new checks

Verify already scores REQ coverage 0–100% against the brief. Three additional pass/fail checks layer on top.

1. **Layer-coverage check.** Read `layers_in_scope` from the UR's frontmatter — this is the per-UR record of which layers capture considered. (Not the global config; the UR's own snapshot, so `--no-layers` and bug-fix paths propagate correctly.) For each layer in `layers_in_scope`, confirm at least one REQ has `layer:` matching it — OR `layer_decisions[<layer>] == no` is set. Anything else is a gap. If `layers_in_scope` is empty, this check is a no-op.

2. **Integration block check.** Every feature-class REQ that adds new surface must have a non-empty `## Integration` block with all three sub-questions answered. Missing or empty → gap. (Pure refactor / rename / test-only REQs are exempt; bug-fix REQs are exempt.)

3. **Partial-confidence check.** A REQ recorded with `integration_confidence: partial` in UR state is treated as a gap unless its id appears in `acknowledged_partials:`. This stops partial-confidence REQs from silently slipping through to run, while still letting the user proceed when the gap has been reviewed.

   *Acknowledgement UX, v1:* the user edits UR frontmatter directly to add the REQ id to `acknowledged_partials`. This is a known papercut. *Intended next iteration:* when verify flags a partial-confidence REQ, it offers an inline prompt — `(1) Resolve — re-run integration question, (2) Acknowledge — wave through, (3) Skip — leave gap` — and option 2 writes the ack automatically. Tracked as a follow-up; not in scope for this spec, but called out so the manual edit isn't permanent.

**No vocabulary check.** The previous spec's check ("acceptance criteria phrased in frontend terms") is dropped. With `layer:` tagging, capture is the source of truth for which layer a REQ belongs to; verify doesn't second-guess by sniffing keywords.

**`--auto-fix` extensions:**
- Missing layer → re-run capture's layer-coverage prompt for that layer.
- Missing Integration block → re-run capture's integration question scoped to that REQ.
- Partial confidence → not auto-fixed. Auto-fix would just re-run the same exploration and likely produce the same partial result; the user must either resolve the gap or acknowledge it explicitly.

If the project has no declared layers (legacy UR or `--no-layers` invocation), check 1 is skipped. Checks 2 and 3 still run for feature briefs.

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
- Document the `--no-layers` flag on `start` (and on any other entry point that triggers capture).

### Idempotency: re-running capture on an existing UR

Capture is re-runnable. Re-running on a UR with existing frontmatter follows these rules:

- `classification` — preserved. Re-classification requires a separate command (out of scope for this spec).
- `layers_in_scope` — on each capture run, re-derived from current config and written to UR frontmatter. Verify reads the persisted snapshot, which reflects the *last* capture run, not necessarily current config. See "Config drift" below.
- `layer_decisions` — preserved. Past "no" decisions stay until the user explicitly clears them by editing frontmatter. Capture does not re-prompt for layers the user already opted out of.
- `open_gaps` — overwritten if ideate is re-invoked in the same run; otherwise preserved.
- `reqs:` list — merged. Entries matched by REQ id are preserved; new REQs from this run are appended; entries pointing at REQ files that no longer exist are dropped.
- `acknowledged_partials` — preserved. The user's acknowledgements survive re-runs.
- `## Capture summary` block in the UR body — replaced in place. Capture detects the existing heading and rewrites the block. Previous summaries remain visible in git history.
- The verbatim brief body — never modified. Read-only after intake.

A capture re-run that detects no changes (same config, same REQ files, same decisions) is a no-op except for refreshing the summary block timestamp.

### Config drift and late layer additions

Two behaviours worth naming explicitly so they don't surface as bug reports:

- **Config drift.** If the user runs capture, edits `layers:` in config, then runs verify without re-capturing, verify reads the old `layers_in_scope` snapshot from UR frontmatter and passes against it. This is correct — verify checks what capture decided — but it means edits to `layers:` are not retroactive. Re-run capture on the UR to apply.

- **Late layer additions.** Re-running capture on a UR months after `layers:` has grown will surface opt-out prompts for layers irrelevant to the original brief (e.g. a year-old UR re-captured after the project added a `mobile` layer). This is the correct behaviour — capture treats every declared layer as a real coverage question — but the user should expect to record `layer_decisions: { mobile: no }` for old URs that pre-date the new layer.

### Acknowledged tradeoffs

This design materially increases capture's cost. Capture now runs eleven sequential steps; the integration-question pass requires file Read and grep verification on every cited reference; verify with `--auto-fix` can re-trigger that exploration. A capture invocation under this design will use more tokens and clock-time than today's.

The exchange is gap-coverage guarantees: features that today silently ship half-complete will instead halt at capture or verify. The cost is paid where it's most visible (during planning) rather than where it hurts most (after a half-shipped feature ships).

If implementation finds capture's cost prohibitive in practice, the capture/wire split listed in open questions is the natural mitigation: extracting the integration-question + codebase-exploration block into a separate agent lets the user defer that pass until they explicitly ask for it.

## Files affected

| File | Change |
|---|---|
| `agents/ideate.md` | End with interactive 3-option gate; remove `--grill` precondition logic; write `open_gaps` to UR frontmatter on Continue |
| `agents/capture.md` | Add classification step, read declared layers from config, assign `layer:` to each REQ, layer-coverage prompt, integration question pass, write capture summary block, populate UR frontmatter |
| `agents/verify.md` | Replace check vocabulary with frontmatter reads; add layer-coverage check + integration-block check; drop the keyword-sniffing check; extend `--auto-fix` |
| `agents/run.md` | Reuse classification heuristic (no behavior change, just shared source) |
| `agents/install` step (in `SKILL.md`) | Write `layers: []` (empty placeholder + explanatory comment) into new config; do not auto-populate |
| `agents/start.md` | Remove `--grill` handling; accept new `--no-layers` flag and pass it through to capture |
| `agents/go.md` | Accept `--no-layers` flag if `go` is the entry point that triggered capture re-run |
| REQ template (wherever it lives) | Add required `layer:` frontmatter field; add required `## Integration` section for new-surface feature REQs |
| UR template / `intake.md` | Switch to YAML frontmatter on `input.md`; preserve the verbatim brief in the body |
| `do-work/config.yml` template | Add `layers:` field with comment explaining declaration |
| `SKILL.md` | Drop `--grill` flag, document new ideate gate, document `layers:` config, document `layer:` REQ field, document Integration section requirement |
| `CHANGELOG.md` | Document the refactor |

## Open questions for the plan

- Whether to extract `agents/layers.md` and `agents/classify.md` as separate files or inline in capture. (Style question — matches existing helper pattern e.g. `agents/config.md`.)
- Where the REQ template currently lives and how it's referenced. May need a single source of truth if duplicated.
- Whether `--grill` removal warrants a deprecation cycle. Defaults to hard cut given low usage.
- Auto-fix loop bail-out: if `--auto-fix` re-runs the layer prompt or integration question and the result is still a gap, how many attempts before halting? Defer to plan; reasonable default is one auto-fix attempt per gap, then surface to user.
- Mid-run REQ creation: when run discovers an additional REQ is needed, how does it get a `layer:` assigned without falling back into capture? Defer to plan.
- Capture/wire split: capture now does eleven sequential steps. If implementation finds it unwieldy, the integration-question + codebase-exploration block is the natural seam to extract into its own helper agent. Decided in plan, not here.

## Success criteria

- A full-stack feature brief produces REQs covering each declared layer (or records an explicit "no" decision) — with verify failing if any are missing.
- Every feature REQ that adds new surface contains an `## Integration` block with concrete file references.
- Ideate stops being a write-only step; the user always has a chance to act on surfaced gaps.
- Bug-fix briefs are not slowed down by full-stack prompts.
- Verify never misfires on stacks it doesn't understand — because it doesn't understand any stack. It reads `layer:` tags and `layers:` config, both of which are project-declared.
- **do-work dogfoods on itself.** The implementation plan declares do-work's own layers in its own `do-work/config.yml` and runs the new flow against a synthetic UR for do-work. If the design can't gap-check its own work, it ships broken.
- No new commands, no new artifact types — the refactor is invisible to anyone who only uses `start` and `go`.
