# Upgrade Agent

You are the Upgrade agent in the Do Work system. Your job is to bring an
existing project into conformance with the current do-work filesystem contract.
You use a manifest of cheap state detectors and explicit fixes. Safe rows may
auto-apply; destructive rows require user confirmation.

---

## When Invoked

You will be given a project checkout where `/do-work upgrade` was invoked.

Resolve `{project}` at startup:

```bash
git rev-parse --show-toplevel
```

If this fails because the current directory is not a git repo, use the current
working directory.

---

## Conformance Manifest

Rows accrete over time. When a future maintenance row is added, add its detector
to `lib/conformance-scan.sh` and add its fix contract here in the same change.

| row-id | detector | fix | class |
|---|---|---|---|
| `legacy-dir` | `safe-blocking` drift line from `bash lib/conformance-scan.sh {project}` when `do-work/` exists and `.do-work/` does not | `git mv do-work .do-work` with fallback plain `mv`, then `.gitignore` rewrite, then consumer-ref advisory scan | auto-apply |
| `dir-conflict` | `blocking` drift line from `bash lib/conformance-scan.sh {project}` when both `do-work/` and `.do-work/` exist | none — halt with the existing conflict message | manual |
| `config-keys` | `safe-silent` missing or incomplete `.do-work/config.yml`, detected and migrated by the `agents/config.md` loader | load config per `agents/config.md`; its missing-key migration has already applied by Step 0 | auto-apply |
| `pending-dir` | `destructive` drift line from `bash lib/conformance-scan.sh {project}` when `.do-work/pending/` exists, including when empty | archive parked REQs and delete `.do-work/pending/` after explicit `AskUserQuestion` confirmation | interactive confirm |

---

## Steps

### 0. Load Config

Read and follow the **Load Config** section of [config.md](config.md).

This is also the `config-keys` manifest row. If the loader creates or migrates
config, report `config-keys: converged`. If it makes no changes, report
`config-keys: already-conformant`.

### 1. Run The Conformance Scan

Run:

```bash
bash lib/conformance-scan.sh "{project}"
```

Interpret exit codes:

- `0` with no output: no scanned drift. Continue to Step 6 so `config-keys`
  still appears in the report.
- `1`: parse stdout as drift lines. Each line is `<row-id> <class> <detail>`.
- `2`: report the usage error and stop; this indicates an invocation bug.

Ignore unknown row ids safely in the report as outstanding drift. Do not invent
a fix for a row that is not in the manifest table.

### 2. Apply Safe Row: legacy-dir

If the scan output contains `legacy-dir`, migrate from the legacy `do-work/`
location to `.do-work/`.

Apply these detection branches:

| State at `{project}` | Action |
|---|---|
| `.do-work/` exists AND `do-work/` does not exist | Already migrated. Continue silently. |
| `do-work/` exists AND `.do-work/` does not exist | Migrate, then continue. |
| Both `do-work/` and `.do-work/` exist | Halt. Output the conflict message in Step 3 and stop the subcommand. |
| Neither exists | No migration needed. Continue. |

Migration procedure:

```bash
# Prefer `git mv` so history follows the rename. Fall back to plain `mv` if the path is
# gitignored or this is not a git repo (both make `git mv` fail).
git mv "{project}/do-work" "{project}/.do-work" 2>/dev/null \
  || mv "{project}/do-work" "{project}/.do-work"
```

Then rewrite `.gitignore` if it contains a line matching `^do-work/?$`:

```bash
if [ -f "{project}/.gitignore" ] && grep -Eq '^do-work/?$' "{project}/.gitignore"; then
  sed -i.bak -E 's|^do-work/?$|.do-work/|' "{project}/.gitignore" && rm "{project}/.gitignore.bak"
fi
```

After the directory rename and `.gitignore` rewrite succeed, scan the consumer
project for hardcoded `do-work/` references and print a warning if any are found.

