# Design — Retro Ledger Learning (`/do-work retro`)

> Design spec for UR-035 R3 / Gap E. Implementation spec for REQ-217 (rollup
> script + retro agent) and REQ-218 (routing + capture injection). Path-unit
> parent: REQ-215. Sibling design doc: `docs/design/ur-closure.md` (REQ-210).
>
> **Status:** design — decisions only. No code or agent files ship from this REQ.

The do-work ledger is currently write-only. `lib/run-ledger.sh` records model,
cost, result, review outcome, retry-adjacent data and changed-vs-declared files
into `.do-work/runs/RUN-NNN.yml`, and `lib/file-feedback.sh` emits feedback
fingerprints — but nothing in the system ever reads any of it. This design turns
that exhaust into a per-project learning loop: a deterministic rollup
aggregates the ledger, a judgment agent interprets the aggregate into bounded,
capture-facing guidance, and capture consumes that guidance as advisory context
during decomposition (exactly as it already consumes `ideate.md`).

The split follows the house pattern: arithmetic in tested bash
(`lib/retro-rollup.sh`, modelled on `lib/coverage-rollup.sh`), judgment in an
agent (`agents/retro.md`). The feed-forward is advisory and never blocks, in the
manner of `agents/ideate.md` ("Do not block the pipeline. You are advisory.").

---

## 1. Inputs

Retro reads **only** local-repo artifacts: the run ledger, REQ files, feedback
fingerprints, and git metadata of the local repo. (See §6 Privacy/scope.)

### 1a. Ledger fields mined — `.do-work/runs/RUN-NNN.yml`

The schema is fixed by `lib/run-ledger.sh` (the writer). Retro consumes these
fields; everything else in the file is ignored.

| Field | Source line in writer | Used for |
|---|---|---|
| `req` | `req: $REQ_ID` | Join key back to the REQ file (shape, Files, ACs). |
| `ur` | `ur: ${UR_ID}` | Group runs by UR for per-UR aggregates. |
| `model` | `model: "$MODEL"` | Escalation analysis (`sonnet` vs `opus`). |
| `result` | `result: "$RESULT"` | Stop-reason classification (`done`, `verification-failing`, `blocked`, `ambiguous-criteria`, …). |
| `review_outcome` | `review_outcome: "$REVIEW"` | Pair with `result` to separate "done but review-flagged" from clean done. |
| `proof_status` | `proof_status: "$PROOF_STATUS"` | `proven` vs `unproven` rate per REQ shape. |
| `changed_files` | `write_list "changed_files"` | Footprint actual — compared against the REQ's declared `**Files:**`. |
| `started_at` / `ended_at` | timestamps | Recency weighting (recent runs weighted over old ones — see §2d). |

**Retry counts.** The ledger writer does not emit a dedicated retry field. Each
worker attempt that produces a ledger row is one run; a REQ that was retried
appears as **multiple `RUN-NNN.yml` rows sharing the same `req`**. Retro derives
the retry count per REQ as `count(rows where req == R) - 1`. (REQ-217 must not
invent a new ledger field for this — it is derived from existing rows. If a
future REQ adds an explicit `attempt:` field to the writer, retro should prefer
it, but the design does not depend on that change landing.)

**Changed-files vs declared Files.** For each ledger row, retro joins to the
REQ file (working/ or archive/) via `req`, extracts its `**Files:**` line, and
compares the declared set against `changed_files`. This is the footprint
under/over-prediction signal (§2c). The REQ-file `**Files:**` extraction reuses
the `extract_field`-style grep already proven in `coverage-rollup.sh`.

### 1b. Feedback fingerprints mined

Fingerprints are the stable dedup keys defined by `lib/file-feedback.sh`
(`<event-type>:<slug>:<n>:<hash>`). Retro mines occurrences of these event
types. The set is exactly the events the system already emits:

| Fingerprint event | Class (per file-feedback.sh) | What recurrence ≥2× tells capture |
|---|---|---|
| `footprint-miss` | system | Declared Files routinely understate reality for a REQ shape. |
| `verify-fail` | project | A REQ shape ships but fails runtime verification. |
| `ambiguous-criteria` | project | A REQ shape is under-specified at capture time. |
| `stale-slot` | system | Workers stall on a REQ shape (often oversized REQs). |
| `concurrent-conflict` | system | Two REQs touch overlapping files — footprint declarations collide. |

