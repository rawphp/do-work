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
| Path-unit worker has nothing to implement; need branch evidence for merge | Layer children already on integration base | Do **not** re-implement. Re-run path verification (tests + ui re-vision + docs). If `.do-work/` is gitignored, write a local path-closure note under the Issue dir for humans, and land an **empty commit** (`--allow-empty`) on `req/<id>` so the orchestrator has a merge tip. Reuse prior `ui-evidence` PNG only after **re-vision-assert**; copy under the path-unit step name when useful |
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
| `tracker.backend: linear` but Issue only exists under `.do-work/user-requests/` with `REQ-*.md` backlog; Linear milestone/issues missing | Capture ran markdown store (or dual-wrote) while config already says linear | **Hard-stop** — do not treat markdown REQs as live. Offer: (1) create Linear Issue milestone + issues from the markdown capture then go, or (2) set `tracker.backend: markdown` for this run. Never silent-fallback while backend is linear |

## 9. Go / verify UR existence must follow active backend

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `go` hard-stops "UR not found at user-requests/…" while sqlite/linear has the Issue | Phase agent still uses markdown-only path probe for "UR exists" | After Load Config + backend resolve: **markdown** → `user-requests/UR-NNN/input.md`; **sqlite** → `get-ur`; **linear** → `read_ur`. Never require local `user-requests/` when backend is not markdown |
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
| A capture-created REQ's `--deps` points at the **wrong** REQ (a different Issue's REQ) — the dependent later claims a satisfied/unrelated dep instead of its real predecessor | `create-req` allocates slugs globally (max+1 across the whole DB / REQ tree); a multi-REQ capture that passes `--deps "REQ-NNN"` with a **guessed** slug has it accepted (that slug already exists for another REQ) and silently wired to the wrong target | Create the dependency-target REQ **first**, read its actual slug from `create-req` stdout, then pass that real slug as `--deps` on the dependent REQ. Or create all REQs first and wire deps after via `set-blocked-by`. **Never** pass a not-yet-allocated slug to `--deps`; always re-verify with `dw-db check-deps REQ-NNN` after |

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

## 18. Acceptance-evidence checker requires block-style YAML — flow-style reports falsely fail

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `lib/check-acceptance-evidence.sh <req> <report.yml>` prints `acceptance evidence missing evidence item: AC1…ACn` for every AC and exits 1, even though the report clearly lists each AC with `status: passed` + `evidence` | The script parses the worker report with a simple line-based reader (not a full YAML parser); flow-style mappings (`AC1: {status: passed, evidence: [{type: test, ref: t}]}`) are valid YAML but invisible to that reader, so it sees every AC as having no evidence | Write the report in **block style** (`AC1:` newline `  status: passed` newline `  evidence:` newline `    - type: test` newline `      ref: …`). Treat any "all ACs missing evidence" result as a formatting false-fail first — re-run with block style before investigating the report content |

## 19. Path-unit definition disagrees: verify is Layer-agnostic, close/go require Layer:none

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| A UR captured with every REQ assigned a `Layer:` (backend/frontend) — none `Layer: none` — yet the endpoint REQs carry real `**Entry point:**`/`**Terminal state:**` pairs; `go` Step 4b fires the closure offer and/or the close agent then finds **zero path-units** and writes an empty `no-path-units` report, skipping the endpoint walk the operator expected | `verify.md` Step 4f treats "Entry point / Terminal state present" as the path-unit signal (Layer-agnostic), but `close.md` Step 2 and `go.md` Step 4b define a path-unit as `**Layer:** none` AND both path fields present. The two definitions disagree, so an Issue captured with layered path-field REQs looks walkable to verify but yields nothing to close | When collecting path-units for close on an Issue with no `Layer: none` REQs, fall back to the verify signal: every archived REQ with non-empty `**Entry point:**` + `**Terminal state:**`, ignoring `**Layer:**`. (Skill-side fix: align close.md Step 2 / go.md Step 4b with verify's Layer-agnostic detection, or have capture emit `Layer: none` path-unit parents when a REQ's entry point spans the layer model.) |

