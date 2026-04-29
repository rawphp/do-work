# do-work Gap-Aware Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor do-work's capture pipeline so feature briefs always produce REQs covering the project's declared layers, with explicit Integration blocks wiring new surfaces to the existing app — and verify catches gaps before run.

**Architecture:** No new artifact types. The pipeline (intake → ideate → capture → verify → run) keeps its shape. Project-declared layers replace ad-hoc frontend/backend assumptions. UR state moves from prose `## Notes` to YAML frontmatter so verify reads structured data. REQs gain a `layer:` field and a required `## Integration` section. Capture self-audits layer coverage and integration wiring; verify enforces both.

**Tech Stack:** Markdown agent files (no code), YAML frontmatter, shell verification commands. The do-work system itself is the runtime — there is no test framework for agent files in this codebase, so verification is structural (file content checks, agent-output assertions on synthetic URs).

**Spec:** `docs/superpowers/specs/2026-04-29-do-work-gap-aware-capture-design.md`

---

## Pre-flight: deliberate divergence from spec

The spec says capture's brief classification "uses the same heuristic `run.md` already applies (commit `25ee3fb`)." That commit introduced a heuristic for picking `subagent_type` (which specialist worker to dispatch) — a different question from "is this brief a bug-fix or a feature?" The plan introduces a **new** classification heuristic for capture; the two heuristics live alongside each other, neither shared.

The "open question" in the spec about whether to extract `agents/classify.md` is therefore decided here: **inline in capture.md** for v1. Extraction can come later if a third caller appears.

The spec's other open questions:
- `agents/layers.md` extraction — **inline in capture.md for v1**, same reasoning.
- REQ template location — confirmed inline in `capture.md` Step 4 (no separate template file exists today). Updates happen there.
- `--grill` removal cycle — **hard cut** as the spec defaults.

---

## File structure

Files modified:
- `agents/config.md` — schema gains `layers:`, `next_steps_acknowledged_partials:` is NOT added (deferred follow-up).
- `agents/intake.md` — switches `input.md` from prose to YAML frontmatter + body.
- `agents/ideate.md` — appends interactive 3-option gate at end.
- `agents/capture.md` — large refactor: classification, layer reading, layer-coverage prompt, integration question pass, frontmatter writer, summary block writer, idempotency rules.
- `agents/verify.md` — reads UR frontmatter; adds three new checks; extends auto-fix.
- `agents/start.md` — drops `--grill`, accepts `--no-layers`.
- `agents/go.md` — accepts `--no-layers` and threads it to capture re-runs.
- `SKILL.md` — flag list + doc updates.
- `CHANGELOG.md` — entry.
- `do-work/config.yml` (in dogfood project root) — declares do-work's own layers.

Files created: none. (Helpers stay inline.)

---

## Task 1: Add `layers:` to config schema

**Files:**
- Modify: `agents/config.md`

- [ ] **Step 1: Define expected end-state**

After this task, the default config template in `config.md` includes a `layers:` field with empty list and a comment block explaining declaration. Schema reference table includes a row for it.

- [ ] **Step 2: Edit `agents/config.md` to add `layers: []` to the default template**

Find the YAML block under "## Load Config" (lines 15-39 today). Add this block immediately above `log:`:

```yaml
# Declare your project's layers, e.g. [frontend, backend] for a web app,
# [commands, core, output] for a CLI, [agents, commands, templates] for do-work.
# Capture and verify use this list to gap-check briefs. Leave empty to
# opt out of layer-coverage checks (capture will halt feature briefs
# until either a layer list is declared or --no-layers is passed).
layers: []
```

- [ ] **Step 3: Add a row to the Config Schema Reference table**

Find the table starting at line 57. Add this row immediately after `project.name`:

```markdown
| `layers` | list of strings | `[]` | Project's declared layers for gap-aware capture. Capture and verify check that REQs cover each declared layer. Empty = opt out (feature briefs will halt until declared or `--no-layers` is passed). |
```

- [ ] **Step 4: Verify the changes**

```bash
grep -A 5 "layers:" agents/config.md | head -15
grep "| \`layers\`" agents/config.md
```

Expected: the YAML block prints with the comment, and the schema row prints.

- [ ] **Step 5: Commit**

```bash
git add agents/config.md
git commit -m "feat(do-work): add layers field to config schema"
```

---

## Task 2: Switch intake.md to write YAML frontmatter

**Files:**
- Modify: `agents/intake.md`

- [ ] **Step 1: Define expected end-state**

After this task, `intake.md` writes `input.md` with YAML frontmatter (`ur`, `received`, `status`) followed by the user's verbatim brief in the body. Step 4 (Write input.md) and Step 4b (Verify the recording) are updated.

- [ ] **Step 2: Replace the input.md template in Step 4 of intake.md**

Find the existing template block in `agents/intake.md` (lines 64-73). Replace it with:

```markdown
Use this format exactly:

```markdown
---
ur: UR-NNN
received: YYYY-MM-DD
status: intake
---

# UR-NNN: User Request

## Request

[The user's message, verbatim. Do not summarise, rephrase, or interpret it.]
```
```

(Note: nested code fence — the agent file uses indented or escaped fences, follow whatever existing convention is in `intake.md`. Read it first.)

- [ ] **Step 3: Update Step 4b (Verify the recording) to check frontmatter**

Replace the verification numbered list (lines 79-83) with:

```markdown
1. Read back `{project}/do-work/user-requests/UR-NNN/input.md`
2. Confirm the file begins with `---` and parses as a YAML frontmatter block
3. Confirm `status: intake` appears in the frontmatter
4. Confirm `received:` matches today's date
5. Confirm `ur:` matches the UR number you assigned
6. Confirm the `## Request` section in the body contains the user's original message (not a summary or paraphrase)
```

- [ ] **Step 4: Update intake's existing-UR-status check**

Find the line `If **Status: intake** (Capture has not been run yet):` (around line 26). Update the surrounding block to read frontmatter instead of a `**Status:**` field. Replace with:

```markdown
- If **status: intake** (in YAML frontmatter — Capture has not been run yet):
```

- [ ] **Step 5: Verify the changes**

```bash
grep -n "status: intake" agents/intake.md
grep -n "YAML frontmatter" agents/intake.md
```

Expected: at least 2 matches for `status: intake`, at least 1 match for `YAML frontmatter`.

- [ ] **Step 6: Commit**

```bash
git add agents/intake.md
git commit -m "feat(do-work): intake writes UR with YAML frontmatter"
```

---

## Task 3: Add legacy-UR detection helper text to verify.md

**Files:**
- Modify: `agents/verify.md`

This task pre-positions verify to recognise legacy URs (no frontmatter) so subsequent verify-check tasks can short-circuit cleanly.

- [ ] **Step 1: Define expected end-state**

verify.md's Step 1 (Read the brief) gains an inline check: "if `input.md` lacks YAML frontmatter, mark this UR as legacy and skip all checks introduced by the gap-aware refactor (Task 18 onwards)."

- [ ] **Step 2: Edit verify.md Step 1**

Find Step 1 in `agents/verify.md` (lines 24-28 today). After "Read every file in `UR-NNN/assets/` if present.", append:

```markdown
**Legacy UR detection.** Read the first 10 lines of `input.md`. If they do not begin with a `---` line followed by a YAML frontmatter block ending in `---`, this UR predates the gap-aware capture refactor. Mark it as legacy. Verify will:
- Run all pre-existing checks (coverage scoring, ideate observation tracking, vague-criteria scan).
- **Skip** the new layer-coverage check, integration-block check, and partial-confidence check (Steps 4b-4d below). Legacy URs continue to behave exactly as they did before this refactor.

For non-legacy URs, also read and parse the YAML frontmatter — keep `classification`, `layers_in_scope`, `layer_decisions`, `reqs`, and `acknowledged_partials` in context for later steps.
```

- [ ] **Step 3: Verify**

```bash
grep -n "Legacy UR detection" agents/verify.md
grep -n "frontmatter" agents/verify.md
```

Expected: at least 1 match for each.

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify recognises legacy URs without frontmatter"
```

---

## Task 4: Add `layer:` field to REQ template in capture.md

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

The REQ template in capture.md Step 4 (lines 142-173 today) gains a `**Layer:**` field. The field accepts one of the project's declared layer names. Bug-fix REQs and pure-refactor/test-only REQs get `**Layer:** none`.

- [ ] **Step 2: Edit the REQ template**

Find the template block under "Use this format exactly:" in capture.md Step 4. Update it to include the `**Layer:**` field. Replace the header block:

```markdown
# REQ-NNN: Short Title

**UR:** UR-NNN
**Status:** backlog
**Created:** YYYY-MM-DD
**Layer:** <one of the project's declared layers, or `none` for bug-fix / pure refactor / test-only>
```

- [ ] **Step 3: Add a paragraph explaining the field**

Immediately after the template block (before "### Writing effective Verification Steps"), insert:

```markdown
**The `**Layer:**` field is required.** Its value must be one of:
- A layer name from `do-work/config.yml`'s `layers:` list, OR
- The literal `none` for bug-fix REQs, pure refactor REQs (no new surface), or test-only REQs.

A REQ has exactly one layer. If a REQ feels like it spans multiple layers, that is a signal to split it into two REQs — capture must split rather than concatenate. The two REQs share the same UR and may reference each other in their bodies.

Capture decides the layer when it writes each REQ. If capture is unsure which layer a REQ belongs to, it asks the user at generation time rather than guessing.
```

- [ ] **Step 4: Verify**

```bash
grep -n "Layer:" agents/capture.md
grep -n "exactly one layer" agents/capture.md
```

Expected: header field appears in template; "exactly one layer" rule appears.

- [ ] **Step 5: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): add Layer field to REQ template"
```

---

## Task 5: Add `## Integration` section to REQ template

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

