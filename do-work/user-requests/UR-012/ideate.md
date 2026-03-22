# Ideate — UR-012

**Reviewed:** 2026-03-22

## Explorer — Assumptions & Perspectives

- The brief says "after every step we take" — this implies all agents (intake, capture, ideate, verify, run, go, log) should offer next steps, not just the log agent which currently uses AskUserQuestion. Each agent ends with a "Report" section that outputs plain text; converting all of them to use AskUserQuestion is a significant surface area change.
- "Next steps" means different things per agent: after intake it's "run capture", after capture it's "run verify/go", after go it's "review outputs". The next-step options need to be agent-specific, not a generic list.
- The config switch needs a clear scope boundary — does it control whether agents present next steps at all, or does it control whether they use AskUserQuestion specifically (vs. plain text suggestions)? The brief implies the former: on = present via AskUserQuestion, off = current behavior (plain text or nothing).
- Orchestrator agents (start, go) delegate to sub-agents. If sub-agents present AskUserQuestion mid-flow, that would interrupt the orchestrator's sequence. Next-step prompts should only fire at the terminal output of a pipeline, not between delegated steps.

## Challenger — Risks & Edge Cases

- AskUserQuestion has a hard cap of 4 options. Some agents may have more than 3 plausible next steps (e.g., after verify: run, auto-fix, re-capture, inspect gaps). The implementation must prioritize or truncate, which means each agent needs a curated option set — not a dynamic list.
- If the config key is missing or the feature is off, agents must produce identical output to today. This is a backwards-compatibility constraint: the config default should be `false` so existing users are unaffected unless they opt in.
- The run agent operates in a loop. Presenting AskUserQuestion after every REQ completion would break the autonomous loop — the user would have to approve each iteration. The run agent should only present next steps when the loop terminates (backlog empty or stopper hit), not after each REQ.
- When start or go agents delegate, they already control the flow. Adding AskUserQuestion at sub-agent boundaries would create double-prompting (sub-agent prompts, then orchestrator prompts). The feature should be suppressed when an agent is running as a delegate inside an orchestrator.

## Connector — Links & Reuse

- AskUserQuestion is already used in the log agent (REQ-035, REQ-036) for draft selection. The pattern established there — structured options with preview fields, "Other" as discussion mode — can be reused for next-step presentation across agents.
- Config extension follows the same pattern as REQ-013 (add config system), REQ-024 (add audience config), REQ-034 (add batch_size). The schema in config.md has a clear table format; adding a new key is mechanical.
- The intake agent already outputs "Next steps:" as plain text in its report. The other agents output similar suggestions. Converting these to AskUserQuestion options is a format change, not a logic change — the content already exists.

## Summary

The core work is: (1) add a config toggle, (2) define agent-specific next-step option sets, and (3) update each agent's report section to conditionally use AskUserQuestion. The main risks are interrupting orchestrated flows (start/go delegating to sub-agents) and breaking the run agent's autonomous loop. The safest approach is to only present next steps at the terminal output of standalone agent invocations, and to default the feature to off.
