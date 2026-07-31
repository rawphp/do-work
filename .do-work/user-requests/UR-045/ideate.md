# Ideate — UR-045

**Reviewed:** 2026-07-31

## Explorer — Assumptions & Perspectives

- **Assumes Linear Initiatives + InitiativeToProject exist in the operator's MCP surface.** The hierarchy is the whole model (UR = Initiative, Project per UR). Scenario: a workspace plan without Initiatives (or MCP tools that only expose Issues/Projects) would leave `create_ur` / `read_ur` / verify-close homes unimplemented. Triggers §6 hierarchy and §6.4 intake sequence.
- **Assumes every phase agent will actually load the port (not just "should").** ~18 agents touch work items; missing one keeps raw `.do-work/REQ-*` paths forever. Scenario: `status` or `unblock` still globs markdown while `run` uses Linear → split brain and false claim/idle reports. Triggers §5.2 load path and §13 agent list.
- **Non-ticket homes (Docs, Initiative sections) need capacity and permission checks.** Decisions, calibration, verify, and close are parked in Team Docs and Initiative description sections. Scenario: doc create is blocked for the bot, or Initiative description hits a size limit mid-capture/verify → agent invents ad-hoc comments (forbidden) or hard-stops mid-UR. Triggers §10 non-ticket park and §9.1 "prefer description appends".
- **Human Linear UI editors are unmodeled stakeholders.** Claim is comment protocol + workflow state while assignee stays human. Scenario: a human clears claim comments, renames `do-work/UR-007`, or moves status outside the map while a run is live → concurrent-conflict thrash or unclaimable backlog. Triggers §8 claim protocol and open risk #5.
- **Migration leaves historical trees readable but not authoritative — offline tooling may not know.** Retro, coverage rollups, and humans grepping archive will still see markdown. Scenario: after cutover someone runs a script against `.do-work/archive/` and treats it as live backlog. Triggers §12 step 6 and §7 ledger "telemetry only" distinction.

## Challenger — Risks & Edge Cases

- **Optimistic claim is weaker than `claim-req.sh`'s rename race.** Markdown claim uses atomic `mv`/`git mv` (exit 2 on race). Linear is re-read + comment. Scenario: two orchestrators claim the same issue in the same second; both pass re-read → dual workers, dual worktrees, merge chaos. Triggers §8 atomicity story and open risk #3.
- **"Linear unusable ⇒ hard stop" vs partial outages mid-REQ.** Clear at start; foggy mid-flight. Scenario: MCP dies after claim but before heartbeat/archive — worker cannot release cleanly; issue stuck in Progress with stale claim comment. Triggers §4 "Linear unusable" and §14 error table (no mid-flight recovery path).
- **`status_map` and label prefixes are team-specific landmines.** Defaults map stopped → "Canceled". Scenario: team has no "Canceled", or "Done" is a different workflow state name → every `set_req_status` fails after capture has already created issues. Triggers §7 config schema and validation rules.
- **Native `blocks` relations + mirrored `**Depends on:**` can diverge.** Two sources of truth for deps. Scenario: human edits relation graph in UI but not the body (or vice versa); `list_claimable_reqs` follows relations while humans read the body. Triggers §4 Deps decision and §14 "Relation tool missing" fallback.
- **Milestone cursor on Project description is another optimistic shared write.** Deploy gate still uses local `gate-owner.md`, but active milestone content is remote. Scenario: two terminals advance milestone after gate without serializing Project description updates → lost checklist updates. Triggers §11 milestone mode.
- **Phasing (9 steps) under-orders test/regression for markdown.** Port + markdown.md first is right, but every agent touch is a regression surface. Scenario: half-migrated agents (capture on port, run still filesystem) ship and pass markdown tests while Linear path is unusable. Triggers §16 phasing and §15 testing.

## Connector — Links & Reuse

- **Reuse parallel coordination design, not its FS primitives.** `docs/superpowers/specs/2026-05-21-do-work-parallel-coordination-design.md` and `lib/{pick,claim,check-deps,check-footprint,heartbeat,scan-stale,deadlock-check}.sh` define the semantics port.md must restate; Linear must reimplement, not call bash.
- **Header schema and path-units are already the body template.** SKILL.md REQ header fields + path-unit/`Parent:` model map 1:1 to §9.2 Issue template and sub-issues — capture output shape stays stable across backends.
- **Upgrade/conformance is the natural migration door.** UR-039 decision: maintenance centralizes in `/do-work upgrade` via conformance manifest. Migration (§12) should be a conformance/upgrade row or explicit upgrade step, not a one-off agent-only path.
- **Linear skill already mandates live tool rediscovery.** `~/.grok/skills/linear/SKILL.md` (MCP-first, `search_tool` then `use_tool`) matches §17 risk #1 and §14 MCP missing — `linear.md` should import that protocol, not invent tool names.
- **Standing decisions memory format is portable.** `.do-work/decisions.md` one-line format becomes Team Doc `do-work/decisions` with the same line grammar; capture/ideate/question/worker read paths already treat the file as optional.
- **Straggler backlog item is unrelated.** `REQ-270` (depends-on tokenizer) sits at backlog root from UR-042 — not part of multi-tracker; do not fold into this UR's decomposition.
- **No existing `agents/tracker/`** — greenfield under `agents/`; layers for this project remain `[agents, commands, templates]` with likely commands/templates out of scope (docs + agents + config only), consistent with UR-043/044 layer answers.

## Summary

The design is implementation-ready on product decisions, but the hard work is **mechanical port adoption across every phase agent** and **honest Linear claim/deps semantics** without silent markdown fallback. Decompose so markdown regression stays green at every phase boundary, freeze the op catalog early, and treat Linear MCP capability discovery (Initiatives, relations, Docs) as a first-class spike path-unit before wiring the full run loop.