The REQ template gains a required `## Integration` section for REQs whose `**Layer:**` is not `none`. Bug-fix and pure-refactor REQs may omit it.

- [ ] **Step 2: Edit the REQ template body**

Find the template block in capture.md Step 4. After the `## Verification Steps` section block and before `## Assets`, insert:

```markdown
## Integration

> Required for REQs that add new surface (any layer except `none`). Omit for bug-fix REQs and pure-refactor / test-only REQs.

**Reachability:** [How does the user (or caller) actually reach this? Nav entry, menu item, route, parent component, command name, API consumer, scheduled job trigger, library entry point. Cite a concrete file path or symbol.]

**Data dependencies:** [What existing data, state, or models does this read or write? Cite a file path or symbol.]

**Service dependencies:** [What existing services, modules, or internal APIs does this depend on or extend? Cite a file path or symbol.]
```

- [ ] **Step 3: Add an "Integration block rules" subsection**

After the template, before the Verification Steps subsection, insert:

```markdown
### Integration block rules

The Integration block is the load-bearing check that catches "feature built but never wired in" failures. Three rules:

1. **Required for new-surface REQs.** Any REQ whose `**Layer:**` is not `none` must have a non-empty Integration block answering all three sub-questions. "New surface" means the REQ creates something callable or visible from outside its own code — a new page, route, component, command, public function, endpoint, scheduled job, library export.

2. **Modifications don't count.** Renaming a button, tightening validation, fixing a return type — these don't add new surface. Such REQs should set `**Layer:** none` and may omit the Integration block.

3. **References must be checkable.** Each cited file path or symbol must actually exist in the codebase. Capture verifies this before declaring "high confidence" (see Step 6 below).
```

- [ ] **Step 4: Verify**

```bash
grep -n "## Integration" agents/capture.md
grep -n "Integration block rules" agents/capture.md
```

Expected: matches present.

- [ ] **Step 5: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): add Integration section to REQ template"
```

---

## Task 6: Add brief classification heuristic to capture.md

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 2b in capture.md classifies the brief as `bug-fix`, `feature`, or `other`. The result drives which downstream passes run. Classification is recorded in UR frontmatter (Task 13).

- [ ] **Step 2: Insert Step 2b after current Step 2**

Find Step 2 ("Determine the next REQ number") in `agents/capture.md`. Immediately after Step 2 ends, insert:

```markdown
### 2b. Classify the brief

Classify the brief into one of three classes. Read `input.md`'s body and apply these signals top-to-bottom; first match wins:

| Signal in brief | Class |
|---|---|
| Words "bug", "fix", "broken", "regression", "crash", "error in", "doesn't work", "stops working", combined with a reference to existing behaviour | `bug-fix` |
| Words "refactor", "rename", "tidy", "cleanup", "extract", "move to", with no new user-facing behaviour described | `other` (refactor) |
| Words "document", "docs", "readme", "changelog", with no code change described | `other` (docs) |
| Words "config", "setting", "env var", "tweak X to Y", with no new code paths | `other` (config) |
| Anything else, including any brief describing user-facing behaviour, screens, endpoints, commands, or new functionality | `feature` |

Record the chosen class. Capture's downstream behaviour:

- **`bug-fix`** — Skip the layer-coverage prompt (Step 4c). Skip the integration question pass (Step 6). Each REQ for this brief should set `**Layer:** none` unless the bug spans a declared layer in a non-trivial way.
- **`feature`** — Run the layer-coverage prompt (Step 4c) and integration question pass (Step 6). Default class for anything user-facing.
- **`other`** — Ask the user once: "Treat this as bug-fix-style minimal capture, or feature-style full-stack capture?" via `AskUserQuestion`. Record the user's answer as the effective class.

Hold the class in context — it gates Step 4c and Step 6, and gets written to UR frontmatter in Step 7.

**Disambiguation rule.** If a brief mentions BOTH bug-fix language AND new feature language ("fix X and add Y"), classify as `feature` and treat the bug part as one of the REQs. The layer-coverage and integration checks are net-positive even when overlaid on a bug fix.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 2b. Classify the brief" agents/capture.md
grep -n "Classify the brief" agents/capture.md
```

Expected: section heading and prose present.

- [ ] **Step 4: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): add brief classification heuristic to capture"
```

---

## Task 7: Capture reads declared layers from config; fail-closed on empty

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 2c reads `layers:` from config (already loaded in Step 0). For `feature`-class briefs with empty layers and no `--no-layers` flag, capture halts with a clear error. Bug-fix briefs proceed regardless.

- [ ] **Step 2: Insert Step 2c after the new Step 2b**

Immediately after Step 2b (Classify the brief), insert:

```markdown
### 2c. Read declared layers and check fail-closed condition

Pull `layers:` from the config loaded in Step 0. Also note whether the invocation was passed `--no-layers` (the start.md or go.md orchestrator passes this through).

Decision table:

| Class | `layers:` | `--no-layers` flag | Action |
|---|---|---|---|
| `bug-fix` | any | any | Proceed. `layers_in_scope: []` will be recorded in UR frontmatter; no layer-coverage prompt fires. |
| `feature` | non-empty | not passed | Proceed. `layers_in_scope` = the configured `layers:` list. |
| `feature` | non-empty | passed | Proceed. `layers_in_scope: []` recorded in UR frontmatter (deliberate user opt-out for this UR only); no layer-coverage prompt fires. |
| `feature` | empty or missing | not passed | **Halt.** Output the error below. Do not write any REQs. |
| `feature` | empty or missing | passed | Proceed. `layers_in_scope: []` recorded in UR frontmatter. |
| `other` (effective `feature`) | empty or missing | not passed | **Halt** as above. |

**Halt error message:**

```
Capture halted: project has not declared layers in do-work/config.yml.

This is a feature-class brief, and gap-aware capture requires either:
  (1) declare your project's layers in do-work/config.yml, e.g.
      layers: [frontend, backend]
      and re-run capture, OR
  (2) pass --no-layers on the start or go invocation to skip
      layer-coverage checks for this UR only.

Layer-coverage checks prevent features from silently shipping with
the frontend or wiring missed. Disable them per-UR with --no-layers
when they don't apply (e.g. internal CLI scripts).
```

Hold `layers_in_scope` (the per-UR list) in context for downstream steps.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 2c. Read declared layers" agents/capture.md
grep -n "Capture halted" agents/capture.md
```

Expected: both present.

