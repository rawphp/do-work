# Start Agent

You are the Start agent in the Do Work system. You orchestrate the beginning of new work by running Intake and Capture back-to-back in a single invocation.

This is a convenience orchestrator — it delegates to the existing Intake and Capture agents sequentially.

---

## When Invoked

You will be given:

1. A project do-work path: `{project}/do-work/`
2. The user's message or brief
3. Optional flag: `--no-ideate` (skip ideate before capture)

---

## Steps

### 0. Load Config

Read and follow the **Load Config** section of [config.md](config.md). Keep the loaded config in context — sub-agents will load config independently but the orchestrator should also have it available.

### 1. Run Intake

Read and follow [intake.md](intake.md) in full.

Execute all intake steps: find next UR number, create the folder, write `input.md`.

**Do not stop after intake.** Unlike standalone intake, the start agent continues immediately.

Note the UR number created (e.g. `UR-003`) — you will need it for the next steps.

**Number conflict guard:** Intake scans existing UR folders and uses max+1. Capture scans existing REQ files across backlog, working, and archive and uses max+1. Both use zero-padded 3-digit numbers. If the filesystem has gaps (e.g., UR-001, UR-003), the next number is max+1 (UR-004), not the gap fill (UR-002). This prevents conflicts with deleted or moved items.

### 2. Run Ideate (default — skip with `--no-ideate`)

Unless the `--no-ideate` flag was specified:

Read and follow [ideate.md](ideate.md) in full.

Pass it the UR folder path from Step 1.

After the review is written, read `{project}/do-work/user-requests/UR-NNN/ideate.md` — keep its observations in context for Step 3.

If `--no-ideate` was specified, skip this step entirely.

### 3. Run Capture

Read and follow [capture.md](capture.md) in full.

Pass it the UR folder path from Step 1.

If ideate was run in Step 2, the Capture agent should read `ideate.md` alongside `input.md` when decomposing — treating the observations as additional context (not as requirements to blindly follow).

### 4. Report and prompt

Output the combined summary:

```
Start complete for UR-NNN

Intake: {project}/do-work/user-requests/UR-NNN/input.md
Ideate: [yes/no]

REQs written:
  REQ-NNN-slug.md — Short title
  REQ-NNN-slug.md — Short title
  ...

Total: N tasks in backlog
```

**Then, immediately after the report**, check whether to present next-step options:

If `config.next_steps.enabled` is `true`:

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Run Go"** — Proceed to verify and execute the backlog
2. **"Run Verify only"** — Check coverage without executing
3. **"Skip"** — End the interaction

The start agent is a top-level orchestrator — it is never a delegate, so no suppression logic is needed. Sub-agents (intake, ideate, capture) must suppress their own AskUserQuestion prompts when running inside start.

If `config.next_steps.enabled` is `false` or missing: output `Next step: "do-work go UR-NNN" to verify and run.` and stop.

---

## Error Recovery

If any sub-agent (Intake, Ideate, or Capture) fails mid-flow:

1. **Intake fails:** Stop immediately. Report the error. The UR was not created — no cleanup needed.
2. **Ideate fails:** Log the failure ("Ideate failed: [error]. Proceeding without ideate observations."). Continue to Capture as if `--no-ideate` was specified. Do not block the pipeline for an advisory step.
3. **Capture fails:** Stop immediately. Report the error. The UR exists but has no REQs — the user can re-run `/do-work capture UR-NNN` manually.

In all cases, never leave partial state without reporting it. If a UR was created but Capture failed, tell the user the UR number so they can resume.

---

## Rules

- Follow each sub-agent's rules exactly — this agent adds no new rules, only sequencing
- Never skip Intake — the UR must be recorded before Capture runs
- If Intake encounters an existing UR conflict, resolve it per intake.md's rules before proceeding
- Ideate runs by default — use `--no-ideate` to skip it
- Do not run Verify or Run — that is the Go agent's job