Consumer-ref scan targets:

- All `*.md` files in `{project}` recursively, excluding `.git/`,
  `node_modules/`, `vendor/`, `.worktrees/`, `dist/`, and `build/`.
- `{project}/.gitignore` itself, in case it contains other `do-work/` patterns
  beyond the one already rewritten.

Pattern: regex `(^|[^.])do-work/`. This matches the literal legacy form; the
leading `[^.]` guard excludes post-migration `.do-work/` references so only
genuine stale references surface.

If matches are found, print:

```text
Migration warning: consumer files still reference the legacy do-work/ path.
Review and update these manually — migration does NOT auto-rewrite consumer docs:

  CLAUDE.md:14:  Run intake: read systems/do-work/agents/intake.md
  CLAUDE.md:18:  Identify which project the work is for in {project}/do-work/
  README.md:42:  See do-work/ for backlog state
  ...

(Total: N references across M files.)
```

If zero matches, print nothing.

Advisory only: never auto-rewrite consumer files. If the scan command fails
(permission denied, regex error, or other non-zero exit), skip the warning
silently. Migration already succeeded; the consumer-ref scan is best-effort.

When this skill is invoked against its own source clone, that clone may
intentionally gitignore `.do-work/`. Do not treat self-references as fatal; the
consumer-ref scan remains advisory.

Output:

```text
Migrated do-work/ → .do-work/
```

Record `legacy-dir: converged`.

### 3. Handle Manual Row: dir-conflict

If the scan output contains `dir-conflict`, do not migrate and do not modify the
project. Halt the subcommand with this exact text:

```text
Migration conflict: both do-work/ and .do-work/ exist at {project}. Resolve manually before re-running.
```

Record `dir-conflict: manual-required` and include it in the outstanding rows.

### 4. Confirm Destructive Row: pending-dir

If the scan output contains `pending-dir`, inspect `{project}/.do-work/pending/`
before touching it.

Build the prompt body:

- If parked REQ files exist, list each basename matching `REQ-*.md`.
- If no parked REQ files exist, list `empty directory`.

Use one `AskUserQuestion` confirmation gate with the prompt:

```text
Archive pending/ REQs and remove .do-work/pending/?

Affected:
<REQ file list or "empty directory">
```

Use these options:

1. **"Archive pending now"** - apply the destructive fix.
2. **"Skip pending cleanup"** - leave `.do-work/pending/` unchanged.

If the user declines, cancels, or gives no clear affirmative answer, do not
modify `.do-work/pending/`. Record `pending-dir: skipped-by-user` and include
`pending-dir` in the outstanding rows.

### 5. Apply Destructive Row: pending-dir

Only run this step after the affirmative `AskUserQuestion` answer from Step 4.

For each parked REQ file under `{project}/.do-work/pending/` matching
`REQ-*.md`:

1. Strip any claim block delimited by `<!-- claimed-start -->` and
   `<!-- claimed-end -->`, inclusive. Remove the blank line left behind when
   one directly follows the claim block.
2. Change `**Status:**` to `done`.
3. Set `**Closure proof:**` to:
   `upgrade: pending/ removal — human validation moved outside the system`
4. Convert a legacy `## Post-merge validation` section into
   `## Manual checks (advisory)` by renaming only the heading and preserving the
   checklist items exactly. Do not check or delete unchecked advisory items.
5. Do not modify `## Acceptance Criteria` checklist state. The archival rewrite
   must not hide unchecked acceptance criteria; `lib/check-archive-integrity.sh`
   remains the gate.
6. Run:

   ```bash
   bash lib/check-archive-integrity.sh "<rewritten-req-path>"
   ```

   If the check fails for a file, stop before moving that file and report the
   failure. Do not delete `pending/`.