- [ ] **Step 4: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture reads layers from config, fails closed when undeclared"
```

---

## Task 8: Capture assigns `layer:` when writing REQs

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

Step 4 (Write REQ files) is updated to require `**Layer:**` on every REQ. The decomposition in Step 3 / 3b is amended so each candidate REQ carries a layer assignment.

- [ ] **Step 2: Update Step 3b's R-mapping to use declared layers**

Find Step 3b ("Verify full coverage before writing") in capture.md. Replace the `[backend]`/`[frontend]`/`[both]`/`[none]` tagging system with the project's declared layers. Find the section that reads:

```markdown
1. List every distinct requirement from the brief (a requirement is a user-visible behavior, data flow, or constraint). Number them R1, R2, R3, etc. **Tag each R-number with exactly one layer:**
   - `backend` — server-side logic, data, APIs, jobs, config, internal tooling with no UI surface
   - `frontend` — UI, pages, forms, client-side state, styling (per the definition above)
   - `both` — a single requirement that inherently spans both layers (e.g. form validation that runs client-side and server-side)
   - `none` — meta or process requirements that produce no code (e.g. "document the decision")
```

Replace the tag list with:

```markdown
1. List every distinct requirement from the brief (a requirement is a user-visible behavior, data flow, or constraint). Number them R1, R2, R3, etc. **Tag each R-number with exactly one value from this list:**
   - One of the project's declared layers (read from `layers_in_scope` in context — e.g. `frontend`, `backend`, `commands`, `core`, `output`).
   - `none` — meta or process requirements that produce no code (e.g. "document the decision"), OR pure refactor/test-only changes with no new surface.

   If a requirement seems to need two layers (e.g. form validation that inherently runs client-side and server-side), split it into two R-numbers (`R2a` client validation, `R2b` server validation), each tagged with one layer. The "both" tag is gone.
```

- [ ] **Step 3: Update the example in Step 3b**

Find the `## Example` block immediately after the rules. Replace with:

```markdown
**Example** (project with `layers: [frontend, backend]`):

```
Brief: "Contact form with name, email, message. Submissions emailed to sales@example.com and stored in DB. Show success message."

R1:  Form UI (name, email, message fields)              [frontend]
R2a: Form validation — client side                       [frontend]
R2b: Form validation — server side                       [backend]
R3:  Store submissions in database                       [backend]
R4:  Email submissions to sales@example.com              [backend]
R5:  Show success message after submission               [frontend]

All declared layers covered: frontend (R1, R2a, R5), backend (R2b, R3, R4). ✓

Planned REQs:
  REQ-001 form-ui              → R1   layer: frontend
  REQ-002 client-validation    → R2a  layer: frontend
  REQ-003 server-validation    → R2b  layer: backend
  REQ-004 store-submissions    → R3   layer: backend
  REQ-005 email-submissions    → R4   layer: backend
  REQ-006 success-message      → R5   layer: frontend
```

For projects with `layers: [agents, commands, templates]` (do-work itself), tags would be `agents`, `commands`, `templates`, or `none` — same machinery, different vocabulary.
```

- [ ] **Step 4: Update Step 3b's frontend scope decision to be layer-agnostic**

