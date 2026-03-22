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

test:
  suite_command: ""      # e.g. "./vendor/bin/pest", "npx vitest run", "npm test"

next_steps:
  enabled: false         # when true, agents present next-step options via AskUserQuestion after each phase
```

4. **Migrate missing keys to disk.** Compare the existing config.yml against the default template above. For each top-level section (`project`, `log`, `next_steps`) and each key within those sections:

   - If a **top-level section is entirely missing** from the file (e.g. `next_steps:` does not appear), append the full section block — including all keys, default values, and inline comments — to the end of the file.
   - If a **top-level section exists but is missing individual keys** (e.g. `log:` exists but `batch_size` is absent), append the missing keys with their default values to that section.
   - **Never overwrite existing values.** If a key exists in the file, keep the user's value regardless of what the default says.
   - If **no keys are missing**, do not write to the file. Skip this step silently.
   - If keys were added, report: `Config updated: added [list of added keys/sections]`

5. Keep the final merged values (file values + defaults for anything still missing) in context for subsequent steps.

**Never fail or stop because of a missing or incomplete config.** If config creation or migration fails for any reason, proceed with in-memory defaults.

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
| `test.suite_command` | string | `""` | Full test suite command to run at end of the do-work loop (e.g. `./vendor/bin/pest`, `npx vitest run`). If empty, the run agent attempts common defaults. |
| `next_steps.enabled` | boolean | `false` | When true, agents present next-step options via AskUserQuestion after each phase completes. When false or missing, agents report as they do today without prompting. |