## 20. "Validate complete" ≠ empty close report

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Operator asks to validate an Issue is complete; close writes `overall: no-path-units` while the product already ships (or while REQs sit in backlog with ACs still `[ ]`) | `close.md` only scans **archived** path-units (`Layer: none` + entry/terminal). A shipped UR whose REQs were never archived, or were captured as layered children without path fields, looks like "nothing to close" | Before treating `no-path-units` as a completeness yes: `list_reqs_for_ur` across backlog + working + archive. If any REQ is not archived, the Issue is **not** tracker-complete. Walk the brief on the merged app anyway (web/api/cli as the brief implies) and report product-complete vs tracker-complete as two verdicts |

## 21. Prefer the project's existing `.do-work/` layout over a legacy skill clone

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `/do-work start` tries to create `do-work/` (legacy tree) on a project that already has `.do-work/` + champion agents | The invoked skill copy is an older `do-work/`-path clone; Grok/hub may register that copy even when the project already runs champion | After `git rev-parse --show-toplevel`, if `{project}/.do-work/config.yml` exists, follow the champion agents (`.do-work/`, tracker port, ideate gate). Do **not** install or write a sibling `do-work/` tree. If only `do-work/` exists, that is `legacy-dir` — migrate via conformance, don't dual-write |

## 22. Private UI Vite must start from the worktree app package

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| UI screenshot is a default Vite page, 404, or the main checkout app instead of the REQ change | `npx vite` ran from process CWD (or repo root), not the worktree package that owns `vite.config` / `package.json` | `cd` into `{worktree}/<app-package>` before starting a **private** evidence server; pass an unused `--port` (never the shared 5173 / project.test host). Confirm the ready URL is that private origin, then screenshot. Stop the private server when the step ends |
| UI screenshot connection-refused after a "Vite ready" log | The start command was bound to a short tool timeout; the wrapper killed the process group when that call returned/timed out | Start the private server as a **long-lived** process (no short wall-clock kill on the start command). Confirm the private port still listens immediately before screenshot. Stop the server only after the PNG is on disk |
| UI screenshot of the shared `*.test` / Herd origin shows **old** behaviour while worktree tests are green | Live Herd/nginx serves the **main checkout** `public/build` (no `public/hot`); worktree JS is not on that origin | Do **not** treat the shared project.test host as proof of a worktree frontend change. Start a **private unused-port** Vite whose root/alias loads the **worktree** source (or a tiny harness that mounts the changed component) and screenshot that origin |
| Private Vite listens but every path returns **HTTP 404** (empty body) | Worker passed a harness HTML path as a **positional** Vite CLI arg (`npx vite … harness.html`); Vite treats that as a wrong root, so `/` and `/harness.html` both 404 | Start Vite with **no** HTML positional: `cd {worktree}/<app-package> && npx vite --host 127.0.0.1 --port <free> --strictPort`. Open `http://127.0.0.1:<port>/harness.html` (file under package root). Confirm `curl -s -o /dev/null -w '%{http_code}'` is 200 before screenshot |
| Need a second UI state (tab click) but `playwright screenshot` CLI cannot click | CLI is navigate+wait only | Prefer a temporary harness `?tab=` (or similar) query that auto-selects the state after mount; or script with Playwright Python/node API. Do not hang forever on a selector that only appears after an unsent click |

## 23. Policy `.env.*` matches committed `.env.example`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worker is `done` with tests green, then `check-policy.sh` exits 1: `blocked_path: …/.env.example matches .env.*` | Default `security.blocked_paths` includes `.env` and `.env.*`. The glob is unanchored-suffix: `.env.example` is a public template, not a secret file | Do **not** merge/archive. Treat as `policy-blocked`. Before the next run that must document an env var, narrow `security.blocked_paths` so `.env.*` does not match `.env.example` (keep `.env`, add explicit secret siblings like `.env.local` / `.env.production`). Then `/do-work resume` the stopped REQ — the feature branch can stay. Never bypass the policy gate silently |

## 24. Linear Issue slug lookup is zero-padded; evidence checker needs the project root

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `get_milestone` / `read_ur` for `UR-30` returns not-found while `UR-030: …` exists on the product Project | Capture allocated a zero-padded `UR-NNN` slug; operator typed the unpadded form | List product-Project milestones and match `**UR-id:**` / name prefix `UR-0*30` / `UR-30`. Accept both padded and unpadded operator args. Do not hard-stop on the first exact-name miss |
| `check-acceptance-evidence.sh` says `ui screenshot file missing` though the PNG exists under `{project}/.do-work/user-requests/…/ui-evidence/` | The REQ snapshot was written under `/tmp` (Linear has no working/ file); the script walks up from that path and never finds `{project}` | Write the Linear body snapshot under `{project}/.do-work/state/` (or another path inside the project) before calling the checker so `resolve_project_root` lands on the real app |

