# do-work field lessons

**Only lessons that improve the next do-work run.** Gate before every append:
**“Will this improve do-work?”** — Yes → here (skill process: claim, worktree,
verify, merge, tracker, recovery). No → project `AGENTS.md` / docs (session-capture),
not this file. No product names/ticket ids as substance.

## 1. Laravel Pest in git worktrees — real vendor, not symlink

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Pest fails all tests with `A facade root has not been set` / factories blow up | `vendor/` was **symlinked** from the main checkout into the worktree | **Do not** rely on a vendor symlink for Laravel. In the worktree app root (or package that owns `composer.json`): remove the symlink, run **real** `composer install`, keep `.env` linked/copied from main |
| `php artisan` boots but `php artisan test` / Pest does not | Same path mismatch: Pest/PHPUnit resolve base path via vendor location | Real vendor tree under the worktree package |

`provision-worktree.sh` `linked: vendor` is fine for many stacks; for **Laravel + Pest** treat vendor as unprovisionable-by-symlink and install for real.

## 2. Linear claim heartbeat in-place

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Orchestrator passed a **claim comment id** and said update in-place only | Multi-agent claim protocol | Use `save_comment` with that `id` + refreshed `heartbeat` ISO; do **not** post a second active claim comment unless update tools are missing |

## 3. Monorepo / nested package provision (depth)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| provision-worktree exits 0 but nested package deps missing; tests cannot boot | Auto-detect is depth ≤ 1 (root + immediate children only); nested `package.json` / `composer.json` not seen | `worktree.link_paths` for monorepo dep dirs, or symlink them after provision before verification |
| Vitest / package tests cannot resolve deps in worktree | Nested package `node_modules` not linked (same depth limit) | Symlink **absolute** path from main checkout’s package `node_modules` into the worktree package before test |

## 4. Path-unit close when children already shipped

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Path-unit worker has nothing to implement; need branch evidence for merge | Layer children already on integration base | Do **not** re-implement. Re-run path verification (tests + ui re-vision + docs). If `.do-work/` is gitignored, write a local path-closure note under the UR dir for humans, and land an **empty commit** (`--allow-empty`) on `req/<id>` so the orchestrator has a merge tip. Reuse prior `ui-evidence` PNG only after **re-vision-assert**; copy under the path-unit step name when useful |
| Worktree base wrong | Checkout HEAD ≠ named integration base | Create worktree from the **integration base named in the dispatch**, not from a dirty/other feature branch on the main checkout |

## 5. Stage B: assert integration base before every merge

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| REQs merge into a random feature branch while go recorded a different integration base | Orchestrator shell checked out another branch mid-run (or never re-asserted base after sibling activity); Stage B used current HEAD | Before **every** Stage B `git merge`, run `git branch --show-current` and require equality with the recorded ensure-integration-base tip. If mismatch: `git checkout <recorded-base>` only when safe, or merge via worktree that holds the base — never merge “wherever HEAD is” |
| Feature commits exist but integration tip missing files | Merged onto wrong branch first | Cherry-pick / re-merge feature commits onto the recorded base; leave foreign branch as-is or reset only if operator owns that WIP |

**Rule:** integration base is a **recorded name**, not “whatever the shell is on.” Parallel waves + multi-branch monorepos make silent checkout drift common.

## 6. Bash `read` + empty SQLite columns

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Multi-column CLI filters drop/mis-assign fields when a middle column is empty | `IFS=$'\t' read` treats tab as **IFS whitespace** and collapses consecutive delimiters | Use a non-whitespace record separator for `sqlite3 -separator` (e.g. `$'\x1e'`) when empty fields are possible |


## 7. Parallel iOS xcodebuild — unique derivedDataPath

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Parallel native iOS workers collide in shared DerivedData (build thrash, flaky codesign, wrong products) | Default DerivedData is shared across worktrees/agents | Pass and honor a **per-REQ** `-derivedDataPath` (e.g. `/tmp/dd-<sanitized-req-id>`) on every `xcodebuild test` in that worker; never share default DerivedData across concurrent iOS leaves |
| Orchestrator named a worktree path that is not on disk yet | Race or provision skipped | Create worktree from the **recorded integration base** (`git worktree add … -b req/<id> <base>`), then provision — do not invent a different base |