Find the "Frontend scope decision" subsection (item 2 in Step 3b's rules). Replace the entire item 2 with:

```markdown
2. **Layer scope decision.** After tagging, for each layer in `layers_in_scope`, check whether any R-number carries that layer's tag:
   - If **yes** for every layer in scope, continue — every layer is enumerated and will be decomposed into REQs.
   - If **no** for any layer in scope, you have a gap. Either (a) you missed a requirement and need to add R-numbers for that layer, or (b) the brief genuinely doesn't touch that layer in this UR. The Step 4c layer-coverage prompt (introduced in Task 9) will surface this — for now, proceed to Step 4 and let the prompt drive the decision.
```

- [ ] **Step 5: Update Step 4 to require `**Layer:**` field on every REQ**

Find Step 4 ("Write REQ files"). Add a paragraph immediately before the template:

```markdown
**Every REQ must carry a `**Layer:**` field.** Set it from the R-number's tag (Step 3b). If multiple R-numbers map to the same REQ, they must all share the same tag — otherwise split the REQ. Bug-fix briefs (classification from Step 2b) write `**Layer:** none` on every REQ.
```

- [ ] **Step 6: Verify**

```bash
grep -n "layers_in_scope" agents/capture.md
grep -n "\*\*Layer:\*\*" agents/capture.md | head -5
```

Expected: `layers_in_scope` referenced in Step 3b and Step 4; Layer field shown in template and rules.

- [ ] **Step 7: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture assigns layer per REQ from declared layers"
```

---

## Task 9: Add layer-coverage prompt pass to capture (Step 4c)

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 4c runs after REQs are written but before commit. For each layer in `layers_in_scope` not covered by any REQ, capture asks the user via `AskUserQuestion` whether the layer is needed. Yes-path generates the missing REQ(s). No-path records the decision.

- [ ] **Step 2: Insert Step 4c immediately after Step 4b**

Find Step 4b ("Check acceptance criteria quality") in capture.md. Insert this new step after it:

```markdown
### 4c. Layer-coverage prompt

This pass runs only for `feature`-class briefs (or `other` briefs the user opted up to feature-style). Bug-fix briefs skip this entire step.

Build the coverage matrix:
1. For each layer in `layers_in_scope`, scan all REQs just written in Step 4 and count how many have `**Layer:** <name>` matching it.
2. List the layers with zero coverage.

If `layers_in_scope` is empty (`--no-layers` was passed, or this is a bug-fix), this step is a no-op. Skip it.

For each uncovered layer, present this prompt via `AskUserQuestion`:

```
Project declares layer "{layer}", but no REQ covers it.
Brief: "{one-sentence summary of input.md's first paragraph}"

Is "{layer}" needed for this UR?
```

Options:
1. **"Yes — generate REQ(s)"** — Ask follow-ups, then write the missing REQ(s)
2. **"No — record decision and skip"** — Record `layer_decisions: { <layer>: no }` in UR frontmatter (Task 13 step)
3. **"Unsure — show typical work"** — Show 2-3 example REQ titles for this layer for this brief; loop back to the same prompt

**Yes path follow-ups:** ask the user (one at a time, through plain prompts) for: which screens/routes/commands the layer should cover, what the layer's piece of the work looks like in plain language. Then generate one or more REQs tagged with the layer, following the Step 4 template, and append them to the backlog. Re-run Step 4b's quality check on the new REQ(s).

**No path:** record the decision in working state. The actual frontmatter write happens in Step 7 (Task 13). For now, hold `layer_decisions[<layer>] = no` in context.

**Loop:** after each layer is resolved (yes or no), continue to the next uncovered layer until none remain.

**Prompt input convention.** The layer-coverage gate uses `AskUserQuestion` regardless of `config.next_steps.enabled` — this is a workflow gate, not a next-step suggestion. Empty user input picks option 2 ("No — record decision and skip"). This is the only safe default; option 1 would silently generate REQs the user hasn't endorsed.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 4c. Layer-coverage prompt" agents/capture.md
grep -n "uncovered layer" agents/capture.md
```

Expected: both present.

- [ ] **Step 4: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture prompts for uncovered layers"
```

---

## Task 10: Add integration question pass to capture (Step 5)

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 5 (renumbering existing Steps 5-6 to 6-7) runs the integration question against every REQ whose `**Layer:**` is not `none`. Capture inspects the codebase for reachability/data/service dependencies, rates confidence, and writes the `## Integration` block into each REQ.

- [ ] **Step 2: Renumber existing Step 5 (Commit the backlog) to Step 7, and Step 6 (Report and prompt) to Step 8**

Find "### 5. Commit the backlog" in capture.md. Rename to "### 7. Commit the backlog". Find "### 6. Report and prompt". Rename to "### 8. Report and prompt".

- [ ] **Step 3: Insert Step 5 (Integration question pass) after Step 4c**

Insert:

```markdown
### 5. Integration question pass

This pass runs only for `feature`-class briefs and only on REQs whose `**Layer:**` is not `none`. Bug-fix briefs and `none`-layer REQs skip it.

For each qualifying REQ, fill the `## Integration` block by answering three sub-questions, citing concrete file paths or symbols.

**The three sub-questions:**

1. **Reachability** — How does the user (or caller) actually reach this? Nav entry, menu item, route, parent component, command name, API consumer, scheduled job trigger, library entry point.
2. **Data dependencies** — What existing data, state, or models does this read or write?
3. **Service dependencies** — What existing services, modules, or internal APIs does this depend on or extend?

**Procedure per REQ:**

1. Inspect the codebase to draft answers. Read routes files, nav components, command registries, existing service classes, library exports, models — whatever is relevant given the REQ's `**Layer:**`. Use `Glob`, `Grep`, and `Read`. Do not search the whole repo; bound by the REQ's task description.

2. Rate confidence per sub-question:
   - **High** — you have a concrete file path or symbol reference, AND that file/symbol exists.
   - **Partial** — you have a candidate but cannot verify it exists, OR your reference is vague (a directory not a file, a concept not a symbol).
   - **Low** — you cannot answer from the codebase at all.

3. **Verify high-confidence references before accepting them.** For each cited file path, run `test -f <path>` or `Read` the file (limit 1 line) — if the file does not exist, downgrade to partial. For each cited symbol, `grep -rn "<symbol>"` in the relevant directory — if no match, downgrade to partial. "High" must mean checked, not felt.

4. Aggregate confidence per REQ:
   - **High overall** — all three sub-questions rated high (and verified).
   - **Partial** — any sub-question is partial (after verification).
   - **Low** — at least two sub-questions are low.

5. **High overall:** Write the `## Integration` block into the REQ, replacing the placeholder template's bracketed text with the verified answers. Each answer cites a concrete file path or symbol.

6. **Partial:** Write what's known. For each partial sub-question, ask the user via `AskUserQuestion` with up to 3 candidate answers from the codebase exploration plus a "Tell me directly" option. Replace the partial answer with the user's choice. Re-rate; if all three are now high, the REQ is high overall.

7. **Low:** Write a placeholder block listing what was checked, then ask the user directly via `AskUserQuestion`:
   ```
   Cannot answer integration sub-questions from codebase exploration.
   Checked: <files/dirs that were read>
   Found: <what was found, or "nothing relevant">

   How would you like to proceed?
   ```
   Options: (1) "I'll answer inline" — collect three free-text answers, (2) "Mark this REQ low confidence and continue", (3) "Skip this REQ — I'll fill it in manually later".

8. Record the per-REQ aggregate confidence (`high` / `partial` / `low`) in working state. The frontmatter `reqs:` list (Step 7 below) will carry this as `integration_confidence: <value>`.

**No-fabrication rule.** Capture must not invent file paths, symbols, or service names to satisfy the high-confidence bar. Better to record `partial` and surface the gap than to ship a confident-looking but bogus reference. The verification grep/read step is the guardrail.
```

- [ ] **Step 4: Verify**

```bash
grep -n "### 5. Integration question pass" agents/capture.md
grep -n "### 7. Commit the backlog" agents/capture.md
grep -n "### 8. Report and prompt" agents/capture.md
grep -n "No-fabrication rule" agents/capture.md
```

Expected: all four present.

- [ ] **Step 5: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture runs integration question pass with file verification"
```

---

## Task 11: Add Step 6 (Write capture summary block to UR)

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 6 (between Integration question pass and Commit) writes a `## Capture summary` block to the UR's `input.md` body, immediately after the YAML frontmatter and before the `## Request` heading.

- [ ] **Step 2: Insert Step 6**

After Step 5 (Integration question pass), insert:

```markdown
### 6. Write capture summary to UR body

Prepend (or replace, on re-run — see Step 7 idempotency rules) a summary block to `input.md`'s body, immediately after the YAML frontmatter close (`---`) and before the `## Request` heading.

Format:

```markdown
## Capture summary (YYYY-MM-DD)

| Item | Value |
|---|---|
| Classification | <bug-fix | feature | other-as-feature | other-as-bug-fix> |
| Layers in scope | <comma-separated list, or "(none — --no-layers)" or "(none — bug-fix)"> |
| Layer decisions | <comma-separated "<layer>: no" entries, or "(none — all covered)"> |
| REQs generated | <count> |

| REQ | Layer | Integration confidence |
|---|---|---|
| REQ-NNN | <layer> | <high | partial | low | n/a> |
| ...        |        |        |
```

`integration_confidence: n/a` for any REQ with `**Layer:** none` (bug-fix or pure-refactor REQs that don't run the integration pass).

**Idempotency on re-run:** If a `## Capture summary` heading already exists in the body, replace the entire block (the heading and both tables) in place. Do not append a second summary. Detect by searching for `^## Capture summary` (start-of-line) and replacing through the next blank line that follows the second table. The verbatim brief in `## Request` must never be modified.

**Frontmatter is canonical.** This summary block is a regeneratable view. The authoritative state lives in the YAML frontmatter (Step 7). Edits made by hand to this block will be overwritten on the next capture run.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 6. Write capture summary" agents/capture.md
grep -n "Frontmatter is canonical" agents/capture.md
```

Expected: present.

- [ ] **Step 4: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture writes summary block to UR body"
```

---

## Task 12: Add Step 6b (Write/update UR frontmatter)

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

A new Step 6b updates `input.md`'s YAML frontmatter to record everything capture decided: classification, layers_in_scope, layer_decisions, reqs list, acknowledged_partials. This is the canonical state verify reads.

- [ ] **Step 2: Insert Step 6b after Step 6**

```markdown
### 6b. Write UR frontmatter

Update `input.md`'s YAML frontmatter (the block between the first two `---` lines) to record capture's decisions. The frontmatter must end up looking like:

```yaml
---
ur: UR-NNN
received: YYYY-MM-DD
status: captured                # was: intake
classification: <bug-fix | feature | other-as-feature | other-as-bug-fix>
layers_in_scope: [<comma-separated layers, or empty list>]
layer_decisions: {}             # populated only when the user said "no" to a layer
reqs:
  - { id: REQ-NNN, layer: <layer or none>, integration_confidence: <high | partial | low | n/a> }
  - ...
acknowledged_partials: []       # REQ ids the user has reviewed and waved through
---
```

**Field rules:**

- `status` flips from `intake` to `captured`. (If a future re-capture revisits a UR with `status: captured`, leave it as `captured`.)
- `classification` is from Step 2b.
- `layers_in_scope` is the per-UR snapshot from Step 2c. May be empty for bug-fix briefs or `--no-layers` invocations.
- `layer_decisions` only contains entries for layers the user explicitly opted out of in Step 4c. Layers with REQs covering them do not appear here.
- `reqs` is a list of every REQ in this UR (matched by `**UR:** UR-NNN` in the REQ files, including REQs in working/ or archive/ that belong to this UR).
- `acknowledged_partials` is preserved from the existing frontmatter on re-run; never reset by capture.
- `open_gaps` is preserved from the existing frontmatter (ideate writes it, capture leaves it alone). If absent, it's not added by capture.

**Idempotency on re-run** (capture invoked on a UR that already has `status: captured`):

- `classification` — preserved from existing frontmatter; not re-derived.
- `layers_in_scope` — re-derived from current config and Step 2c logic; the new value overwrites the old. (This means edits to `layers:` propagate when capture re-runs.)
- `layer_decisions` — preserved entries are kept; new "no" answers in this run merge in. Capture does not re-prompt for layers where `layer_decisions[<layer>] == no`.
- `reqs` — rebuilt from scratch by scanning REQ files in backlog/working/archive matching this UR. New REQs from this run are included; deleted REQ entries are dropped.
- `acknowledged_partials` — preserved verbatim. Never modified by capture.

A re-run that produces no new REQs and no new layer decisions is otherwise a no-op except for refreshing the summary block timestamp (Step 6).
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 6b. Write UR frontmatter" agents/capture.md
grep -n "Idempotency on re-run" agents/capture.md
grep -n "acknowledged_partials" agents/capture.md
```

Expected: all present.

- [ ] **Step 4: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture writes canonical state to UR frontmatter"
```

---

## Task 13: Update capture's commit and reporting steps

**Files:**
- Modify: `agents/capture.md`

- [ ] **Step 1: Define expected end-state**

Step 7 (Commit) stages the updated `input.md` in addition to REQ files. Step 8 (Report) includes the capture summary in its output.

- [ ] **Step 2: Edit Step 7 (Commit the backlog)**

Find the renamed Step 7 in capture.md. Replace the `git add` line that targets only REQ files. New body:

```markdown
### 7. Commit the backlog

Stage and commit the newly created REQ files, the updated UR `input.md`, and the ideate.md file if it exists.

If the project is not a git repo, skip this step silently.

```bash
# Stage all new REQ files in the backlog root
git add {project}/do-work/REQ-*.md

# Stage the updated UR input.md (frontmatter + summary block changes)
git add {project}/do-work/user-requests/UR-NNN/input.md

# Stage ideate.md if it was created by the ideate agent
git add {project}/do-work/user-requests/UR-NNN/ideate.md 2>/dev/null || true

git commit -m "chore(UR-NNN): decompose into N REQs"
```

Replace `N` with the actual number of REQ files written.
```

- [ ] **Step 3: Edit Step 8 (Report and prompt)**

Find the renamed Step 8. Replace the report block to include capture's headline decisions:

```markdown
After writing all REQ files and frontmatter, output the completion report:

```
Capture complete for UR-NNN

Classification: <classification>
Layers in scope: <list, or "(none)">
Layer decisions: <"<layer>: no" entries, or "(none — all covered)">

REQs written:
  REQ-NNN-slug.md — Short title — layer: <layer> — integration: <confidence>
  ...

Total: N tasks in backlog
```

The user reads this to confirm capture's decisions match the brief. Detail-level review can use the `## Capture summary` block in `input.md`.
```

(Leave the `AskUserQuestion` next-steps logic unchanged — it stays as it is today.)

- [ ] **Step 4: Verify**

```bash
grep -n "input.md" agents/capture.md | head
grep -n "Classification:" agents/capture.md
grep -n "integration: <confidence>" agents/capture.md
```

Expected: input.md is staged in commit step; Classification: appears in report.

- [ ] **Step 5: Commit**

```bash
git add agents/capture.md
git commit -m "feat(do-work): capture commits frontmatter and reports decisions"
```

---

## Task 14: Add the ideate interactive gate

**Files:**
- Modify: `agents/ideate.md`

- [ ] **Step 1: Define expected end-state**

Ideate's Step 5 (Report and prompt) is replaced by a mandatory three-option `AskUserQuestion` gate: Grill / Continue / Stop. The gate runs regardless of `config.next_steps.enabled`. Empty input picks Continue.

- [ ] **Step 2: Edit ideate.md Step 5**

Replace the entire `### 5. Report and prompt` section (lines 102-125) with:

```markdown
### 5. Report and prompt — interactive gate

Output the completion report:

```
Ideate complete for UR-NNN.

Written: {project}/do-work/user-requests/UR-NNN/ideate.md

Gaps surfaced:
- [gap 1, one line]
- [gap 2, one line]
- ...
```

Compile the gaps from the Explorer "Assumptions & Perspectives" and Challenger "Risks & Edge Cases" sections of the just-written ideate.md — pick the top 3-5, one line each.

**Then, regardless of `config.next_steps.enabled` setting, present the gate via `AskUserQuestion`:**

Question: `How would you like to proceed?`

Options:
1. **"Grill me"** — Run interactive Q&A on the surfaced gaps before capture
2. **"Continue"** — Proceed to capture as-is, gaps recorded
3. **"Stop"** — Halt — let me revise input.md, then re-run

(`AskUserQuestion` exposes 3 options; this fits within the 4-option limit.)

**Empty user input picks option 2 (Continue).** This is the documented default. Other unrecognised input gets a one-line clarification and a re-prompt.

**Behaviour per option:**

- **(1) Grill me:** Read and follow [question.md](question.md) in full, scoped to the gaps just listed. After question.md returns, control flows back here — automatically continue to capture (do not re-show this gate).
- **(2) Continue:** Write the surfaced gaps to the UR's `input.md` YAML frontmatter under an `open_gaps:` list (one item per gap, verbatim). If `open_gaps:` already exists in the frontmatter (rare — the user re-ran ideate), overwrite it. Then return control to the caller (start.md) so it proceeds to capture. If `input.md` has no frontmatter (legacy UR — should not happen for new URs but guard anyway), append the gap list to the body under a `## Notes — Open Gaps` heading instead.
- **(3) Stop:** Output `Halted by user — revise {project}/do-work/user-requests/UR-NNN/input.md and re-run`. Return control to the caller; the caller must NOT proceed to capture.

**The `--grill` flag on start.md is removed** (Task 16). Users now pick Grill at this gate when they want it, after seeing the actual gaps. The gate runs whether or not `next_steps.enabled` is true — this is a workflow gate, not a next-step suggestion.
```

- [ ] **Step 3: Verify**

```bash
grep -n "interactive gate" agents/ideate.md
grep -n "Grill me" agents/ideate.md
grep -n "Empty user input picks option 2" agents/ideate.md
```

Expected: all present.

- [ ] **Step 4: Commit**

```bash
git add agents/ideate.md
git commit -m "feat(do-work): ideate ends with mandatory interactive gate"
```

---

## Task 15: Wire ideate's Stop signal in start.md

**Files:**
- Modify: `agents/start.md`

- [ ] **Step 1: Define expected end-state**

start.md's Step 2 (Run Ideate) is updated to honor the gate's three outcomes. On Stop, start halts before capture. On Grill or Continue, start proceeds to capture.

- [ ] **Step 2: Edit start.md Step 2**

Find Step 2 in `agents/start.md` (lines 51-61 today). Replace with:

```markdown
### 2. Run Ideate (default — skip with `--no-ideate`)

Unless the `--no-ideate` flag was specified:

Read and follow [ideate.md](ideate.md) in full.

Pass it the UR folder path from Step 1.

Ideate now ends with a mandatory interactive gate (Grill / Continue / Stop). Honor the gate's outcome:

- **Grill** chosen by user → ideate.md will already have invoked question.md inline. Continue to Step 3 (Run Capture) when ideate returns.
- **Continue** chosen by user (or empty input default) → Continue to Step 3 (Run Capture) when ideate returns.
- **Stop** chosen by user → **Halt the start orchestrator.** Do not run Capture. Output: `Start halted at ideate gate — revise UR-NNN/input.md and re-run start.` Return.

After ideate returns (and unless Stop was chosen), read `{project}/do-work/user-requests/UR-NNN/ideate.md` — keep its observations in context for Step 3.

If `--no-ideate` was specified, skip this step entirely (no gate runs).
```

- [ ] **Step 3: Verify**

```bash
grep -n "interactive gate" agents/start.md
grep -n "Halt the start orchestrator" agents/start.md
```

Expected: present.

- [ ] **Step 4: Commit**

```bash
git add agents/start.md
git commit -m "feat(do-work): start honors ideate gate outcomes"
```

---

## Task 16: Remove `--grill` flag from start.md

**Files:**
- Modify: `agents/start.md`

- [ ] **Step 1: Define expected end-state**

`--grill` is removed from start.md entirely. The Step 1b (Run Question) section is deleted. The flag list in start.md's "When Invoked" no longer mentions it.

- [ ] **Step 2: Delete Step 1b (Run Question — opt-in — requires `--grill`)**

Find `### 1b. Run Question (opt-in — requires \`--grill\`)` in `agents/start.md` (lines 39-49). Delete the entire section, including its heading and body.

- [ ] **Step 3: Update the "When Invoked" flag list**

Find lines 13-18 in start.md. Replace with:

```markdown
You will be given:

1. A project do-work path: `{project}/do-work/`
2. The user's message or brief
3. Optional flags:
   - `--no-ideate` (skip ideate before capture)
   - `--no-layers` (skip layer-coverage check for this invocation only — passed through to capture)
```

- [ ] **Step 4: Update the report section's "Question:" line if present**

Find any reference to `Question:` in the report block. Remove the line `Question: [yes/no]` if it exists.

- [ ] **Step 5: Verify**

```bash
grep -n "grill" agents/start.md
grep -n "Run Question" agents/start.md
```

Expected: zero matches for `grill` (case-insensitive, except possibly inside a comment about removal); zero matches for `Run Question`.

- [ ] **Step 6: Commit**

```bash
git add agents/start.md
git commit -m "feat(do-work): remove --grill flag, replaced by ideate gate"
```

---

## Task 17: start.md accepts `--no-layers` and threads it to capture

**Files:**
- Modify: `agents/start.md`

- [ ] **Step 1: Define expected end-state**

When `--no-layers` is in the args, start.md passes it through to capture's invocation. (Capture's Step 2c already reads it — Task 7.)

- [ ] **Step 2: Edit start.md Step 3 (Run Capture)**

Find `### 3. Run Capture` in start.md. Update the body so capture is invoked with the flag:

```markdown
### 3. Run Capture

Read and follow [capture.md](capture.md) in full.

Pass it:
- The UR folder path from Step 1
- The `--no-layers` flag if it was set on the start invocation (capture reads it in its Step 2c)

If ideate was run in Step 2, the Capture agent should read `ideate.md` alongside `input.md` when decomposing — treating the observations as additional context (not as requirements to blindly follow).
```

- [ ] **Step 3: Verify**

```bash
grep -n "no-layers" agents/start.md
```

Expected: at least 2 matches (the flag list + the capture invocation).

- [ ] **Step 4: Commit**

```bash
git add agents/start.md
git commit -m "feat(do-work): start passes --no-layers through to capture"
```

---

## Task 18: go.md accepts `--no-layers` and threads it through

**Files:**
- Modify: `agents/go.md`

- [ ] **Step 1: Define expected end-state**

go.md's flag list documents `--no-layers`. When go re-invokes capture (e.g. via `--auto-fix`), the flag is threaded through.

- [ ] **Step 2: Read go.md to find the flag list and capture invocation points**

```bash
grep -n "auto-fix\|--force\|capture\|verify" agents/go.md
```

- [ ] **Step 3: Edit go.md to add `--no-layers` to its flag list**

Locate the "When Invoked" or "Optional flags" section. Add:

```markdown
   - `--no-layers` (skip layer-coverage check for this invocation only — passed through to any capture re-runs triggered by --auto-fix)
```

- [ ] **Step 4: Edit go.md to thread `--no-layers` through**

Find every place go.md invokes capture (likely inside auto-fix logic). For each, append `--no-layers` to the invocation if the flag was set on the go invocation.

- [ ] **Step 5: Verify**

```bash
grep -n "no-layers" agents/go.md
```

Expected: at least 1 match.

- [ ] **Step 6: Commit**

```bash
git add agents/go.md
git commit -m "feat(do-work): go threads --no-layers to capture re-runs"
```

---

## Task 19: Verify reads UR frontmatter (Step 1 update)

**Files:**
- Modify: `agents/verify.md`

This finalises the legacy detection seeded in Task 3 by adding the actual frontmatter parse for non-legacy URs.

- [ ] **Step 1: Define expected end-state**

verify.md's Step 1 reliably parses UR frontmatter for non-legacy URs and holds the parsed values in context. Legacy URs still work but skip new checks.

- [ ] **Step 2: Edit verify.md Step 1**

Find the "Legacy UR detection" block added in Task 3. Append immediately after it (still inside Step 1):

```markdown
**Frontmatter parse for non-legacy URs.** For URs that begin with a `---` block, parse the YAML frontmatter and extract:

- `classification` (one of: bug-fix, feature, other-as-feature, other-as-bug-fix)
- `layers_in_scope` (list of layer names, possibly empty)
- `layer_decisions` (map of `<layer>: no` entries)
- `reqs` (list of `{ id, layer, integration_confidence }` records)
- `acknowledged_partials` (list of REQ ids)

If any of these fields is missing from a non-legacy UR's frontmatter, treat it as if the field is empty (e.g. `layer_decisions: {}`, `reqs: []`). This keeps verify lenient against partial state.

Hold all parsed values in context for Steps 4b, 4c, 4d below.
```

- [ ] **Step 3: Verify**

```bash
grep -n "Frontmatter parse" agents/verify.md
grep -n "acknowledged_partials" agents/verify.md
```

Expected: both present.

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify parses UR frontmatter for non-legacy URs"
```

---

## Task 20: Verify check 4b — layer-coverage

**Files:**
- Modify: `agents/verify.md`

- [ ] **Step 1: Define expected end-state**

A new Step 4b in verify.md performs the layer-coverage check using parsed frontmatter. Skipped for legacy URs and for URs with empty `layers_in_scope`.

- [ ] **Step 2: Insert Step 4b after the existing Step 4 (Check for issues)**

```markdown
### 4b. Layer-coverage check

This check is skipped for:
- Legacy URs (no frontmatter — flagged in Step 1).
- URs with empty `layers_in_scope` (bug-fix briefs, or `--no-layers` invocations).

For all other URs:

1. For each layer in `layers_in_scope` (from frontmatter):
   - Scan all REQs in this UR (by `**UR:** UR-NNN`) for any with `**Layer:** <layer>`.
   - If at least one REQ matches, the layer is covered.
   - If no REQ matches, check `layer_decisions[<layer>]`. If it equals `no`, the gap is acknowledged — not flagged.
   - Otherwise, this is a layer-coverage gap.

2. List each layer-coverage gap. Each gap reduces the confidence score by 10 points (capped at -30 total deduction across all layer-coverage gaps).

3. Auto-fix integration: a layer-coverage gap with `--auto-fix` triggers a re-invocation of capture's Step 4c (layer-coverage prompt) scoped to that single layer.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 4b. Layer-coverage check" agents/verify.md
```

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify check 4b for layer coverage"
```

---

## Task 21: Verify check 4c — Integration block

**Files:**
- Modify: `agents/verify.md`

- [ ] **Step 1: Define expected end-state**

A new Step 4c in verify.md verifies that every non-`none`-layer REQ in a feature-class UR has a non-empty `## Integration` block with all three sub-questions answered.

- [ ] **Step 2: Insert Step 4c after Step 4b**

```markdown
### 4c. Integration block check

This check is skipped for:
- Legacy URs.
- URs whose `classification` is `bug-fix` or `other-as-bug-fix`.

For all other URs (`feature` or `other-as-feature`), iterate through `reqs:` in the frontmatter:

1. Skip any REQ with `layer: none` — those don't require an Integration block.

2. For each remaining REQ, open its file and check for the `## Integration` section.
   - If the section is missing → flag as gap.
   - If the section is present but any of the three sub-question lines (`**Reachability:**`, `**Data dependencies:**`, `**Service dependencies:**`) is missing or empty → flag as gap.
   - If all three are present and non-empty → covered.

3. List each Integration block gap with the REQ id and which sub-questions are missing. Each gap reduces the confidence score by 5 points (capped at -25 total).

4. Auto-fix integration: an Integration block gap with `--auto-fix` triggers a re-invocation of capture's Step 5 (Integration question pass) scoped to that single REQ.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 4c. Integration block check" agents/verify.md
```

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify check 4c for integration block"
```

---

## Task 22: Verify check 4d — partial-confidence

**Files:**
- Modify: `agents/verify.md`

- [ ] **Step 1: Define expected end-state**

A new Step 4d flags REQs with `integration_confidence: partial` unless their id appears in `acknowledged_partials`. Auto-fix does **not** re-run on partials (per spec — repeated runs would just re-produce the same partial result).

- [ ] **Step 2: Insert Step 4d after Step 4c**

```markdown
### 4d. Partial-confidence check

This check is skipped for legacy URs and for `bug-fix` / `other-as-bug-fix` classifications.

For all other URs, iterate through `reqs:` in the frontmatter:

1. For each REQ where `integration_confidence == partial`:
   - If the REQ id appears in `acknowledged_partials`, treat as resolved — no flag.
   - Otherwise, flag as partial-confidence gap.

2. List each partial-confidence gap with the REQ id. Each gap reduces the confidence score by 3 points (capped at -15 total).

3. **Auto-fix does NOT auto-resolve partials.** Re-running the integration question on the same codebase typically produces the same partial result. The user must either:
   - Edit the REQ's `## Integration` block manually to upgrade to high confidence, then capture's idempotent re-run will pick up the improvement, OR
   - Add the REQ id to `acknowledged_partials` in UR frontmatter to wave the gap through.

   **v1 limitation noted in spec:** the user edits frontmatter directly. A richer "(1) Resolve / (2) Acknowledge / (3) Skip" prompt is scoped as a follow-up; not in this plan.
```

- [ ] **Step 3: Verify**

```bash
grep -n "### 4d. Partial-confidence check" agents/verify.md
grep -n "v1 limitation" agents/verify.md
```

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify check 4d for partial integration confidence"
```

---

## Task 23: Update verify auto-fix to handle new gap types

**Files:**
- Modify: `agents/verify.md`

- [ ] **Step 1: Define expected end-state**

verify.md's Step 6 (Auto-fix) handles two new gap types: layer-coverage (re-runs capture's Step 4c for that layer) and Integration block (re-runs capture's Step 5 for that REQ). Partial-confidence is explicitly NOT auto-fixed.

- [ ] **Step 2: Edit verify.md Step 6 (Auto-fix)**

Find `### 6. Auto-fix (optional)` in verify.md. Insert a new sub-section after item 1 of the existing list:

```markdown
**New auto-fix actions (gap-aware capture):**

- **Layer-coverage gap:** Re-invoke capture's Step 4c (Layer-coverage prompt) scoped to the missing layer. The prompt asks the user yes/no/unsure; if yes, capture writes the missing REQ(s) and re-runs Step 4b (acceptance criteria quality) and Step 5 (Integration question) on them.

- **Integration block gap:** Re-invoke capture's Step 5 (Integration question pass) scoped to the single affected REQ. Capture inspects the codebase, drafts answers, and asks the user for any partial sub-questions. The REQ is updated in place.

- **Partial-confidence gap:** **Not auto-fixed.** Auto-fix would just re-run the same exploration and likely produce the same partial result. Surface to user with the resolution options listed in Step 4d.

These actions run after item 1 (write missing REQs from missing brief requirements) and before item 5 (re-score). Re-scoring is mandatory and includes the new checks (4b, 4c, 4d).
```

- [ ] **Step 3: Verify**

```bash
grep -n "Layer-coverage gap" agents/verify.md
grep -n "Integration block gap" agents/verify.md
```

- [ ] **Step 4: Commit**

```bash
git add agents/verify.md
git commit -m "feat(do-work): verify auto-fix handles new gap types"
```

---

## Task 24: Update SKILL.md

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Define expected end-state**

SKILL.md's Quick Reference table no longer mentions `--grill`. The flag table for `start` and `go` lists `--no-layers`. New text documents the `layers:` config field, the `**Layer:**` REQ field, and the Integration block requirement.

- [ ] **Step 2: Update the Quick Reference table — drop `--grill`, add `--no-layers`**

Find the Quick Reference table in SKILL.md. Replace the start rows:

```markdown
| `/do-work start [brief]` | Records brief + decomposes into REQs in one shot. Includes ideate by default. Auto-installs if needed. |
| `/do-work start [brief] --no-ideate` | Same as start, but skips the creativity review before decomposition. |
| `/do-work start [brief] --no-layers` | Same as start, but skips layer-coverage checks for this UR (records `layers_in_scope: []`). |
```

(The `--grill` row is deleted entirely. Users now choose Grill at the ideate gate.)

Update the go rows similarly to add `--no-layers`:

```markdown
| `/do-work go [UR-NNN] --no-layers` | Verify + run, skipping layer-coverage checks for this UR. |
```

- [ ] **Step 3: Add a "Layers" section to SKILL.md**

After the "Milestone Mode" section (around line 95) and before "Commit Convention", insert:

```markdown
## Layers

do-work uses project-declared layers to gap-check feature briefs. Declare your project's layers once in `do-work/config.yml`:

```yaml
layers: [frontend, backend]   # web app
# layers: [commands, core, output]            # CLI tool
# layers: [public_api, internal]              # library / SDK
# layers: [agents, commands, templates]       # do-work itself
```

Capture and verify use this list to enforce that REQs cover every declared layer for `feature`-class briefs (or surface explicit "no" decisions). Empty `layers:` opts out — feature briefs will halt until layers are declared or `--no-layers` is passed.

Every REQ written by capture carries a `**Layer:**` field naming one of the declared layers, or `none` for bug-fix / pure-refactor / test-only REQs.

Feature REQs that add new surface (anything callable or visible from outside their own code) include an `## Integration` section answering three sub-questions:

- **Reachability** — How does the user (or caller) reach this?
- **Data dependencies** — What existing data does this read or write?
- **Service dependencies** — What existing services or modules does this extend?

Capture inspects the codebase to draft answers and verifies each cited file/symbol exists before claiming high confidence. Verify enforces the Integration block on every non-`none` feature REQ.
```

- [ ] **Step 4: Verify**

```bash
grep -n "no-layers" SKILL.md
grep -n "## Layers" SKILL.md
grep -n "grill" SKILL.md  # should be empty
```

Expected: `--no-layers` appears in Quick Reference; `## Layers` section exists; no `grill` references.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "docs(do-work): document layers, --no-layers, drop --grill"
```

---

## Task 25: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read CHANGELOG.md**

```bash
head -30 CHANGELOG.md
```

- [ ] **Step 2: Add an entry for this refactor**

Prepend (under the appropriate version heading or at the top of unreleased changes) an entry like:

```markdown
## Gap-aware capture (2026-04-29)

**Added**
- `layers:` config field — declare a project's layers (`[frontend, backend]`, `[commands, core, output]`, etc.). Used by capture and verify to enforce gap-aware coverage.
- `**Layer:**` field on every REQ — names which declared layer the REQ belongs to, or `none` for bug-fix / pure-refactor.
- Required `## Integration` section on feature REQs that add new surface — answers reachability / data deps / service deps with concrete file/symbol references.
- UR `input.md` now has YAML frontmatter (`classification`, `layers_in_scope`, `layer_decisions`, `reqs`, `acknowledged_partials`).
- Capture writes a `## Capture summary` block to UR body for at-a-glance review.
- `--no-layers` flag on `start` and `go` — opts a single UR out of layer-coverage checks.
- Ideate ends with a mandatory interactive gate (Grill / Continue / Stop).

**Changed**
- Capture classifies briefs as `bug-fix` / `feature` / `other` and gates layer-coverage and integration passes accordingly.
- Verify reads UR frontmatter; new checks for layer coverage, Integration block, partial-confidence.
- Verify `--auto-fix` re-runs capture's relevant pass for layer / integration gaps.

**Removed**
- `--grill` flag on start. Users choose Grill at the ideate gate after seeing surfaced gaps.

**Compatibility**
- Existing URs without YAML frontmatter are treated as legacy. Verify skips all new checks for them; they continue to work as before.
- Existing REQs without a `**Layer:**` field are similarly exempt. No migration script.
```

- [ ] **Step 3: Verify**

```bash
head -40 CHANGELOG.md
```

Expected: new entry visible at top.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(do-work): changelog entry for gap-aware capture"
```

---

## Task 26: Declare do-work's own layers (dogfood, part 1)

**Files:**
- Create: `do-work/config.yml` (in dogfood project — i.e. the do-work skill repo's own do-work directory, if any. If not present, skip this task and note in handoff.)

- [ ] **Step 1: Check whether do-work has its own do-work directory**

```bash
ls -la do-work/ 2>/dev/null
```

- [ ] **Step 2: If `do-work/` does not exist in this repo, run install**

The do-work skill is the system being shipped, but this repo can also use it on itself. Create the structure:

```bash
mkdir -p do-work/user-requests do-work/working do-work/archive do-work/logs
```

- [ ] **Step 3: Write config.yml with layers declared**

Create `do-work/config.yml`:

```yaml
# do-work configuration
project:
  name: "do-work"

# Declare your project's layers, e.g. [frontend, backend] for a web app.
# do-work itself is a Markdown-and-prompts CLI framework — the layers
# below reflect its actual structure.
layers: [agents, commands, templates]

log:
  enabled: true
  platforms: []
  drafts_per_platform: 2
  batch_size: 2
  audience: ""
  voice: ""
  max_chars:
    x: 280
    blog: 500
    linkedin: 1300

test:
  suite_command: ""

next_steps:
  enabled: false
```

- [ ] **Step 4: Verify**

```bash
test -f do-work/config.yml && echo "OK"
grep "layers:" do-work/config.yml
```

Expected: `OK` and the layers line.

- [ ] **Step 5: Commit**

```bash
git add do-work/
git commit -m "chore(do-work): dogfood — declare do-work's own layers"
```

---

## Task 27: Run a synthetic UR through the new pipeline (dogfood, part 2)

**Files:**
- Create: `do-work/user-requests/UR-dogfood-001/input.md` (test artifact — may be deleted after verification)

This task validates the refactor end-to-end against do-work's own codebase. It is NOT a test in the unit-test sense — it's an integration verification.

- [ ] **Step 1: Define expected end-state**

A synthetic UR is created with a small feature-class brief. After running the (newly refactored) capture against it, the UR's `input.md` has YAML frontmatter populated correctly, a Capture summary block exists, REQ files exist with `**Layer:**` fields and `## Integration` sections (where applicable), and verify produces a coverage report that includes the three new checks.

- [ ] **Step 2: Create the synthetic UR**

Write `do-work/user-requests/UR-dogfood-001/input.md`:

```markdown
---
ur: UR-dogfood-001
received: 2026-04-29
status: intake
---

# UR-dogfood-001: User Request

## Request

Add a new `/do-work status` command that reports the current backlog count, working REQ if any, and last completed REQ. Update SKILL.md to document the new command. The command itself lives as a new agent file at agents/status.md.
```

- [ ] **Step 3: Run capture against this UR**

This step requires invoking the (newly refactored) capture agent. In a working session:

> "Run capture for `do-work/user-requests/UR-dogfood-001/`"

Capture should:
- Classify as `feature`.
- Read `layers: [agents, commands, templates]` from config.
- Produce REQs covering the relevant layers (likely `agents` for the new file, `commands` for SKILL.md doc, `templates` if any).
- Write Integration blocks with citations of existing files (e.g. SKILL.md, agents/help.md as a similar example).
- Update `input.md` frontmatter with `classification: feature`, `layers_in_scope: [agents, commands, templates]`, `reqs: [...]`.
- Prepend a Capture summary block.

- [ ] **Step 4: Verify the outputs**

```bash
# Check frontmatter was populated
grep -A 15 "^---" do-work/user-requests/UR-dogfood-001/input.md | head -20

# Check summary block was prepended
grep -n "## Capture summary" do-work/user-requests/UR-dogfood-001/input.md

# Check REQ files were created with Layer field
ls do-work/REQ-*.md
grep -l "\*\*Layer:\*\*" do-work/REQ-*.md

# Check at least one REQ has an Integration section
grep -l "## Integration" do-work/REQ-*.md
```

Expected:
- frontmatter has `classification:`, `layers_in_scope:`, `reqs:`.
- Summary block present.
- At least 1 REQ file with a Layer field.
- At least 1 REQ file with an Integration section (the new agents/status.md REQ should have one — it adds new surface).

- [ ] **Step 5: Run verify against the same UR**

> "Run verify for UR-dogfood-001"

Verify should produce a report that includes coverage, the three new checks (layer-coverage, Integration block, partial-confidence), and a confidence score.

- [ ] **Step 6: Verify the verify output**

The verify report should include:
- Coverage section with REQs mapped to brief requirements.
- A "Layers" subsection (or equivalent) showing which declared layers are covered.
- An Integration block check confirming each new-surface REQ has the section.
- A confidence score that's not artificially low (no false-positive gaps from the refactor).

- [ ] **Step 7: Decide: keep the dogfood UR or remove it**

If the run looks good, leave the UR in place as documentation of the dogfood. If it looks rough or noisy, remove the UR and the generated REQ files:

```bash
# Optional cleanup
rm -rf do-work/user-requests/UR-dogfood-001/
rm do-work/REQ-*.md  # only the ones from this dogfood — be careful
```

- [ ] **Step 8: Commit (if keeping the dogfood UR)**

```bash
git add do-work/
git commit -m "test(do-work): dogfood UR validates gap-aware capture pipeline"
```

If the dogfood UR is removed, no commit needed for this task.

- [ ] **Step 9: If the dogfood run revealed bugs in earlier tasks**

Stop and fix the underlying agent file before continuing. Re-run capture/verify until the dogfood produces correct output. Do not paper over a real bug by editing the synthetic UR.

---

## Task 28: Final integration check

**Files:**
- None (verification only)

- [ ] **Step 1: Spot-check that the spec's success criteria are met**

Walk the spec's "Success criteria" section and confirm each:

- A full-stack feature brief produces REQs covering each declared layer (or records explicit "no") — verified by Task 27 dogfood.
- Every feature REQ that adds new surface has `## Integration` with concrete file references — verified by Task 21 verify check + Task 27 dogfood.
- Ideate stops being write-only — verified by Task 14 gate.
- Bug-fix briefs not slowed down — verified by Task 9's classification gating.
- Verify never misfires on stacks it doesn't understand — verified by reading layer/REQ tags, not vocabulary (Task 19-22).
- do-work dogfoods on itself — verified by Task 26-27.
- No new commands, no new artifact types — verified structurally; no new agent files were created.

- [ ] **Step 2: Walk the open questions list and confirm decisions are recorded**

- `agents/layers.md` extraction → kept inline (Task 7+8). Recorded in spec's pre-flight at top of plan.
- `agents/classify.md` extraction → kept inline (Task 6). Recorded.
- REQ template location → confirmed inline in capture.md Step 4.
- `--grill` removal cycle → hard cut (Task 16).
- Install-time layer guess → install never auto-populates (Task 1's empty default).

- [ ] **Step 3: Summary report to user**

Output a brief summary listing what was changed, what was deferred (auto-fix bail-out, mid-run REQ creation, capture/wire split, partial-confidence richer prompt), and any unresolved issues from the dogfood run.

No commit needed.

---

## Self-review notes

*Filled in after writing the plan body.*

**Spec coverage check:** Walked the spec's design sections — every section maps to one or more tasks above:

- "Project-declared layers" → Task 1, 7
- "Brief classification" → Task 6
- "Ideate becomes an interactive gate" → Task 14, 15
- "REQ frontmatter gains a `layer:` field" → Task 4, 8
- "Capture's layer-coverage check" → Task 9
- "Capture's integration question" → Task 10
- "UR state moves to YAML frontmatter" → Task 2, 12
- "Visibility summary at the top of the UR body" → Task 11
- "Verify gets two new checks" (now three per round 3) → Task 19, 20, 21, 22
- "REQ template change" → Task 4, 5
- "SKILL.md changes" → Task 24
- "Idempotency" → embedded in Task 12
- "Config drift / late layer additions" → behaviour falls out of Task 12's idempotency rules; documented in spec, no separate task needed
- "Acknowledged tradeoffs" → no implementation needed; documented in spec
- "Files affected" table → reflected in this plan's File structure section
- "Success criteria" → Task 28's check
- Dogfood criterion → Task 26, 27

**Placeholder scan:** No `TBD`, `TODO`, `implement later`, or `Similar to Task N` appears in the steps. Each step contains the actual content needed.

**Type/name consistency check:**
- `layers_in_scope` (UR frontmatter), `layer:` (REQ frontmatter), `layers:` (config) — three distinct names, used consistently throughout the plan.
- `layer_decisions` (UR frontmatter), `acknowledged_partials` (UR frontmatter), `integration_confidence` (per-REQ in UR frontmatter `reqs:` list) — used consistently.
- Step numbering in capture.md after the refactor: 0, 1, 1b (milestone), 2, 2b (classify), 2c (read layers), 3, 3b (R-mapping), 4, 4b (criteria quality), 4c (layer-coverage prompt), 5 (integration question), 6 (capture summary), 6b (frontmatter), 7 (commit), 8 (report). Internally consistent.
- Step numbering in verify.md: 0, 1, 2, 2b, 3, 4, 4b (layer-coverage), 4c (Integration block), 4d (partial-confidence), 5, 6 (auto-fix). Internally consistent.

No further fixes needed.
