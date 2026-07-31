# Skill best-practices findings — do-work (ORI-5 / ORI-6)

**Issue:** ORI-5 (inventory) · ORI-6 (confirm + N/A completeness) · **UR:** UR-001  
**Scope:** Inventory only — progressive disclosure, description routing, lean SKILL.md, references/scripts layout, anti-patterns, Linear store consistency.  
**Out of scope:** Structural migration (no splits, no renames, no agent body rewrites in this REQ).

Measured in worktree `.worktrees/req-ori-5` on branch `req/ORI-5` (base `linear`); confirmed on `req/ORI-6` with explicit N/A table (ORI-6 AC).

---

## 1. Rubric (which checklist items apply)

Source: `effective-agent-skills` (`~/.grok/skills/effective-agent-skills/SKILL.md`) — progressive disclosure, description routing, lean body, references one-level deep, anti-patterns, ship checklist.

| Rubric item | Applies? | Notes for do-work |
|-------------|----------|-------------------|
| **L1 description routing** (what + when + differentiator; no how-summary) | Yes | Frontmatter description is the only discovery signal |
| **L2 lean SKILL.md** (activation budget; aim well under ~5k tokens) | Yes | SKILL.md is the always-loaded body on match |
| **L3 progressive disclosure** (`references/`, on-demand load) | Yes | Skill has no `references/`; detail lives in `agents/` + `docs/` |
| **`scripts/` for determinism** (fragile/repetitive → code) | Partial | Determinism lives in `lib/*.sh` (project shape), not skill-standard `scripts/` |
| **Bash-first, prose-second** | Yes | Many good command examples; also large procedural prose |
| **One skill, one concern** / no mega-skill | Yes | do-work is a full PM loop (intake→archive) in one skill |
| **No human-facing docs inside skill folder** | Yes | README / CHANGELOG / CONTRIBUTING at skill root |
| **Relative paths only** | Yes | Prefer `{project}` / relative; some `~/.claude/skills` examples |
| **State-check before action** | Yes | Strong (conformance scan, install check, Load Config) |
| **Validation loops** | Yes | TDD checkpoints, review gate, archive-integrity, verify |
| **Output formats documented** | Yes | Return reports, checkpoint YAML, claim blocks |
| **Failure modes documented** | Yes | Hard-stops, stopper reasons, dual-write bans |
| **Keep references one level deep** | Yes | SKILL → agents/* is one hop; linear.md internal path chains are deep |
| **No dual-write / single source of truth** (project multi-tracker rule) | Yes | Port contract: Linear sole store when `backend: linear` |
| **Ship checklist** (name match, triggers, relative paths, compose, VCS) | Yes | Spot-check only |

### N/A checklist items (no silent omission)

Items from `effective-agent-skills` that do **not** apply as hard gates or ship criteria for this inventory. Each row is deliberate — not omitted.

| Checklist / guide item | Status | One-line rationale |
|------------------------|--------|--------------------|
| Pattern A “30–80 line skill” length target | **N/A** | do-work is intentionally Pattern B (process + large `lib/` surface); line-count budget still measured under L2, not Pattern A. |
| Security checklist (third-party skill install audit) | **N/A** | Evaluating first-party do-work package, not installing untrusted third-party skills. |
| `assets/` folder (templates/fonts/static) | **N/A** | No static skill assets required; templates live under project/skill `templates/` when present, not skill-standard `assets/`. |
| `disable-model-invocation` frontmatter | **N/A** | Skill is meant to auto-route on PM/backlog phrases; manual-only flag would break primary UX. |
| “Don’t write style-only variants” anti-pattern | **N/A** | do-work is a full workflow skill, not a tone/format preference pack. |
| “Don’t bundle library code” (paste npm/pip sources into skill) | **N/A** | Helpers are project shell under `lib/`, not vendored third-party library source trees. |
| “Defer to `--help` for completeness” | **N/A** as ship gate | Most agent ops are Markdown sequences + MCP rediscovery, not a single CLI with `--help`; `lib/*.sh` scripts are thin and documented in agents. |
| Ship: tested with weak and strong models | **N/A** this REQ | Inventory/docs only; model matrix testing is out of scope for ORI-5/ORI-6 (belongs to runtime eval, not findings file). |
| Ship: eval suite of trigger prompts | **N/A** this REQ | No trigger-eval harness in this inventory; routing quality noted qualitatively under F6 only. |
| Compose interfaces between *separate* published skills | **N/A** short-term | Product is one skill + `lib/`; multi-skill composition is a future migrate option (see §4 item 6), not current packaging. |

---

## 2. Metrics (re-measured)

```text
$ wc -l SKILL.md agents/tracker/linear.md agents/run.md
     767 SKILL.md
    2113 agents/tracker/linear.md
    1433 agents/run.md
```

| Path | Lines | Words | ~Tokens (words×1.3) |
|------|------:|------:|--------------------:|
| `SKILL.md` | 767 | 6983 | ~9077 |
| `agents/tracker/linear.md` | 2113 | 21609 | ~28091 |
| `agents/run.md` | 1433 | 15597 | ~20276 |
| `agents/capture.md` | 819 | 8726 | ~11343 |
| `agents/run-worker.md` | 595 | 6363 | ~8271 |
| `agents/upgrade.md` | 575 | 3469 | ~4509 |
| `agents/tracker/port.md` | 481 | 3540 | ~4602 |
| `agents/tracker/markdown.md` | 412 | 2806 | ~3647 |
| `agents/config.md` | 264 | 3790 | ~4927 |
| All `agents/**/*.md` (23 files) | ~9848 | — | — |
| `lib/*.sh` | 62 scripts | — | (determinism home) |

**Layout gaps (skill standard):**

| Expected (effective-agent-skills) | Actual |
|-----------------------------------|--------|
| `references/` | **Missing** |
| `scripts/` | **Missing** (helpers under `lib/`) |
| Lean `SKILL.md` | 767 lines / ~9k tokens (over L2 budget) |

**Activation stack estimate (full body reads, worst case):**

| Scenario | Files typically forced into context | ~Tokens |
|----------|-------------------------------------|--------:|
| Markdown `/do-work run` | SKILL + config + port + markdown + run + run-worker | ~50.8k |
| Linear `/do-work run` | SKILL + config + port + **linear** + run + run-worker | ~75.2k |

**Human-facing docs at skill root:** `README.md` (369), `CHANGELOG.md` (154), `CONTRIBUTING.md` (303) — anti-pattern vs “skills are for agents.”

---

## 3. Findings (ordered: identify → migrate later)

Findings are ranked so **identify / measure / document** work precedes **split / migrate** work. Severity: `blocker` | `major` | `minor`. Fix class: `docs` | `split` | `code` | `leave`.

### Identify-first (do before any structural migrate)

| ID | Title | Severity | Evidence | Fix class |
|----|-------|----------|----------|-----------|
| F1 | **SKILL.md far exceeds L2 activation budget** | **blocker** | 767 lines, ~6983 words, ~9k tokens vs guide “activation &lt;5k tokens”. Body includes full Quick Reference, tracker essay (§ Tracker backends), parallel execution design summary, REQ schema, and ~315 lines of per-subcommand stubs that restate agent files. | **split** (later): keep routing + minimal stubs in SKILL; move schema/parallel/tracker essays to `references/` or keep only pointers to `agents/*`. |
| F2 | **`agents/tracker/linear.md` is a mega-file (runtime + path history)** | **blocker** | 2113 lines / ~28k tokens. Opens with path-unit scaffolding (REQ-288…REQ-301 design diary) then operational CRUD, claim, milestone, migration sequences. Loading backend=`linear` forces agents to absorb historical path narrative + full op catalog. | **split** (later): operational sequences vs path-history/design appendix; optional `references/linear-*.md` one level deep from a short `linear.md` index. |
| F3 | **No `references/` progressive-disclosure tree** | **blocker** | `ls references` → missing. Detail is either inlined in SKILL or in always-linked fat `agents/*.md`. L3 (“load only when needed”) has no standard hook; agents that follow “read X in full” load entire files. | **split** (later): introduce `references/` for schema, parallel, Linear ops, milestone; SKILL/agents point with just-in-time “read when …”. |
| F4 | **Worst-case Linear run stack ~75k tokens of instruction** | **blocker** | Stack SKILL+config+port+linear+run+run-worker ≈ 57.9k words. Context pressure → missed hard-stops, partial sequence following, dual-write “safety” inventiveness. | **split** + **docs**: shrink mandatory full-file reads; index + section pointers; keep hard rules in a short always-loaded contract. |
| F5 | **Markdown path assumptions still dominate SKILL subcommand stubs** | **major** | SKILL subcommands hardcode `.do-work/user-requests/`, backlog `REQ-*.md`, `working/` (≈27 matches in SKILL alone; `agents/run.md` ≈58). Under `tracker.backend: linear`, work-item truth is Linear — stubs can steer agents toward markdown list/confirm steps before backend load. Phase agents *do* restate Load Config + port path, but SKILL is read first. | **docs** first (clarify “paths below are markdown default; Linear uses port ops”), then **split** stubs so store I/O is never specified in SKILL. |
| F6 | **Description routing is OK but incomplete for multi-tracker** | **major** | Frontmatter what+when+triggers present. Still says “file-based autonomous loop” / “REQ files” only — weak differentiator vs Linear mode and vs generic task skills. No explicit triggers for “linear backlog”, “tracker.backend”, “migrate to Linear”. Risk: wrong mental model at L1. | **docs**: extend description what/when/differentiator; keep no how-summary. |
| F7 | **Human-facing docs live inside the skill package** | **major** | Root `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (~826 lines). Rubric: “No human-facing docs inside the skill folder.” Agents may load README instead of SKILL/agents. (Acceptable if package is also a product repo — still a skill-ship smell.) | **leave** if dual product+skill is intentional; else **docs** relocate human guides outside install path or mark “humans only / do not load”. |
| F8 | **Monolithic mega-skill (many concerns in one folder)** | **major** | One skill covers install, intake, capture, verify, run, review, close, retro, log, upgrade, multi-tracker, parallel, milestones. Rubric anti-pattern: “Don’t write monolithic mega-skills.” Composition would be multiple skills + shared substrate (already partially `lib/` + `.do-work/`). | **leave** short-term (product identity); long-term **split** only after inventory of phase boundaries (this doc). |
| F9 | **Missing skill-standard `scripts/` name (uses `lib/`)** | **minor** | 62 shell helpers under `lib/` — correct determinism placement, nonstandard vs agentskills.io `scripts/`. Install and SKILL already teach `lib/`. | **leave** (project convention) or **docs** note “`lib/` ≡ scripts/”. |
| F10 | **Absolute / home-path examples in agent docs** | **minor** | e.g. SKILL “loaded from `~/.claude/skills/do-work/`”; run.md example `/Users/you/.claude/skills/do-work`. Rubric prefers relative + placeholders. Functional, slightly host-specific. | **docs** |

### Linear dual-write / phase-agent path gaps

| ID | Title | Severity | Evidence | Fix class |
|----|-------|----------|----------|-----------|
| F11 | **No dual-write policy is documented and repeated — treat as intentional strength** | **minor** (positive) | SKILL, `port.md`, `linear.md`, `markdown.md`, capture/run/run-worker hard-stop “no silent markdown fallback”. Context pack: “No dual-write.” | **leave** — do not “fix” by adding mirrors. |
| F12 | **`linear.md` path-unit diary mixed with live op sequences** | **major** | Sections `## Path: Linear MCP capability spike (REQ-288)` … migration REQ-300/301 sit above/ beside production sequences (CRUD, claim, hard-stop). Agents instructed to “read linear.md” get implementation archaeology + matrix “unavailable” narratives that can undercut live MCP use. | **split** later: runtime ops file vs `references/linear-path-history.md` or archive under `docs/design/`. |
| F13 | **Phase agents wire Load Config + port — consistent** | **minor** (positive / residual risk) | All phase agents under `agents/*.md` mention `tracker.backend` / Load Config / tracker. Residual: **order-of-read** risk if SKILL stub runs markdown filesystem checks before agent file (F5). | **docs** (ordering: config → port → backend → then any store I/O). |
| F14 | **Within-Linear “dual-write” of deps (relations + body)** | **minor** | `linear.md`: `set_blocked_by` may write native relations **and** body `**Depends on:**` mirror. This is **not** markdown dual-write; still two Linear representations — document authority (relations win) is present; keep explicit in any split. | **leave** / **docs** clarify in short contract card. |
| F15 | **Markdown historical trees after migrate are easy to re-activate by mistake** | **major** | Post-cutover: local UR/REQ trees remain as **read-only history** while `backend: linear`. SKILL install/list steps and many agents still name those paths. Conformance/upgrade document ignore rules; a rushed agent can still `ls .do-work/` and treat files as live. | **docs** + later **code** (conformance detector / guardrails already partial — extend messaging in SKILL stubs). |
| F16 | **`lib/` remains markdown-centric under Linear (by design)** | **minor** | linear.md: “No Linear-aware bash in lib/ (v1)”. Port ops are agent/MCP sequences. Gap: workers must not call `claim-req.sh` etc. as store of truth when backend=linear — stated in agents; easy to miss under token pressure (F4). | **docs** first; optional **code** thin wrappers later (out of inventory scope). |

### Ship-checklist snapshot

| Checklist item | Status |
|----------------|--------|
| Frontmatter `name` matches folder (`do-work`) | Pass |
| Description what + when + triggers | Partial (F6) |
| Differentiator vs related skills | Weak |
| No human-facing docs in skill folder | Fail (F7) |
| No time-sensitive “as of …” rot | Pass (mostly) |
| Relative paths only | Partial (F10) |
| State-check before action | Pass |
| Validation loop | Pass |
| Output format | Pass |
| One concern / composes cleanly | Fail as pure skill (F8); pass as product |
| Version controlled | Pass |

---

## 4. Recommended migrate order (after identify; not this REQ)

Do **not** execute here — sequencing only so later REQs stay identify-first.

1. **Contract card** (docs): one-page “always load” rules — backend resolution, no dual-write, hard-stop, claim protocol, commit footers.  
2. **SKILL.md diet** (split): Quick Reference + agent index + “read agent file” only; move schema/parallel/tracker essays to `references/`.  
3. **Linear runtime extract** (split): `linear.md` → short index + `references/linear/{crud,claim,milestone,migrate}.md`; archive path-unit diary.  
4. **SKILL subcommand path neutrality** (docs/split): no markdown filesystem prechecks in stubs; defer store I/O to phase agent after port load.  
5. **Description refresh** (docs): multi-tracker what/when/differentiator.  
6. **Optional composition** (leave until 1–5): only if still over budget — phase skills with shared `lib/` substrate.  
7. **Human docs packaging** (leave/docs): decide product-repo vs pure skill install layout.

---

## 5. Acceptance map (ORI-5 / ORI-6)

| AC | How satisfied |
|----|----------------|
| Rubric explicit | §1 |
| Each finding: title, severity, evidence, fix class | §3 tables (≥5; F1–F16) |
| SKILL.md line count, top agent sizes, missing references/scripts | §2 |
| Linear dual-write / phase-agent path gaps | F11–F16 |
| Identify-first before migrate | §3 order + §4 explicit sequencing |
| Non-applicable checklist items documented as N/A | §1 **N/A checklist items** table (no silent omission) |
| No structural migration in this REQ | Findings file only |

---

## 6. Verification commands (operator)

```bash
# File exists with severity column
test -s docs/skill-best-practices-findings.md
rg -n 'severity|blocker|major|minor' docs/skill-best-practices-findings.md

# Metrics cited above (re-run anytime)
wc -l SKILL.md agents/tracker/linear.md agents/run.md
```