## 8. Go under Linear when capture left markdown-only REQs

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `tracker.backend: linear` but UR only exists under `.do-work/user-requests/` with `REQ-*.md` backlog; Linear milestone/issues missing | Capture ran markdown store (or dual-wrote) while config already says linear | **Hard-stop** — do not treat markdown REQs as live. Offer: (1) create Linear UR milestone + issues from the markdown capture then go, or (2) set `tracker.backend: markdown` for this run. Never silent-fallback while backend is linear |


## 9. Go / verify UR existence must follow active backend

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `go` hard-stops "UR not found at user-requests/…" while sqlite/linear has the UR | Phase agent still uses markdown-only path probe for "UR exists" | After Load Config + backend resolve: **markdown** → `user-requests/UR-NNN/input.md`; **sqlite** → `get-ur`; **linear** → `read_ur`. Never require local `user-requests/` when backend is not markdown |
| Verify/score runs against empty/wrong backlog | Same: globbed `REQ-*.md` while live store is DB/Linear | List REQs only via port (`list_reqs_for_ur` / `list-reqs`) |

## 10. SQLite archive gate: body ACs + closure_proof column

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `archive-req` fails: missing closure proof / unchecked acceptance criteria | Worker reported done but never set `closure_proof` or flipped `- [ ]` → `- [x]` in REQ **body** | Before `archive-req`: `update-req --closure-proof "…"` and rewrite body AC checkboxes to `[x]` (integrity counts unchecked boxes in body text). Status is set to `done` by `archive-req` itself |

## 11. Worker hard-death (infra: usage limit / crash) — clean orphan worktree before re-dispatch

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worker vanishes with **no YAML report** (idle/failed — e.g. API usage-limit 429, crash); REQ still `in_progress`, an orphan `.worktrees/req-NNN` + a `req/REQ-NNN` branch with **uncommitted** partial work are left behind | Worker process died mid-TDD on an infrastructure failure — not a clean `status: stopped` report | Do NOT salvage uncommitted partial work. `git log req/REQ-NNN` first — if no `feat(REQ-NNN)` commit, the branch is just the base: `git worktree remove .worktrees/req-NNN --force` then `git branch -D req/REQ-NNN`. Refresh the heartbeat (leave the claim — resume semantics) and re-dispatch a FRESH worker off **current** `new-work`. Skipping the cleanup makes the re-dispatched worker's `git worktree add … -b req/REQ-NNN` fail (worktree/branch already exist). Validated under sqlite; same shape for any backend |


## 12. Capture cycle-check is a no-op under sqlite

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `bash {skill-root}/lib/cycle-check.sh UR-NNN` exits 0 under `backend: sqlite`, yet the dep graph was never actually checked | `cycle-check.sh` globs `REQ-*.md` across backlog/working/archive; under sqlite REQs are `work.db` rows (no `REQ-*.md` files), so it finds no edges and returns "no cycle" **vacuously** | Under sqlite, do **not** treat `cycle-check.sh` exit 0 as proof of acyclicity. Verify the graph by querying the `deps` table (`req_id` → `depends_on_req_id`) and running a DFS, or add a `dw-db cycle-check` op. Markdown backend: `cycle-check.sh` remains valid |


## 13. Capture: never guess a not-yet-allocated REQ slug for `--deps`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| A capture-created REQ's `--deps` points at the **wrong** REQ (a different UR's REQ) — the dependent later claims a satisfied/unrelated dep instead of its real predecessor | `create-req` allocates slugs globally (max+1 across the whole DB / REQ tree); a multi-REQ capture that passes `--deps "REQ-NNN"` with a **guessed** slug has it accepted (that slug already exists for another REQ) and silently wired to the wrong target | Create the dependency-target REQ **first**, read its actual slug from `create-req` stdout, then pass that real slug as `--deps` on the dependent REQ. Or create all REQs first and wire deps after via `set-blocked-by`. **Never** pass a not-yet-allocated slug to `--deps`; always re-verify with `dw-db check-deps REQ-NNN` after |


