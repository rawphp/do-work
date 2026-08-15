# Start Agent

You are the Start agent in the Do Work system. You orchestrate the beginning of new work by running Intake and Capture back-to-back in a single invocation.

This is a convenience orchestrator — it delegates to the existing Intake and Capture agents sequentially.

---

## When Invoked

You will be given:

1. A project do-work path: `{project}/.do-work/`
2. The user's message or brief
3. Optional flags:
   - `--no-ideate` (skip ideate before capture)
   - `--no-layers` (skip layer-coverage check for this invocation only — passed through to capture)

---

## Steps

### 0. Load Config

Read and follow the **Load Config** section of [config.md](config.md). Keep the loaded config in context — sub-agents will load config independently but the orchestrator should also have it available.

### 0a. Tracker load path

Work-item storage (Issues, REQs, decisions, verify/close reports, run notes) goes **only** through named tracker port ops after config is loaded:

1. Resolve effective `tracker.backend` (missing/empty/whitespace → `markdown`).
2. Read `agents/tracker/port.md` (shared op catalog + rules).
3. Read `agents/tracker/<backend>.md` (e.g. `markdown.md`, `linear.md`, `sqlite.md`, or `do-work-io.md`).
4. For work-item storage, call **only** named port ops from that backend file — never raw `.do-work/REQ-*` paths or raw Linear tools outside the backend doc.

**Hard rules:**
- **No silent fallback** from `linear`, `sqlite`, or `do-work-io` to `markdown`. If backend is `linear`, `sqlite`, or `do-work-io`, do not substitute Issue/REQ markdown as the store.
- If backend resolves to **`linear`** but `agents/tracker/linear.md` is **missing or unreadable**, **hard-stop** with setup instructions (restore the Linear backend doc / connect Linear skill). Never fall through to markdown paths.
- If backend resolves to **`do-work-io`** but `agents/tracker/do-work-io.md` is missing/unreadable, or MCP/PAT/project is unusable → **hard-stop**. Never fall through to markdown, Linear, or sqlite.
- Markdown backend: ops map — **invoke** coordination scripts as `bash {skill-root}/lib/...` after Load Config step 8 resolves `$SKILL_ROOT`; **catalog identity** remains `lib/*.sh` in `markdown.md` — use those ops; do not re-implement store details here.

### Start store — backend branch (ORI-9)

| Backend | Intake home | Ideate home | Capture home |
|---------|-------------|-------------|--------------|
| **linear** | **`create_ur`** → Issue Project Milestone; report Linear ids | **`append_ideate`** on that milestone; **`read_ur`** for brief/ideate | **`create_req`** Issues on product Project + Issue milestone; **`list_reqs_for_ur`** to list |
| **markdown** | Local `user-requests/UR-NNN/input.md` | Local `ideate.md` | Local `REQ-*.md` backlog files |
| **sqlite** | `create_ur` via dw-db | `append_ideate` via dw-db | `create_req` / `list-reqs` via dw-db — **no** live `REQ-*.md` / `user-requests/` |
| **do-work-io** | **`create_ur`** (`ur.create`) via `agents/tracker/do-work-io.md`; report Issue slug | **`append_ideate`** (`ur.append-ideate`); **`read_ur`** (`ur.get`) | **`create_req`** / **`list_reqs_for_ur`** (`req.create` / `req.list`) — **no** live `REQ-*.md` / `user-requests/` |

When backend is **`linear`**, start **must not** require or create `.do-work/user-requests/` as the work-item store. Hard-stop if Linear MCP unusable — never silent markdown fallback.

When backend is **`sqlite` (1S)**, start uses dw-db only (`create_ur` / capture path via port). Hard-stop if sqlite unusable — never silent markdown fallback.

**When effective backend is `do-work-io` (1D):** sole store is do-work.io via `agents/tracker/do-work-io.md` MCP tools. Do **not** dual-write `user-requests/` or `REQ-*.md`. Hard-stop if MCP/PAT/project unusable — never silent markdown fallback.

### 1. Run Intake

Read and follow [intake.md](intake.md) in full.

- **Markdown:** execute intake steps: find next Issue number, create the folder, write `input.md`.
- **Linear:** execute intake **Linear path** only — port op **`create_ur`** (no local folder). Note **Issue slug + product project id/name + milestone id/name** from the intake report.

**Do not stop after intake.** Unlike standalone intake, the start agent continues immediately.

Note the Issue number created (e.g. `UR-003`) — you will need it for the next steps. Under Linear, also keep the milestone id in context.

**Number conflict guard:**
- **Markdown:** Intake scans existing UR folders and uses max+1. Capture scans existing REQ files across backlog, working, and archive and uses max+1. Both use zero-padded 3-digit numbers. If the filesystem has gaps (e.g., UR-001, UR-003), the next number is max+1 (UR-004), not the gap fill (UR-002).
- **Linear:** Issue slugs come from **`create_ur`** milestone scan; REQ ids are **Linear issue identifiers** allocated by Linear (no local `REQ-NNN`).

### 2. Run Ideate (default — skip with `--no-ideate`)

Unless the `--no-ideate` flag was specified:

Read and follow [ideate.md](ideate.md) in full.

Pass it:
- **Markdown:** the Issue folder path from Step 1
- **Linear:** the Issue slug (and milestone id if known) — not a local folder path

