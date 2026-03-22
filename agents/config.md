# Config Loader

This is a reusable instruction block. Other agents reference this file to load config at startup.

---

## Load Config

At the start of execution, after detecting the project root:

1. Check if `{project}/do-work/config.yml` exists
2. If it exists, read the file and keep its values in context for subsequent steps
3. If it does not exist, create it with the default template below, then keep those values in context:

```yaml
# do-work configuration
# Edit this file to customize agent behavior.

project:
  name: ""

log:
  enabled: true
  platforms: []          # e.g. [x, linkedin]
  drafts_per_platform: 2
  batch_size: 2            # drafts per batch (2 drafts + More + Skip = 4 options in AskUserQuestion)
  audience: ""           # e.g. "indie hackers", "enterprise devs", "startup founders"
  voice: ""              # e.g. "casual and direct", "thoughtful and technical"
```

4. If the file exists but is missing keys, use the defaults above for any missing values

**Never fail or stop because of a missing or incomplete config.** If config creation fails for any reason, proceed with in-memory defaults.

---

## Config Schema Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `project.name` | string | `""` | Project display name |
| `log.enabled` | boolean | `true` | Whether the log step runs after Go |
| `log.platforms` | list | `[]` | Platforms to generate draft posts for (e.g. `[x, linkedin]`) |
| `log.drafts_per_platform` | integer | `2` | Number of draft posts to generate per platform |
| `log.batch_size` | integer | `2` | Drafts to show per batch in the AskUserQuestion selection prompt. Default 2 because AskUserQuestion has a 4-option limit: `batch_size` drafts + "More approaches" + "Skip" must fit in 4 slots. Max 2 for non-final batches; final batch can show up to 3 (replacing "More" with a draft). |
| `log.audience` | string | `""` | Target audience for log posts (e.g. "indie hackers", "enterprise devs"). Shapes framing and references. |
| `log.voice` | string | `""` | Writing style for log posts (e.g. "casual and direct", "thoughtful and technical"). Shapes tone and word choice. |