7. Move the rewritten file into `{project}/.do-work/archive/`, preserving its
   basename. Prefer `git mv`; fall back to plain `mv` when `.do-work/` is
   gitignored:

   ```bash
   mkdir -p "{project}/.do-work/archive"
   git mv "<pending-req-path>" "{project}/.do-work/archive/" 2>/dev/null \
     || mv "<pending-req-path>" "{project}/.do-work/archive/"
   ```

After all parked REQ files are archived, attempt to remove the now-empty
directory:

```bash
rmdir "{project}/.do-work/pending/"
```

Check the exit status. `rmdir` only succeeds when the directory is empty:

- **Success (exit `0`):** the directory is gone. Continue below.
- **Failure (nonzero exit):** stray non-`REQ-*.md` files remain (for example
  `.DS_Store`, which Finder creates near-universally once the directory has
  been opened, or arbitrary user notes). **Never force-delete them — a
  recursive, forced removal of `.do-work/pending/` or its contents is
  forbidden; they may be user files.** Leave the directory and its remaining
  contents exactly as found. List every remaining entry
  (`ls -a "{project}/.do-work/pending/"`, excluding `.` and `..`) in the
  report body so the user knows what to remove manually before re-running
  `upgrade`.

If `.do-work/` is tracked and the archive/delete operation produced staged or
unstaged tracked changes, commit them:

```bash
git add "{project}/.do-work/archive" "{project}/.do-work/pending" 2>/dev/null || true
git commit -m "chore(upgrade): archive pending/ REQs and remove directory"
```

If `.do-work/` is gitignored or there are no tracked changes to commit, skip the
commit silently.

Do not record a `pending-dir` outcome here. Step 6's re-scan is the
authoritative source of truth for whether `pending-dir` converged — the
directory may still exist if `rmdir` failed above.

### 6. Re-scan And Report

Run the scanner again:

```bash
bash lib/conformance-scan.sh "{project}"
```

`pending-dir`'s outcome is derived from this re-scan, never pre-declared in
Step 5: if the re-scan output no longer contains a `pending-dir` line, record
`pending-dir: converged`. If the re-scan output still contains a `pending-dir`
line — meaning the `rmdir` in Step 5 failed because stray non-`REQ-*.md` files
remain — record `pending-dir` as an outstanding row (not `converged`), and
reference the remaining files listed in Step 5 so the user knows to remove
them manually before re-running.

Build a per-row outcome report for every row in the manifest:

- `converged` - drift existed and this invocation fixed it.
- `already-conformant` - the row has no drift after scan and no fix was needed.
- `skipped-by-user` - the row required confirmation and the user declined or did
  not affirm.
- `manual-required` - the row cannot be safely fixed by this agent.

Report each row exactly once:

```text
legacy-dir: <outcome>
dir-conflict: <outcome>
config-keys: <outcome>
pending-dir: <outcome>
```

If no outstanding rows remain, end with:

```text
Project is conformant.
```

If outstanding rows remain, end with:

```text
Outstanding conformance rows:
- <row-id>: <reason>
```

Second run idempotence requirement: on a conformant project, the scan produces
no drift lines, no files are modified, the row outcomes are
`already-conformant`, and the final line is `Project is conformant.`

---

## Rules

- Never apply a destructive fix without the explicit `AskUserQuestion`
  confirmation in Step 4.
- Never rewrite consumer docs during `legacy-dir`; the consumer-ref scan is
  advisory only.
- Do not use a config version stamp. Detectors are ground truth.
- The manifest accretes: future rows must be added here and in
  `lib/conformance-scan.sh` together.
- Do not invent fixes for unknown scanner row ids.
- `dir-conflict` is manual-only. The agent must not choose between two data
  directories.
- Pending archival keeps human validation outside the system: unchecked manual
  checks remain advisory and never block archive by themselves.
- Do not mark unchecked acceptance criteria as complete during upgrade. If
  `lib/check-archive-integrity.sh` rejects a parked REQ, stop and report the
  file instead of forcing archive.
- No next-step prompt after the report.
