# REQ-287: Wire phase agents to tracker load path


**UR:** UR-045
**Status:** done
**Created:** 2026-07-31
**Layer:** agents
**Entry point:** 
**Terminal state:** 
**Parent:** REQ-283
**Closure proof:** checkpoint:.do-work/runs#REQ-287 commit:73569b0 tests:passed
**Criteria approved:** agent-drafted
**Priority:** 3
**Size:** L
**Files:** agents/intake.md agents/capture.md agents/ideate.md agents/question.md agents/verify.md agents/start.md agents/go.md agents/run.md agents/run-worker.md agents/review.md agents/status.md agents/close.md agents/unblock.md agents/resume.md agents/upgrade.md agents/retro.md agents/log.md agents/help.md agents/audit.md agents/config.md agents/tracker/port.md agents/tracker/markdown.md SKILL.md
**Depends on:** REQ-286

## Task

Update every phase agent listed in design §13 so work-item storage goes only through named port ops after loading config → port.md → agents/tracker/<backend>.md. Markdown behavior must remain byte-compatible. Do not invent Linear calls here — load path + markdown op discipline only.

## Context

Design §5.2 and §13; ideate risk: missing one agent causes split brain. Clarification: agents layer only.

## Acceptance Criteria

- [x] Each §13 agent file instructs: load config, resolve tracker.backend, read port.md, read backend md, call only named port ops for work-item storage
- [x] No agent documents silent fallback from linear to markdown
- [x] Markdown path still references existing lib/file flows via markdown.md ops (no mass rewrite of lib/*.sh required in this REQ)
- [x] SKILL.md or config.md points at the load-path contract once
- [x] If backend resolves to linear but agents/tracker/linear.md is missing/unreadable, agents hard-stop with setup instructions — never fall through to markdown paths

## Verification Steps

1. **runtime** `for f in agents/intake.md agents/capture.md agents/run.md agents/run-worker.md agents/status.md; do grep -q 'tracker' "$f" || echo MISSING:$f; done`
   - Expected: key agents mention tracker load path
2. **runtime** `grep -L 'port.md\|tracker.backend\|tracker/' agents/intake.md agents/capture.md agents/run.md agents/close.md agents/upgrade.md || true`
   - Expected: spot-check load path references

## Integration

**Reachability:** Invoked at start of every phase agent (design §5.2 step list)

**Data dependencies:** agents/tracker/port.md agents/tracker/markdown.md .do-work/config.yml

**Service dependencies:** agents/config.md Load Config

## Outputs
