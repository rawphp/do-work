# Do-Work Questioning Phase — Design Spec

**Date:** 2026-04-12
**Status:** Draft
**Goal:** Raise output quality by adding two interrogation passes to the do-work pipeline — one that sharpens the user's brief, one that sharpens the system's REQ decomposition.

---

## Overview

Two new agents added to the do-work system:

1. **`question.md`** — Opt-in interactive agent that grills the user about their brief, extracting implicit assumptions, missing constraints, and unspoken requirements. Appends clarifications to `input.md`.

2. **`audit.md`** — Always-on autonomous agent that interrogates every REQ's acceptance criteria, error paths, scope boundaries, dependencies, and brief alignment. Auto-fixes soft spots and reports what it changed.

Neither agent adds scope. Both add precision.

---

## Agent 1: `question.md` — The User Grill

### Purpose

Interrogate the user's brief one question at a time to extract what the user knows but didn't say. Runs before the system decomposes the brief into tasks.

### Invocation

- Explicit: `/do-work question UR-NNN`
- Via start: `/do-work start --grill`
- Position in pipeline: after Intake, before Ideate

### Process

1. Read `input.md` from the UR folder.
2. Analyze the brief for ambiguity across five vectors:
   - **Scope gaps** — what's mentioned but not bounded?
   - **Unstated assumptions** — what's implied but not said?
   - **Missing actors** — who's involved but not named?
   - **Undefined outcomes** — what does success/failure look like?
   - **Dependency blindspots** — does this require something that doesn't exist yet?
3. Ask questions **one at a time**, walking each branch to resolution before moving to the next.
4. Prefer multiple choice questions when possible.
5. Never ask compound questions.
6. Every question must reference specific language from the brief — no generic checklists.
7. Stop when:
   - All high-value branches are explored, OR
   - User explicitly ends the session, OR
   - No further high-confidence questions remain
8. Append a `## Clarifications` section to `input.md` with a structured Q&A log.
9. Commit the updated `input.md`.

### Output Format

Appended to `input.md`:

```markdown
## Clarifications

**Q:** You said "handle form validation" — which fields need validation, and what are the rules?
**A:** Email (format + uniqueness), password (min 8 chars, one number), name (required, max 100 chars).

**Q:** What should the user see when validation fails?
**A:** Inline errors below each field, no page reload. Red border on the field.

**Q:** Is this client-side only, or does the server re-validate?
**A:** Both. Client-side for UX, server-side as the real gate.
```

### Guardrails

- Never modifies the original brief text — only appends below it.
- Never suggests changes to scope — only extracts what's already in the user's head.
- Never asks more than one question per message.
- Respects diminishing returns — stops when remaining ambiguities are low-value.
- If `## Clarifications` already exists (re-run), appends new Q&A entries below existing ones — never overwrites prior clarifications.

---

## Agent 2: `audit.md` — The REQ Grill

### Purpose

Autonomously interrogate every REQ's quality after capture. Auto-fix soft spots and report what changed. The system's self-critique before execution begins.

### Invocation

- Always-on: runs automatically inside `go.md`, after Verify passes and before Run starts.
- Explicit: `/do-work audit UR-NNN` for standalone use.

### Process

1. Read all REQ files in the backlog for the target UR.
2. Read `input.md` (including any `## Clarifications`) as ground truth.
3. Read `ideate.md` if present, for Challenger risks and Connector overlaps.
4. For each REQ, interrogate five dimensions:

#### Dimension 1: Acceptance Criteria Specificity
Is each criterion falsifiable? Could you write a test for it? Rewrite vague qualifiers ("correctly", "properly", "as expected") into concrete observable outcomes.

#### Dimension 2: Error Path Coverage
Does the REQ account for what happens when things fail? Add missing error/edge case criteria where the happy path is defined but failure isn't.

#### Dimension 3: Scope Boundary Clarity
Is it clear what this REQ touches and what it doesn't? Flag REQs that could bleed into adjacent work.

#### Dimension 4: Dependency Ordering
Does this REQ assume something from another REQ that hasn't been completed yet? Flag out-of-order dependencies.

#### Dimension 5: Brief Alignment
Does this REQ's description and criteria trace back to something in the brief? Flag scope creep (work not rooted in the brief) and drift (subtle misinterpretation of the brief).

5. Auto-fix what it can:
   - Rewrite vague acceptance criteria into specific, testable statements.
   - Add missing error path criteria.
   - Annotate dependency notes on REQs with ordering issues.