## 14. Worker worktree base: branch off the named integration branch, not HEAD

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| A worker's worktree is created off the **wrong** branch (a stale `req/*` or unrelated feature branch), so its commit lands outside the recorded integration base and a later merge goes into the wrong branch | `run-worker.md` W1 reads the base from `git rev-parse --abbrev-ref HEAD` in the main checkout; if another session, operator action, or hook moved HEAD between `ensure-integration-base` and worktree creation, the worker branches off the moved HEAD, not `new-work` | When dispatching a worker in any checkout whose HEAD can drift (e.g. a concurrent do-work session sharing the tree), instruct the worker to create its worktree off the **named** integration branch (`git worktree add … -b req/<id> new-work`), not off HEAD. Then re-assert `git branch --show-current == new-work` before **every** merge (see §5). Workers must never run `git checkout`/`switch` in the main checkout |


## 15. Run phase: background worker/review dispatches don't return their report — verify independently or dispatch foreground

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| A run-worker or review subagent dispatched in the background with a `name` returns only an `idle_notification` ("available"); its YAML Return Report never arrives as a readable message, so the orchestrator can't parse `status` / `closure_proof` / `checkpoint_log` | Named background Agent dispatches behave as persistent teammates (idle-and-wait for mailbox messages), not one-shot tasks; the agent's final report is its turn output, which does not route back to the orchestrator as a completion result over the teammate channel | Do **not** block on the worker's/reviewer's self-reported YAML. Treat the **commit + tests as ground truth**: confirm scope (`git show <hash> --stat`), re-run the REQ's tests + the full suite, run the policy gate, and check the docs yourself — then run the gates and archive on that independent evidence. If you need the report inline, dispatch the worker/reviewer **foreground** (`run_in_background: false`) so its YAML returns directly as the tool result |


## 16. Symlinked dep dir + worker-side regenerator corrupts the shared copy after teardown

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| The orchestrator's final suite (or `php artisan test` / `npm test`) fails in the **main checkout** with a path error pointing at a just-removed worktree (e.g. `include(.../​.worktrees/req-NNN/app/Providers/AppServiceProvider.php): Failed to open stream`) | `provision-worktree.sh` symlinked a dep dir (e.g. `vendor/`) into the worktree; a worker ran a **regenerator** there (`composer dump-autoload`, `npm rebuild`, `npm install`, generation of an optimized classmap) that rewrote the shared dir's generated artifacts to **worktree-relative paths**. Because the dir is a symlink, those worktree paths landed in the main checkout's real dep dir. Tearing the worktree down leaves the main checkout pointing at deleted paths | After the last worker worktree is torn down and **before** the final suite, re-run the regenerator in the main checkout (`composer dump-autoload`, `npm rebuild`) to rewrite the artifacts against main paths. Preventively: for dep dirs a worker is likely to regenerate, prefer real provisioning (`worktree.setup_command: "composer install --no-interaction"`) over a symlink, or instruct workers not to run regenerators in a symlinked-vendor worktree |

Related to §1 (symlinked vendor) but distinct: the symlink **works for running tests** — it breaks only when a worker **regenerates** the shared artifacts, and the failure surfaces in the orchestrator's final suite, not the worker's.


## 17. Pest `WARN` from missing `.env` in a greenfield worktree is cosmetic

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `php artisan test` / `pest` prints `Tests: 1 warning, N passed` with a `WARNINGS … file_get_contents(…/packages/server/.env): Failed to open stream` trace through `vlucas/phpdotenv`, but every assertion counts as passed and the runner exits 0 | Greenfield worktree has no `.env` (it is gitignored and the main checkout never had one either); phpdotenv's `@file_get_contents` raises a PHP warning that Pest surfaces as a test-warning even though no assertion failed | Treat as **green**. The pass/fail signal is the runner **exit code and the `passed`/`failed` counts**, not the `warning` count. Do not chase the warning by creating a `.env`, and do not return `verification-failing`. Sanity check with `vendor/bin/pest … > /dev/null 2>&1; echo exit=$?` if the summary line is ambiguous |