**Fingerprint source.** When `feedback.enabled` is true, fingerprints exist as
GitHub issues (filed by `file-feedback.sh`). Reading GitHub would violate the
local-only scope (§6) and require network/`gh`. Therefore retro does **not**
read GitHub. Instead, fingerprint *occurrences* are derived locally:

- `footprint-miss` — derived from the declared-vs-actual delta in §1a (a miss
  is any row where `changed_files ⊄ declared Files`). This is the authoritative
  local signal and needs no issue tracker.
- `verify-fail` — derived from ledger rows where `result == "verification-failing"`.
- `ambiguous-criteria` — derived from ledger rows where `result == "ambiguous-criteria"`.
- `stale-slot` / `concurrent-conflict` — derived from ledger rows where
  `result` records the stall/conflict, when present.

This keeps retro dependency-free and offline. The fingerprint *taxonomy* from
`file-feedback.sh` is reused as the vocabulary; the *occurrences* are recomputed
from the ledger so retro works on every project regardless of feedback config.

---

## 2. Patterns computed

All four are computed by `lib/retro-rollup.sh` as plain counts/rates/deltas (no
interpretation). Definitions below are the contract REQ-217 implements.

### 2a. Stop-reason frequency by REQ shape

- **Stop reason** = `result` field, with `review_outcome` appended when
  `result == done && review_outcome != passed` (so "done-but-flagged" is a
  distinct bucket from clean "done").
- **REQ shape** = a coarse bucket derived deterministically from the REQ file,
  NOT from lexical guessing of intent. The shape key is:
  `layer` (from `**Layer:**`) × `ac_count` bucket (`≤2`, `3-4`, `>4` acceptance
  criteria) × `files_count` bucket (`1`, `2-3`, `>3` declared files).
- **Output:** for each shape key, count of each stop reason, and a
  `stop_rate = (non-done outcomes) / (total runs for that shape)`.

### 2b. Sonnet→opus escalation rate and its triggers

- **Escalation** = a REQ whose ledger rows include at least one `model: opus`
  row (typically a later retry after a `sonnet` row).
- **Escalation rate** = `escalated REQs / total REQs that ran`.
- **Triggers** = the rollup correlates escalation against the §2a shape key and
  against retry count, emitting which shape buckets escalate most. The rollup
  reports the correlation as counts; *interpreting* it into a calibration rule
  ("`>4`-AC REQs escalate 60% of the time") is the agent's job (§5).

### 2c. Footprint under/over-prediction stats