6. Produce a change report.
7. Commit improved REQs: `chore(UR-NNN): audit REQs — N fixes applied`

### Auto-Fix Boundaries

The audit agent:
- **Does** rewrite vague criteria into specific ones.
- **Does** add missing error path criteria.
- **Does** annotate dependency ordering issues.
- **Does not** delete REQs.
- **Does not** merge REQs.
- **Does not** change scope.
- **Does not** change task descriptions — only sharpens criteria and adds annotations.
- **Does not** block the run — it's a sharpening pass, not a gate.
- If it can't confidently fix something, it flags instead of guessing.

### Change Report Format

```
## Audit Report — UR-NNN

### REQ-001: Add user registration form
- [FIXED] Acceptance criterion "form validates correctly" → "form rejects emails without @ symbol, passwords under 8 characters, and empty name field; displays inline error below each failing field"
- [FIXED] Added error path: "if registration API returns 500, form displays 'Something went wrong, please try again' and preserves entered data"
- [OK] Scope boundaries clear
- [OK] No dependency issues

### REQ-002: Send welcome email
- [OK] Criteria specific
- [FLAG] Depends on REQ-001 (user must exist) but REQ-002 is sequenced after REQ-001 — ordering is correct
- [FLAG] Brief doesn't mention email content or template — unable to auto-fix, may need user input

### Summary
- 2 criteria rewritten
- 1 error path added
- 1 flag requiring user judgment
- Overall: minor fixes applied
```

---

## Pipeline Integration

### Updated `start.md` Orchestration

```
Intake → [Question, if --grill] → Ideate → Capture
```

- `--grill` flag triggers question agent after intake completes.
- Question appends clarifications to `input.md` before ideate reads it.
- Ideate and Capture both benefit from the sharpened brief.
- `--no-ideate` and `--grill` are independent flags — either, both, or neither.

### Updated `go.md` Orchestration

```
Verify → [Audit, if verify passes] → Run → Log
```

- Audit runs automatically after verify scores >= 90%.
- No flag needed — always-on.
- If audit finds issues it can't auto-fix, it reports them but does not block the run.
- If `--force` is used (verify < 90%), audit still runs on whatever REQs exist.

### Standalone Invocation

- `/do-work question UR-NNN` — run the user grill anytime.
- `/do-work audit UR-NNN` — run the REQ grill anytime.

### What Doesn't Change

- Intake, Ideate, Capture, Verify, Run, Log — all unchanged internally.
- Capture already reads `input.md` fully, so it picks up `## Clarifications` automatically.
- Verify's scoring logic stays the same — audit is a post-verify step.
- File structure unchanged — no new folders, no new file types beyond the two agent files.

---

## Questioning Philosophy — Shared Principles

Both agents share interrogation principles, adapted for their context:

1. **Grounded, not generic.** Every question references specific language from the brief or REQ. Never "have you considered error handling?" — always "you said 'save the form data' — what should happen if the save fails mid-way?"

2. **One branch at a time.** Walk a single thread of ambiguity to resolution before opening the next.

3. **Falsifiability test.** The core question for every acceptance criterion: "Could I write a test that definitively proves this passes or fails?" If not, the criterion is too soft.

4. **Brief as source of truth.** Neither agent invents requirements. Question extracts what the user already knows. Audit sharpens what capture already decomposed. Neither adds scope — they add precision.

5. **Diminishing returns awareness.** Question stops when remaining ambiguities are low-value. Audit doesn't nitpick REQs that are already sharp. Both respect the 80/20.

6. **Multiple choice where possible.** For user-facing questions, structured choices are faster than open-ended prompts.

---

## Updated Full Pipeline

```
Intake
  |
  v
[Question] <-- opt-in (--grill or standalone)
  |
  v
Ideate
  |
  v
Capture
  |
  v
Verify (score >= 90%?)
  |
  v
[Audit] <-- always-on, auto-fix + report
  |
  v
Run (TDD loop)
  |
  v
Log
```

---

## File Inventory

| File | Type | New/Modified |
|------|------|-------------|
| `agents/question.md` | Agent | New |
| `agents/audit.md` | Agent | New |
| `agents/start.md` | Agent | Modified (add `--grill` flag support) |
| `agents/go.md` | Agent | Modified (add audit step after verify) |
| `SKILL.md` | Skill definition | Modified (document new commands and flags) |
