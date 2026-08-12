2026-06-12 | UR-036 | human/device validation never blocks merge — automated gates green means delivery proceeds; human checks live post-merge | stranded worktrees were the failure mode
2026-06-12 | UR-036 | pending-validation REQs live in .do-work/pending/, not working/ | working/ implies a live claim + heartbeat; pending has neither
2026-06-12 | UR-036 | human-wait is a first-class Status (pending-validation), not a stopper reason | a stopper strands work; a status parks it after delivery
2026-06-12 | REQ-239/REQ-240 | pending-validation dependency-satisfaction must be honored by BOTH lib/check-deps.sh AND lib/pick-req.sh's inline dep filter (each globs archive/ ∪ pending/) | pick-req reimplements dep-checking inline and is the real claim-arbitration consumer; fixing only check-deps left dependents of parked REQs unclaimable
2026-07-09 | UR-039 | human/device checks never gate closure — REQs archive as done with a `## Manual checks (advisory)` block; supersedes all four 2026-06-12 UR-036/REQ-239-240 entries | user validation is outside the system
2026-07-09 | UR-039 | pending-validation Status, .do-work/pending/, and approve/reject are removed; dependency satisfaction is archive/-only | pending/ implied in-system user validation
2026-07-09 | UR-039 | project maintenance centralizes in /do-work upgrade via a state-probing conformance manifest (no version stamp in config.yml) | the filesystem is the version; detectors are idempotent
2026-07-09 | UR-039 | run.md + run-worker.md rewired in one REQ (REQ-245) rather than split per file | the deferred_checks report-field rename spans both sides of the contract; a split leaves a broken mid-state
2026-07-10 | UR-041 | layer "templates" out of scope | user answered "No" at layer-coverage prompt
2026-07-10 | UR-041 | un-run test/build suite derives unproven via orchestrator-stamped `**Suite:** not-run` header; human/device advisories still never affect proven-ness — refines (does not supersede) the 2026-07-09 advisory-model entries | proven must mean automated verification ran
2026-07-10 | UR-041 | retired config keys are removed only via a curated tombstone list under explicit /do-work upgrade (destructive row); user-added keys are never flagged | additive config loader never deletes; safety by construction
2026-07-10 | UR-042 | deps-format fix kept in one REQ (both parsers + SKILL.md doc + tests) rather than split | pick-req.sh and check-deps.sh must agree on tokenization; a split leaves an inconsistent mid-state

2026-07-23 | UR-043 | layer "commands" out of scope | user answered "No" at layer-coverage prompt
2026-07-23 | UR-043 | layer "templates" out of scope | user answered "No" at layer-coverage prompt
2026-07-23 | UR-044 | layer "commands" out of scope | user declined layer-coverage prompt; default No for lib/agents/docs-only brief
2026-07-23 | UR-044 | layer "templates" out of scope | user declined layer-coverage prompt; default No for lib/agents/docs-only brief

2026-07-31 | UR-045 | layer "commands" out of scope | user answered "No" at layer-coverage prompt
2026-07-31 | UR-045 | layer "templates" out of scope | user answered "No" at layer-coverage prompt
2026-07-31 | UR-045 | Linear MCP capability spike before full Linear CRUD | user clarification spike-first
2026-07-31 | UR-045 | mid-flight Linear MCP failure leaves claim active; resume/unblock repairs | user clarification
2026-07-31 | UR-045 | status_map defaults hard-fail if team workflow state missing | user clarification
2026-07-31 | UR-045 | deps eligibility: native Linear blocks relations authoritative; body Depends on is mirror | user clarification
2026-07-31 | UR-045 | migration surfaced via /do-work upgrade + conformance, not a separate forever command | inferred+confirmed + UR-039
2026-07-31 | hierarchy | Linear UR home is Project Milestone on shared product_project, not Initiative | Linear MCP lacks Initiative create/list tools
2026-08-11 | UR-046 | layer "commands" out of scope | plan work lives in agents/lib/docs not commands/
2026-08-11 | UR-046 | layer "templates" out of scope | no template surface for sqlite backend