Per REQ (joining ledger `changed_files` to the REQ's declared `**Files:**`):

- `under` — files in `changed_files` not in declared Files (under-prediction).
- `over` — files in declared Files never in any `changed_files` (over-prediction).
- `exact` — declared set == union of actual changed sets.
- **Output:** project-wide `under_rate`, `over_rate`, `exact_rate`, plus the
  top-N most-frequently-missed file globs (e.g. `lib/*.test.sh` missed on N of
  M lib REQs).

### 2d. Recurrence fingerprints (same failure ≥2×)

- A **recurrence** = the same `(fingerprint-event, shape-key)` pair appearing in
  ≥2 distinct REQs (or ≥2 attempts of one REQ).
- **Recency weighting:** runs in the last 30 days (by `ended_at`) count double
  toward recurrence ranking, so the calibration reflects current behaviour, not
  long-resolved historical noise. Weighting affects ranking only, not the raw
  counts the rollup also prints.
- **Output:** ranked list of recurring `(event, shape)` pairs with their weighted
  and raw counts.

### 2e. Empty-state contract

If `.do-work/runs/` is absent or empty, the rollup prints a single sentinel line
`runs=0` and exits 0 (mirroring `coverage-rollup.sh`, which exits 0 on no rows).
The agent renders "no run history yet" and writes **no** calibration file. This
satisfies REQ-215 AC: *"A project with no ledger entries gets a clean report,
not an error."*

---

## 3. The calibration artifact — `.do-work/state/calibration.md`

### 3a. Purpose and placement

A bounded, capture-facing block of project-specific guidance that capture injects
as advisory context during decomposition. It lives in `.do-work/state/`
alongside `active-milestone.md` / `milestones.md` (the directory capture already
ensures with `mkdir -p {project}/.do-work/state`). It is **gitignored** like the
rest of `.do-work/` — it is per-project runtime state, not source.

### 3b. Size bound and regeneration rule (anti-growth)

- **Hard bound: ≤30 lines of guidance** (excluding the header and the metadata
  footer). The agent emits at most the top **8** guidance bullets, ranked by
  recurrence weight (§2d). If more than 8 candidate rules exist, only the
  highest-weighted 8 are written; the rest are dropped, not queued.
- **Regenerated, never appended.** Each `/do-work retro` run **overwrites**
  `calibration.md` in full from the current ledger state. There is no merge with
  the prior file. This is the structural guarantee that the file cannot grow
  unbounded across runs — a rule that no longer recurs simply disappears on the
  next regeneration. REQ-217 must `>` (truncate-write), never `>>` (append).
- The rollup is the data source; the **bound is enforced by the agent** when it
  writes the file (judgment about which 8 rules matter most — see §5).

### 3c. Format

```markdown
# Calibration — <project name>

> Auto-generated by `/do-work retro`. Advisory input for capture only.
> Regenerated in full each retro run — do not edit by hand.

## Capture guidance

- <one-line, imperative, project-specific rule>
- ...

<!-- retro-meta
generated_at: <ISO-8601>
runs_analyzed: <N>
window: all-time (recent-30d weighted)
top_recurrences: <event:shape (weighted-count)>, ...
-->
```

Rules: each guidance bullet is one line, imperative, names a concrete REQ shape
or file pattern and the historical signal that justifies it. The `retro-meta`
HTML comment lets capture (and a human) see provenance without it counting
toward the 30-line guidance bound.

### 3d. Worked example

```markdown
# Calibration — do-work

> Auto-generated by `/do-work retro`. Advisory input for capture only.
> Regenerated in full each retro run — do not edit by hand.

## Capture guidance

- REQs touching `lib/*.sh`: always include the matching `*.test.sh` in **Files:** — footprint under-predicted on 5 of 6 lib REQs.
- Split REQs with >4 acceptance criteria — historical stop rate 40% (4 of 10 stalled or went verification-failing).
- `agents/*.md` REQs with >3 declared files escalate sonnet→opus 60% of the time — size them down or start them on opus.
- Doc-conflict-fix REQs (single agent file, ≤2 ACs) run clean — keep them small and parallel-safe.

<!-- retro-meta
generated_at: 2026-06-12T02:00:00Z
runs_analyzed: 14
window: all-time (recent-30d weighted)
top_recurrences: footprint-miss:lib/≤2AC/1file (10), stop:agents/>4AC/>3file (6)
-->
```

**Validation against §3c spec (field-by-field):**

| Spec element (§3c) | Example satisfies it? |
|---|---|
| `# Calibration — <project name>` header | `# Calibration — do-work` ✓ |
| Advisory + "regenerated in full" notice | both notice lines present ✓ |
| `## Capture guidance` section | present ✓ |
| Each bullet: one line, imperative, names shape/file + signal | 4 bullets, all conform ✓ |
| ≤30 guidance lines / ≤8 bullets (§3b) | 4 bullets ✓ (within bound) |
| `retro-meta` comment with `generated_at`, `runs_analyzed`, `window`, `top_recurrences` | all four present ✓ |

This satisfies REQ-216 Verification Step 2 (worked example validates against its
own format spec, handoff spec → example).

---

## 4. Feed-forward wiring

### 4a. Capture reads calibration.md as advisory context

Capture already has the exact slot and the exact phrasing pattern. In
`agents/capture.md` Step 1 ("Read the brief"), ideate observations are kept "as
advisory input for decomposition — they inform your work but are not requirements
to blindly follow." Calibration is wired identically:

- **Where:** `agents/capture.md` Step 1, immediately after the `ideate.md` read.
- **What:** "Read `{project}/.do-work/state/calibration.md` if it exists. Treat
  its guidance bullets as advisory calibration — they inform how you size REQs,
  scope `**Files:**`, and split acceptance criteria, but they never block
  decomposition and are not hard requirements. If the file is absent (no retro
  has run yet), continue without it."
- **Non-blocking guarantee:** like ideate, calibration is *informs, never blocks*.
  No capture branch may fail or halt because calibration is missing, stale, or
  contradicts the brief. The brief always wins. This is the REQ-218 change.

### 4b. Model selection consulting escalation stats — deferred (with reason)

The rollup computes escalation stats (§2b), and the calibration example shows
them surfacing as a capture-facing rule ("size down or start on opus"). That is
the **only** consumer wired now: model-selection influence flows *through capture's
sizing decisions and the REQ's `**Size:**`/`**Files:**`*, not through a direct
runtime hook into the orchestrator's model picker.

Auto-tuning the orchestrator's model selection from live escalation stats is
**deferred**. Rationale:

1. It couples retro to the run loop's hot path; this design keeps retro a cold,
   offline, capture-time advisor.
2. R13 (backlog intelligence) already proposes `**Size:**` as the primary
   model-escalation input — escalation calibration should feed *that* lever, not
   a second parallel one, to avoid two competing model-selection signals.
3. The advisory-only path is safe to ship without changing execution semantics.

REQ-217/218 implement §4a only. A future REQ may wire escalation stats into model
selection once `**Size:**` (R13) lands; this doc names the seam but does not open
it.

---

## 5. Split of labour — script vs agent

Deterministic arithmetic lives in `lib/retro-rollup.sh` (tested bash, modelled on
`lib/coverage-rollup.sh`). Interpretation lives in `agents/retro.md`. The split
is exhaustive — every output below is owned by exactly one side.

### 5a. `lib/retro-rollup.sh` outputs (deterministic — REQ-217 builds + tests)

Emits machine-readable lines (one fact per line, `coverage-rollup.sh` style) to
stdout. No prose, no ranking-by-judgment, no file writes.

| Output | Definition |
|---|---|
| `runs=N` | total ledger rows analyzed (`runs=0` sentinel on empty — §2e). |
| `stop <shape-key> <reason>=<count>` | stop-reason frequency by shape (§2a). |
| `stop_rate <shape-key>=<ratio>` | non-done ratio per shape (§2a). |
| `escalation_rate=<ratio>` | sonnet→opus escalation rate (§2b). |
| `escalation <shape-key>=<count>` | escalations per shape (§2b triggers). |
| `footprint under=<r> over=<r> exact=<r>` | declared-vs-actual rates (§2c). |
| `footprint_missed <glob>=<count>` | top-N most-missed file globs (§2c). |
| `recurrence <event>:<shape> weighted=<w> raw=<n>` | ranked recurrences (§2d). |

These are exactly the facts a `retro-rollup.test.sh` can assert against fixture
`RUN-NNN.yml` files — pure functions of the input, no clock except the
recency-window boundary (which the test pins via a fixed `ended_at` and an
injectable "now").

### 5b. `agents/retro.md` outputs (judgment — REQ-217 builds)

| Output | Why it is judgment |
|---|---|
| The rendered `/do-work retro` report (prose sections). | Choosing what to surface and how to phrase it. |
| Selecting the **top 8** guidance bullets from candidate rules. | Ranking relevance/actionability beyond raw weight. |
| Translating a rate into an imperative capture rule. | "stop_rate=0.4 on >4-AC shape" → "Split REQs with >4 ACs". |
| Writing/overwriting `.do-work/state/calibration.md` (truncate-write, ≤30 lines). | Enforcing the bound and regeneration rule (§3b). |
| Rendering the clean "no run history yet" report on `runs=0`. | Empty-state UX, no file written (§2e). |

**One-line contract:** the script says *what happened* (counts, rates, deltas);
the agent says *what to do about it* (bounded capture guidance) and renders it.

---

## 6. Privacy / scope note

Retro is strictly local and read-mostly:

- **Reads only** `.do-work/` artifacts (`runs/RUN-NNN.yml`, REQ files in
  `working/` and `archive/`) and **git metadata of the local repo** (e.g. commit
  timestamps if used for recency — though `ended_at` from the ledger is the
  primary recency source, so even git reads are optional).
- **Does not** read GitHub issues, call `gh`, hit the network, or read any file
  outside the project working tree. Fingerprint occurrences are recomputed
  locally from the ledger (§1b) precisely so no remote read is needed.
- **Writes only** one file: `.do-work/state/calibration.md` (gitignored runtime
  state), and that only via the agent, regenerated in full.
- No source code, diffs, or commit messages are mined — only the structured
  ledger fields and REQ headers. Nothing leaves the machine.

This keeps retro safe to run on any project, online or offline, with no
credentials and no side effects beyond one gitignored state file.

---

## Implementation handoff

| REQ | Builds | Touches |
|---|---|---|
| REQ-217 | rollup script (deterministic, §5a) + retro agent (judgment, §5b) | `lib/retro-rollup.sh`, `lib/retro-rollup.test.sh`, `agents/retro.md` |
| REQ-218 | `/do-work retro` routing + capture injection (§4a) | `SKILL.md` (subcommand routing), `agents/capture.md` (Step 1 read) |

Both children depend on this document's decisions and must not re-litigate the
script/agent split (§5), the size bound/regeneration rule (§3b), the deferral of
model-selection auto-tuning (§4b), or the local-only scope (§6).