Ideate now ends with a mandatory interactive gate (Grill / Continue / Stop). Honor the gate's outcome:

- **Grill** chosen by user → ideate.md will already have invoked question.md inline. Continue to Step 3 (Run Capture) when ideate returns.
- **Continue** chosen by user (or empty input default) → Continue to Step 3 (Run Capture) when ideate returns.
- **Stop** chosen by user → **Halt the start orchestrator.** Do not run Capture.
  - **Markdown:** Output: `Start halted at ideate gate — revise UR-NNN/input.md and re-run start.`
  - **Linear:** Output: `Start halted at ideate gate — revise UR-NNN brief on Linear (Issue milestone) and re-run start.`
  - Return.

After ideate returns (and unless Stop was chosen), load ideate observations for Step 3:

- **Markdown:** read `{project}/.do-work/user-requests/UR-NNN/ideate.md`
- **Linear:** **`read_ur`** and use `## Ideate` (do not require local `ideate.md`)

If `--no-ideate` was specified, skip this step entirely (no gate runs).

### 3. Run Capture

Read and follow [capture.md](capture.md) in full.

Pass it:
- **Markdown:** the Issue folder path from Step 1
- **Linear:** the Issue slug (+ milestone id); capture uses **`read_ur`** / **`create_req`** — no local `input.md` required
- The `--no-layers` flag if it was set on the start invocation (capture reads it in its Step 2c)

If ideate was run in Step 2, Capture should treat ideate observations as additional context (not requirements to blindly follow) — from local `ideate.md` (markdown) or `## Ideate` via **`read_ur`** (linear).

### 4. Report and prompt

**Markdown report:**

```
Start complete for UR-NNN

Intake: {project}/.do-work/user-requests/UR-NNN/input.md
Ideate: [yes/no]

REQs written:
  REQ-NNN-slug.md — Short title
  ...

Total: N tasks in backlog
```

**Linear report (report Linear ids):**

```
Start complete for UR-NNN

Intake: Linear Issue milestone <milestone id/name> (product project <id/name>)
Ideate: [yes/no — ## Ideate on Issue milestone via append_ideate]

REQs written (Linear issue ids):
  ENG-123 — Short title
  ENG-124 — Short title
  ...

Total: N issues for UR-NNN
```

**Then, immediately after the report**, check whether to present next-step options:

If `config.next_steps.enabled` is `true`:

**Use the `AskUserQuestion` tool** (do NOT just print the options as text) with these options:

1. **"Run Go"** — Proceed to verify and execute the backlog
2. **"Run Verify only"** — Check coverage without executing
3. **"Skip"** — End the interaction

The start agent is a top-level orchestrator — it is never a delegate, so no suppression logic is needed. Sub-agents (intake, question, ideate, capture) must suppress their own AskUserQuestion prompts when running inside start.

If `config.next_steps.enabled` is `false` or missing: output `Next step: "do-work go UR-NNN" to verify and run.` and stop.

---

## Error Recovery

If any sub-agent (Intake, Ideate, or Capture) fails mid-flow:

1. **Intake fails:** Stop immediately. Report the exact error. The Issue was not created — no cleanup needed. Output: `"Start failed at intake: {error}. No Issue was created."`
2. **Question fails:** Output the failure to the user: `"Question failed: {error}. Proceeding without clarifications."` Continue to Ideate (or Capture if `--no-ideate`). Do not block the pipeline for an advisory step.
3. **Ideate fails:** Output the failure to the user: `"Ideate failed: {error}. Proceeding without ideate observations."` Continue to Capture as if `--no-ideate` was specified. Do not block the pipeline for an advisory step.
   - **Markdown:** do not leave a partial local `ideate.md` — if partially written, delete it before continuing.
   - **Linear:** do not invent a local `ideate.md` dual-write; partial milestone append failures → hard-stop / report per linear.md (leave remote state as-is for operator).
4. **Capture fails:** Stop immediately. Report the exact error and the Issue number so the user can resume. Output: `"Start failed at capture: {error}. UR-NNN was created but has no REQs. Resume with: /do-work capture UR-NNN"`

In all cases, never leave partial state without reporting it. If an Issue was created but Capture failed, tell the user the Issue number (and under Linear, the milestone id) so they can resume.

---

## Rules

- Follow each sub-agent's rules exactly — this agent adds no new rules, only sequencing
- Never skip Intake — the Issue must be recorded before Capture runs
- If Intake encounters an existing UR conflict, resolve it per intake.md's rules before proceeding
- Ideate runs by default — use `--no-ideate` to skip it
- Do not run Verify or Run — that is the Go agent's job
- **Linear:** no dual-write to `user-requests/`; intake reports Linear ids; hard-stop if MCP unusable
- **do-work-io:** no dual-write to `user-requests/` or Linear; intake reports Issue slug; hard-stop if MCP/PAT/project unusable


## Field traps (from field-lessons)

- **Prefer existing `.do-work/` (§21):** if `{project}/.do-work/config.yml` exists, use champion layout — do not create a sibling legacy `do-work/` tree.
- **Linear vs markdown capture (§8):** when config says `linear`, capture must create Linear Issue/REQs — do not leave markdown-only backlog.
- **Mockups (§32):** if the brief includes images, vision-read them and copy into `.do-work/evidence/UR-NNN/mockups/` before decomposition.