## 25. Close web walk: wait for SPA hydrate before screenshot

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Playwright `screenshot <url>` of a Vite SPA is a blank dark page; every route PNG is the same tiny size | The CLI captures the empty `#app` shell before Vue mounts | Use `--wait-for-selector` on a real heading/testid and `--wait-for-timeout`. Re-vision the PNG. If it is still blank, verdict is `not-reached`, not `closed` |

## 26. Close subagent must have Shell (or suite output)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Close cannot live-walk and cannot honestly emit `degraded:evidence-by-test` | Close was dispatched as a file-only subagent (no Shell / no Playwright) | Parent must grant **Shell** so close can run the covering suite (and a browser for web walks). If the harness cannot, the parent runs the suite and passes **exit code + passing/failing test names** into close. Do not treat unread test source as a passing suite unless the operator explicitly authorizes that fallback |

## 27. do-work-io `req.get` / `req.list` read shape — use wire fields first

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Verify/audit/worker needs Task text, layer/size, path fields, or suite after `req.get` / `req.list` | Older agents assumed get omitted body/path fields and reconstructed from local files | **Default:** treat `body`, `layer`, `size`, `entry_point`, `terminal_state`, `suite` as present on get/list (create/update persist; get round-trips). Use wire values; see `agents/tracker/do-work-io.md` read_req / list_reqs_for_ur. **Fallback only** if those keys are truly absent on an old server: snapshot under `{project}/.do-work/state/REQ-NNN.body.md` for evidence scripts / worker prompt, and `req.update` so the body is stored — do not invent a coverage miss from a missing key alone |

