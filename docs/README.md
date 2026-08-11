# Do Work — user documentation

Task-based guides for people who install and run `/do-work` in a project. Works with any agent harness wired to the shared skills hub.

## Start here

| If you want to… | Read |
|-----------------|------|
| Install the skill and run your first brief end-to-end | [Getting started](getting-started.md) |
| Understand UR, REQ, `start` / `go`, and the gates | [Concepts](concepts.md) |
| Look up a command or flag | [Commands](commands.md) |
| Fix a failure symptom | [Troubleshooting](troubleshooting.md) |

## Deeper reference

| Page | Audience |
|------|----------|
| [Architecture analysis](architecture-analysis.md) | Owner / architect / operator: full architecture map + ranked improvements |
| [How it works](HOW-IT-WORKS.md) | Operators who want phase-by-phase design detail |
| [../README.md](../README.md) | Install one-liner, quick start, config overview |
| [../agents/config.md](../agents/config.md) | Full `config.yml` schema |
| [../SKILL.md](../SKILL.md) | Skill entrypoint and full behavioural reference |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Contributors changing the skill itself |

## Happy path (two commands)

```text
/do-work start I need a user settings page with email and password change
/do-work go UR-001
```

`start` records the brief and builds the backlog. `go` checks coverage, then runs the backlog when confidence meets the project threshold (default 90%).

## Docs map

```text
docs/
├── README.md                  ← you are here (index)
├── getting-started.md         ← install → first start → first go
├── concepts.md                ← mental model
├── commands.md                ← command reference
├── troubleshooting.md         ← symptoms → fixes
├── HOW-IT-WORKS.md            ← deep dive (design + phases)
└── architecture-analysis.md   ← architecture map + recommendations
```
