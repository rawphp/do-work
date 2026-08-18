# do-work field lessons

No pending field lessons. New lessons may be appended by the post-skill field-lessons loop.

**Only lessons that improve the next do-work run.** Gate before every append:
**“Will this improve do-work?”** — Yes → here (skill process: claim, worktree,
verify, merge, tracker, recovery). No → project `AGENTS.md` / docs (session-capture),
not this file. No product names/ticket ids as substance. Prefer portable
orchestrator procedure over product/framework recipes (Vue/Echo/app-specific).

## 1. do-work-io path fields: keep wire `entry_point` / `terminal_state` short

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `req.update` fails with MySQL `String data, right truncated` on `entry_point` / `terminal_state` | Wire columns are short VARCHAR; capture put the full path prose there | Put the long Entry/Terminal text in the REQ **body** headers; set wire `entry_point` / `terminal_state` to a **short** one-line summary (under ~100 chars). Do not treat body path fields alone as missing when wire is null on older rows — still prefer setting short wire values for close/verify |

## 2. Linked vendor can load classmap files from the main checkout

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worktree tests boot, `App\` edits apply, but seeder/classmap edits are invisible (`ReflectionClass` path is the main checkout) | `provision-worktree.sh` `linked: vendor` — Composer `$baseDir` is the real vendor parent, so classmap (seeders, optimized `App\`) resolves to main | If a worktree edit is not the file PHP actually loads, remove the worktree `vendor` symlink and run real `composer install --no-interaction` in the worktree. Do not `composer dump-autoload` against a symlink. Confirm with `ReflectionClass` on the touched class before treating red/green as authoritative |
| Pest ignores worktree route/middleware edits while `php artisan route:list` in the worktree shows the new gates | Same symlink: Pest/Composer root is the main checkout, so the HTTP kernel loads main routes | Same default action. After a real install, if tests then fail with `MissingAppKeyException`, copy gitignored `.env.testing` from the main checkout (see §3) before treating red/green as authoritative |

## 3. Copy gitignored env into the worktree before framework tests

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worktree suite hits the host shared `*_test` DB (deadlocks, drop-table races) even when phpunit pins `WARP_DB=true` | `provision-worktree.sh` links `vendor` / `node_modules` but does not copy gitignored `.env` / `.env.testing`; framework boot then falls through to the host server | After provision, if `.env` / `.env.testing` are missing in the worktree, copy them from the main checkout. Do not commit them. Do not treat a shared-DB deadlock as an implementation failure — copy env and re-run |

## 4. Verification `--filter=` must match a consecutive test-name token

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| REQ verify `php artisan test --filter=FooBar` never runs the new tests | PHPUnit/Pest `--filter` is a regex on the **test name**; a file like `FooXBarTest` does not contain the consecutive substring `FooBar` | Put the verify filter token in `describe()` / `it()` / `test()` (or name the file so the token is consecutive). Do not assume the filename tokens concatenate into the filter |

## 5. Run worktree tests from the worktree CWD

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `npx vitest` / `npm test` from the main checkout is green but never executes the worker's new specs | Consumer `vitest.config` excludes `.worktrees/**`; relative paths resolve to the main tree | After W2/W3.5, `cd` to the worktree absolute path before every test or private UI server command. Do not pass worktree-relative paths while CWD is the main checkout |

## 6. Host-routed SPA screenshots: use host:port, not Host rewrite

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Playwright `page.route` Host rewrite on `http://127.0.0.1:PORT` returns 404 / the wrong app | The first navigation may not apply the rewritten Host; the app selects the SPA from `request()->getHost()` | Start the worktree app on an unused port and open `http://{expected-host}:{port}` when loopback DNS already exists. Confirm HTTP 200 for the intended shell before login/screenshot |

## 7. Worktree UI screenshots: do not reuse a stale main `public/build`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Login on the private worktree server succeeds but the SPA lands on the old post-login route / shows the pre-child nav | `public/build` was copied or symlinked from the main checkout and predates the integration-tip frontend (Vite manifest older than the merged child commits) | Remove the symlink/copy and run the worktree-local production build so the private server serves this branch’s assets. Confirm the new hashed files are in the login HTML before screenshot. Do not treat the shared host’s built SPA as the worktree UI |

## 7. Close: remote tracker IDs are not the local app fixture

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Close web walk 404s / “not found” for the Issue or REQ slug that exists on the tracker | Tracker backend is remote; the merged app’s local DB is a different store | Walk the **same entry-point surface** with a representative local record (same status/shape). Do not mark `not-reached` solely because the remote ULID is missing locally. `not-reached` is only if the route/component cannot hydrate at all |

## 8. do-work-io: MCP mount is enough when the shell PAT is empty

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Orchestrator hard-stops at Load Config 7c because `${token_env}` is unset, even though `search_tool` already lists authenticated loop tools | PAT lives in the MCP host config, not the agent shell | If tools are discoverable and a read op succeeds, treat MCP as usable. Do not hard-stop solely on an empty process env. Still hard-stop if tools are missing or calls return 401 |

## 9. Kill leftover worker UI servers before Stage B / final suite

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| After the worker returns, a private Vite/dev server is still bound and `.worktrees/req-*` has leftover `.vite` dirs | UI evidence started a long-lived process; worktree remove does not always kill it | After worker YAML (or on hard-death), stop that server. Then tear down the worktree. Do not leave a bound port into merge or the final suite |

## 10. Acceptance-evidence UI refs still need the user-requests path

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `check-acceptance-evidence.sh` fails on a remote backend even though PNGs exist under `.do-work/evidence/UR-NNN/ui-evidence/` | The checker only accepts `.do-work/user-requests/<UR>/ui-evidence/` | Dual-write the PNGs to that path (already in run-worker field traps) **and** rewrite report `ref:` / checkpoint command lines to the user-requests path before running the gate |

## 11. Directory-level footprint globs serialize parallel siblings

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `--parallel N` only claims 1 REQ while many backlog items look independent | Declared `**Files:**` uses a directory prefix (`app/Services/`, `routes/`) shared by siblings | Prefer leaf paths in footprints at capture time. If already claimed, run serial; do not force-claim past `footprint-overlap`. After archive, refill window. |
| Full suite `tail` loses failure inventory | Piped suite output through `tail` before exit | Write suite log to a file first (`tee`), then summarize; never rely on tail-only for Step D attribution |

## 12. Scoped run must filter claimable by Issue

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `/do-work go UR-NNN` claims a REQ from another Issue after the scoped backlog drains | Remote `list-claimable` is project-wide; empty scoped set still returns other Issues' claimable rows | When the run is scoped to `UR-NNN`, only claim REQs whose parent Issue matches (via `req.list` for that UR, or `req.get` parent check). Never treat the first project-wide claimable row as in-scope. |

## 13. Stage A reviewer stuck — kill and re-dispatch narrow

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Independent review subagent runs 10+ min with many tool calls and no YAML verdict | Broad “explore the repo” reviewer prompt; reviewer wanders past the diff/report | Kill the stuck reviewer. Re-dispatch with an explicit allowlist: body snapshot, worker report path, diff path, policy exit — “do not explore the whole repo.” Do not block Stage B siblings on one stuck review. |

## 14. Final-suite failure outside this Issue’s footprint

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Config `suite_command` fails after the Issue backlog drains, but `git log` for this Issue’s REQ subjects never touches the failing package | Ambient debt on the integration base / other Issues | Attribute via `git log` / path ownership first. If no REQ from this run owns the path, fix as a separate hygiene commit on the integration base (or note residual) — do not reopen archived REQs or invent ownership. |

## 15. Private Vite UI evidence must use a CORS-allowlisted origin

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Private worktree Vite boots, but injecting a session PAT still lands on `/login` with console CORS errors on `auth.whoami` | API `CORS_ALLOWED_ORIGINS` lists only shared ports / HTTPS hosts; the private unused port is not on the allowlist | Prefer a private port **already** present on the API CORS allowlist, or temporarily extend the gitignored API env allowlist for that port (do not commit). Confirm whoami succeeds from that origin before screenshot. Do not treat login redirect alone as missing chrome. |

## 16. Contested shared panel: wire from parent, do not set-files past overlap

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Mid-flight `req.set-files` fails `footprint-overlap` on a shared tab/panel leaf a sibling also claimed | Worker added a slot/prop on the contested panel instead of composing from the parent view | Prefer a dedicated control component owned by this REQ and mount it from the parent detail view (sibling of the panel) when the dispatch footprint note says to minimize overlap. Do not force-claim the contested path; drop it from staged files and keep the panel untouched. |

## 17. Component-mount HTML dump for store-permission UI steps

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `ui` step only needs nav/chrome under simulated store permissions, but private SPA boot+login is disproportionate or CORS/port blocked | Full Vite private-server path is for live shells; permission-gated chrome can be proven from the component | Mount the target component (test-utils + sales/ops permission fixture) → write HTML → Playwright PNG → vision-assert. Still dual-write evidence paths. Do not skip the PNG+vision contract. |

## 18. Schema-last: do not `Schema::create` in behaviour tests under Warp

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| First behaviour test is green; the rest fail with host `*_test.migrations` missing or `Host: 127.0.0.1` despite `WARP_DB=true` | `Schema::create` is DDL (implicit commit) and `$this->artisan()` can resolve from the warm base app, not the sandbox fake | For schema-last REQs: inject an in-memory collaborator for selection/idempotency tests; add the migration last; then add a thin persistence test against the real table. Do not `Schema::create` inside Warp/RefreshDatabase behaviour tests |