## 28. After worktree create: read and edit only under the worktree path

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worker implements against the wrong schema/names (or patches tests that don't match the integration base) while the worktree is correct | Main checkout has **dirty WIP** on the same paths; tools defaulted to `{project}/…` instead of `{project}/.worktrees/req-…/…` | After W2/W3.5, treat the **worktree absolute path** as CWD for every read/edit/test. Never use the main checkout tree for source of truth while implementing. Dirty main files are orchestrator/operator WIP — out of bounds |
| Pest `DatasetMissing` on red tests that reference new model constants in `->with([...])` | Dataset evaluates before implementation exists; undefined class constants collapse the dataset | In red phase, use **string literals** in Pest datasets; switch to constants only after they exist (or keep literals if clearer) |

## 29. Issue is product noun; wire stays `ur.*` / `UR-NNN`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Agent invents `issue.create` / `issue_create` / `ISSUE-NNN` / param `issue` after docs or UI say **Issue** | Product noun renamed; **wire deliberately frozen** at `ur.*` / slug `UR-NNN` / param `ur` / port ops `*_ur` | Use **Issue** in prose and reports. For MCP/port: still `ur_create`/`ur.create`, `ur`, `UR-NNN`. Tables may be `issues`/`issue_artifacts`. Do not invent capability names. On Linear: do-work Issue = Milestone; Linear Issue = REQ — never conflate |
| Markdown store probe still looks for `user-requests/` under do-work-io/sqlite/linear | Folder name is markdown-backend only; product noun change did not rename that path | Follow backend resolve: local `user-requests/` only when `backend: markdown` |

## 30. UI evidence path: checker wants user-requests, non-markdown uses evidence/

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `check-acceptance-evidence.sh` fails: `ui ref must be under .do-work/user-requests/*/ui-evidence/` though PNG exists under `.do-work/evidence/UR-NNN/ui-evidence/` | Worker followed sqlite/do-work-io evidence home; checker still hard-requires the markdown-era `user-requests/` path | Before the evidence gate: copy (or rewrite report `ref:`) the PNG to `{project}/.do-work/user-requests/UR-NNN/ui-evidence/REQ-NNN-step-….png`. Do not fail the REQ for path home alone. Prefer instructing workers to write both, or fix the checker to accept `evidence/` for non-markdown backends |

## 31. Submodule pointer merge needs the object in the main checkout

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Parent merges `req/*` cleanly (only a submodule SHA change) but `git -C <submodule> checkout <sha>` fails with `unable to read tree` / missing object | Worker committed the submodule tip **inside the worktree's nested clone**; that object never existed in the main checkout's submodule clone | After Stage B merge of a submodule-pointer commit, `git -C {project}/.worktrees/req-…/<submodule> rev-parse HEAD` and `git -C {project}/<submodule> fetch {worktree-submodule-path} <sha>` then `checkout <sha>` (stash local dirt first). Do not tear down the worktree until the main submodule can resolve the recorded SHA. Prefer workers that also push the submodule tip when a remote exists |
| `git submodule status` shows `+` after merge while parent index is clean | Main submodule working tree still on an older tip | Same fetch+checkout; then re-check `git submodule status` is clean (no `+`) before archive/final suite |

## 26. do-work-io capture must populate REQ body before go/run

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `req.get` returns ACs + files but empty/missing `body` (no Task / Verification Steps); workers under-spec or invent steps | Capture created REQs with title + structured fields only and never wrote the markdown body | In **audit** (before claim) or at capture end: `req.update` with full `## Task` / `## Context` / `## Integration` / `## Verification Steps` body. Path-units also need `entry_point` + `terminal_state`. Do not dispatch workers on AC-only shells |
| Path-unit claimable before children | `depends_on` left empty on Layer:none parent | After capture, set path-unit `depends_on` to all child slugs before go, or workers re-implement / fail verification |

## 32. Pixel-perfect UI briefs: read mockups first; durable evidence copy

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Intake brief invents wrong layout (e.g. dark 3-col when mockups are light Linear) | Agent summarized from placeholders without vision-reading attached images | **Before** writing inventory into the Issue brief: open each attached image (session `images/` or message assets) and describe only what is visible |
| Workers cannot open mockup paths under `/Users/…/.grok/sessions/…` later | Session media is ephemeral | During start/capture, **copy** mockups into `{project}/.do-work/evidence/UR-NNN/mockups/` and cite those paths in REQ Context / Assets |

## 33. Vue private harness: use `RouterView` component, not `h('router-view')`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Harness mounts `#app` but body stays empty; `html` shows raw `<router-view></router-view>` tag; console `No match found for location with path ""` | `createApp({ render: () => h('router-view') })` does **not** resolve Vue Router’s component — browser treats it as an unknown native element | Import `{ RouterView }` from `vue-router` and `h(RouterView)`; `await router.push(...); await router.isReady()` before `app.mount` |

## 34. do-work-io install: MCP usable ≠ PAT in process env

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `/do-work install` for do-work-io can `search_tool` loop tools, but `${token_env}` is unset in the agent shell | Host MCP already has the Sanctum PAT in its server headers; it was never exported as `DOWORK_IO_PAT` | Treat MCP discovery as “tools usable.” Write `tracker.backend: do-work-io` + `base_url`/`project`/`token_env`/`mcp_profile`, then `project.ensure`. **Do not** paste the token into chat or config. Report PAT unset for Load Config 7c / non-MCP shells. Do **not** hard-stop install solely because the process env lacks the PAT when MCP already answers. |

## 35. Parallel merge of shared registration files (provider/routes)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Parallel REQs each add capabilities/routes; after Stage B “ours” resolution, suite fails with missing capability or 404 | Multiple workers edit the same ServiceProvider CAPABILITY_CLASSES list and routes.php; conflict resolution that keeps **ours** drops sibling registrations | After serial Stage B merges that touch shared registration files, **union** CAPABILITY_CLASSES / route groups from each feature tip (or re-read each worktree file before teardown). Never “keep ours” alone for registry/router hubs. Re-run full suite on integration base before archive of the wave |
| Page/DTO helpers diverge (e.g. `toArray` missing) after add/add conflict | Same: partial DTO kept from one branch | Prefer the fuller DTO (methods used by any sibling) or re-copy from the worktree that owns the consumer capability |

## 36. Realtime path-unit walk: Echo key + CORS origin before second-actor

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| SPA open and API mutations succeed, but UI never hydrates; no `/broadcasting/auth`; WS hits wrong app key or never opens Reverb | Shared Vite process inherits a **shell** `VITE_REVERB_APP_KEY` that overrides `.env.local`; or SPA origin is not on `CORS_ALLOWED_ORIGINS` | Before second-actor claim/status/archive: start a **private** Vite with explicit matching Reverb env (`env -u VITE_REVERB_APP_KEY VITE_REVERB_APP_KEY=<server-key> …`), confirm `import.meta.env` shows that key and CORS preflight for that origin returns `Access-Control-Allow-Origin`. Prefer the pre-allowlisted private port if the project already has one. Do not treat the shared Herd/SPA host as proof when its baked/process env diverges from server `REVERB_APP_KEY` |
| list-account only on first paint, never after mutations | Echo never subscribed (wrong key / failed auth) | Fix key+CORS first; then assert WS to Reverb `app/<key>` and ≥1 list-account after the first second-actor mutation before vision-passing the UI step |

## 36. Parallel workers expanding footprint onto shared env docs

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Parallel REQs declared disjoint footprints but both rewrite `packages/*/ .env.example` (or README); Stage B hits content conflict | Workers expanded footprint for docs that "belong" to every local-recipe REQ | Prefer **union resolve** on shared env/docs (keep both comment blocks + keys), never "ours" alone. Optionally claim env-doc REQs serially when both touch the same example file. Re-run related suite after merge |
| Merge blocked by dirty same path on main checkout | Worker or local tool edited main tree mid-run | `git checkout -- <path>` only when the feature tip already carries the intended change; then merge. Re-assert integration base first |

## 37. Final suite after a schema REQ — drop-table teardown vs migration `down()`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| REQ-scoped tests pass and archive; the **final** suite fails in unrelated tests that `Schema::drop` a table, then RefreshDatabase rolls back a later index/`alter` migration | Worker only ran the REQ filter. `down()` assumes the table (and index) still exist. Another test dropped the table first | When a REQ adds or changes a **migration**, do not treat scoped tests as the wave gate. After merge, run the full suite (or at least files that drop that table). Make `down()` no-op if `Schema::hasTable` is false (or `dropIndexIfExists`) **before** archive of the schema REQ |
| Final suite is the first failure | Orchestrator archived on REQ-filter green | Same: schema REQs require a full-suite (or teardown-adjacent) pass before archive |

## 38. Close web walk: clear session between public and authed scenes

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Login (or other public) scene never reaches its testid after earlier authed scenes; wait times out | Same Playwright context keeps `sessionStorage` tokens; the SPA router redirects `/login` → dashboard | Before a public-route scene: logout / `sessionStorage.clear()` in the harness, or use a fresh browser context. Do not reuse leftover tokens across close scenes |

## 38. Multi-Issue close args (`UR-001/005`)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Operator runs `/do-work close UR-001/005` (slash or space list) | Expects multiple Issues closed in one turn | Parse as **multiple** Issue slugs (split on `/`, `,`, whitespace). For each open Issue: full close walk + one `write_close_report`. Already-closed Issues: report closed_at and skip rewrite unless operator asks re-close. Do not invent a nested path `UR-001/005` as a single id |

## 38. do-work-io bulk create_req hits per-minute rate limit

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Capture mid-UR fails with `rate_limited` / HTTP 429 on `req.create` after ~15–20 creates | Free/control profile enforces per_minute rate on capability bus | Pace creates (~1/s), retry 429 with exponential sleep (15s+), finish deps in a second pass after creates. Do not dual-write markdown REQs. Do not re-create already-allocated slugs — list_reqs_for_ur and resume remaining titles only |

## 39. Missing config.yml + live do-work.io MCP → do not markdown-close

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `/do-work close UR-NNN` closes a local `user-requests/archive/` ghost or invents `no-path-units` while the real Issue is open on do-work.io | Project has no `.do-work/config.yml` (or backend unset → markdown default) even though the host already has a working `dowork` MCP and a project slug matching the git basename | Before any markdown Issue/REQ read: if `search_tool` finds do-work.io tools, **hard-stop or re-resolve** — write/load `tracker.backend: do-work-io` + `tracker.dowork.project` (slug = basename or `project.list` match), then `ur_get` / `req_list` / `ur_write-close-report`. Never treat local archive as store truth while MCP project exists. |
| Close finds wire `entry_point`/`terminal_state` null but body has `**Entry point:**` / `**Terminal state:**` | Capture stored path fields only in body | Parse body path headers as path-unit fallback; prefer `req.update` next capture to set wire fields |
