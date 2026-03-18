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
