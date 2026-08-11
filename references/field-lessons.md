# do-work field lessons

Portable patterns for future do-work runs (any project). Read at skill start when present; append at end of runs that teach something transferable.

---

## 1. Linear `save_milestone` patch vs full replace

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| MCP `save_milestone` with `patch` fails: `Invalid arguments` / validation error | Host or schema rejects nested `patch` ops (or anchors don’t match Linear’s normalized markdown) | Prefer **full `description` rewrite** (read → merge sections → write). Never dual-write local `user-requests/` |
| Partial section update needed (`## Ideate`, `## Clarifications`, `## Verify`) | Same | Rebuild description: keep `## Brief` verbatim; replace only the target section; write full body |
| **`## Brief` / Capture summary vanish after verify** | Agent passed **only** the new `## Verify` block as `description` — Linear **replaces** the whole field | **Always** read current description → splice section → write **full** body. Size spill: short `## Verify` pointer in description + full report as **milestone comment** (`<!-- do-work-verify-report -->`). If wipe already happened, restore from session MCP dump / GraphQL immediately |
| MCP write flaky mid-session | Transport / size | Retry full replace once; GraphQL `projectMilestoneUpdate` only if MCP remains unusable **and** operator env already has Linear auth — still no markdown store fallback |

---

## 2. Linear deps: relations API, not `IssueUpdateInput`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Cannot set `blockedBy` on issue update | `IssueUpdateInput` has **no** blocks fields | Use `issueRelationCreate` with `type: blocks`, `issueId` = **blocker**, `relatedIssueId` = **blocked** |
| Claim eligibility wrong after capture | Only body `**Depends on:**` written | Dual-write: relations authoritative + body mirror (port rule) |
| Path-unit never claimable | Parent not blocked by children (or reverse) | Path-unit Issue **blocked by** layer children; leaf deps as hard edges only |

---

## 3. “Is the dependency already done?” — verify before re-asking

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Grill asks hard-dep on a side-track; operator says “I thought that was done” | Brief still says “recommended” / “depends on” after the work shipped | **Check Linear** (UR milestone / Issues → Done) **and** repo evidence (release workflow, tags, install script) before asking again |
| Confirmed done | Side-track complete | Record clarification: treat as **existing infrastructure**, not a hard wait; still note residual gaps (e.g. extra GOOS in matrix) |

Do not invent “still open” from plan prose alone when the product Project shows Done.

---

## 4. Multi-stream phase plans — grill the decomposition forks

For large multi-workstream briefs (Windows + billing + updates + …), ideate gaps are high-impact. Prefer **Grill** questions that change REQ graph shape, not polish:

| Fork | Why it changes capture |
|------|-------------------------|
| Billable entity (workspace vs user) | Migrations, Cashier model, portal ownership |
| Runtime acceptance bar (unit/compile vs CI vs manual smoke) | Verification Steps + done criteria |
| Control-loop thrash policy (hysteresis, cooldown, manual resume) | Domain AC + agent loop REQs |
| Placeholder vs real integration (SSO hook depth) | Scope of leaf REQs |

Self-answer pass still batches confident codebase inferences first (composer packages present, existing columns, heartbeat fields).

---

## 5. Bulk Linear `create_req` under a large plan

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Capture of 15–25 Issues is slow / times out | Serial MCP + full bodies | Batch creates with stable §9.2 bodies; set labels (`Layer/*`, `Size/*`, `path-unit`); **then** a second pass for relations + `**Depends on:**` mirrors |
| Milestone description huge | Full plan pasted into `## Brief` | Intake may keep full plan; subsequent section updates should not truncate Brief when editing Ideate/Capture — merge carefully |
| cycle-check.sh fails under Linear | Script is markdown-path | Under `backend: linear`, treat relation graph as authority; don’t halt solely because local `REQ-*.md` cycle-check finds nothing |

---

## 6. Field-lessons write exception

Skill install trees are often “read-only at runtime” for product work. **Exception:** appending or creating this file (`references/field-lessons.md`) under the do-work skill root **is allowed** when a run produced portable lessons — do not skip capture because of the generic skill-dir rule.

---

## 7. Monorepo worktrees: `vendor` symlink depth + Laravel base path

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `provision-worktree.sh` leaves `packages/*/vendor` unprovisioned | Auto-detect only walks **depth ≤ 1** from worktree root; `packages/server/composer.json` is depth 2 | Configure `worktree.link_paths: [packages/server/vendor, …]` **or** run `composer install` inside the package worktree path before tests |
| Symlinked `vendor` → main checkout: `config()` / app boot hits wrong tree; new worktree classes “not found” or tests pass against main `app/` | Laravel `Application::inferBasePath()` uses Composer ClassLoader root (= main `packages/server` when vendor is a symlink) | Prefer **real `composer install` in the worktree package** for PHP monorepos. Alternative: set `APP_BASE_PATH` to the worktree package root for test runs — do not assume symlink vendor is safe for PSR-4 load of worktree code |

Portable rule: for Laravel packages under `packages/<name>/`, treat symlink-vendor as a **smoke shortcut only**; TDD that adds classes under the worktree needs a worktree-local autoload (install or path fix).

Same depth trap for **`packages/web/node_modules`**: empty `worktree.link_paths` + depth-1 auto-detect → worktree has no JS deps. Symlink `packages/web/node_modules` from the main checkout (or set `link_paths`) before `npm test`.

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `node_modules/vitest: Too many levels of symbolic links` after manual `ln -s` | From worktree `packages/web`, relative `../../packages/web/node_modules` resolves **into itself** (worktree root is only two `..` up), not the main checkout | Symlink with an **absolute** main-checkout path, or count parents to the monorepo root (`../../../../packages/web/node_modules` when worktree is `{repo}/.worktrees/<name>/packages/web`). Prefer `worktree.link_paths` so provision does this correctly. |

---

## 8. UI evidence for auth-gated SPA forms

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `ui` step needs “form visible for owner” but Playwright only reaches login | Real SPA route requires session; worker has no seed credentials | Serve a **temporary** root HTML entry in the package (`evidence-*.html`) that mounts the real component with props (`canEdit: true`) and a **mocked `fetch`** for the settings API; screenshot that; **delete the HTML before commit** |
| Main checkout Vite already on :5173 | Parallel / stale main dev server | Start worktree Vite on a free port (`--port 5199 --strictPort`); do not assume the main-checkout server has worktree code |

Still vision-assert the PNG (enabled + thresholds + locked weights / save). Do not commit evidence HTML or pass on a11y-only scrapes.

---

## 9. Parallel web REQs sharing one view file

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Two workers both claim `SettingsView.vue` (or similar shell) | Footprint lists component dirs only, not the shared mount view | Expand `**Files:**` to include every shell/layout file the worker will edit; at claim time treat view mounts as exclusive if both REQs name the same path |
| Auto-merge succeeds but double-mounts UI | Both REQs added adjacent sections | Prefer path-unit parent to do mount wiring after leaf components land, or claim shell view serially |

---

## 10. REQ AC / task title beats plan step comments

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Plan Task N says “v1 no-X” but Issue Task/AC requires X | Capture applied a clarification override; plan doc not rewritten | Implement **Issue AC + Task**, not stale plan comments. Cross-check design § clarifications when titles diverge (e.g. prefer-cmux dedup vs “v1 no dedup”) |
| Worker ships plan-literal no-op and fails AC | Read plan before Issue body | Always treat Linear Issue (or markdown REQ) as the closure oracle; plan is scaffolding |

---

## 11. Child-resource payloads need parent link diagnostics

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| UI pane/session view cannot show agent online / hb without machines store | Child list/get payload only maps the child row | Extend the **shared payload helper** (not controller + cap twice) with parent-link fields (`last_heartbeat_at`, `agent_version`, optional derived `agent_online`) |
| List endpoint N+1 on link lookup | Payload always re-queries per row | Optional preloaded link arg; **batch-load** links in list authority (unique by machine/host key), pass through |
| Online bool drifts from client filter | Server invents a different stale window | Mirror the UI threshold constant (document the match); prefer raw ISO heartbeat + bool both when chips need either |

Do not invent stream-persistence columns for “honest empty stream” when client already owns WS/chunk evidence — only expose server-known diagnostics.

---

## 12. Live chip must require stream evidence (not transport-up)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Empty terminal shows green “live” / header “Live” | Status machine maps WS `connected` → live; header reuses “Live” for transport | Gate **live** on chunk/output evidence only; `connected` → **waiting**; silence → **idle**; offline distinct. Rename header transport chip to “Stream on/off” so it never collides with pane live |
| Blank pane with no “why” | Empty copy ignores agent heartbeat | When silent, append agent online/offline + last-hb age from parent-link diagnostics (see §10) — pure helpers, unit-tested |
| Dual status chrome confuses users | App WS chip vs pane stream chip use same word | Keep transport wording separate from pane stream evidence wording |

Portable rule: **transport connected ≠ product live**. Chips and empty-state copy must say waiting/idle/offline until evidence arrives.

---

## 13. GoReleaser GOOS vs self-update asset contract

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Windows release added as zip; agent update fails | Self-update client hardcodes `AssetName` → `*.tar.gz` and `ExtractBinary` only understands tar.gz | Keep **tar.gz for every GOOS** until the update client is taught zip; document the contract next to `.goreleaser.yaml` |
| Matrix builds unwanted `windows/arm64` | `goos × goarch` cartesian product | Use `ignore:` for unsupported pairs; ship only the arch the AC names (e.g. windows/amd64) |
| Docs say “or defer” but compile is CGO-free | Untested assumption that Windows needs CGO | Cross-compile smoke (`GOOS=windows GOARCH=amd64 go build`) before deferring the matrix entry |


---

## 14. Agent dual-loop: share one stream Registry

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Heartbeat Converge and command Start each create a Registry | Run helpers construct their own lifecycle maps | Wire **one** Registry in main; pass into both loops (heartbeat Converge + create_pane Start) |
| Double stream POST for same pane_id | Independent cancel maps; Converge cannot stop command-started streamers | Shared map is the fix — not “stop all on converge” hacks |
| Wiring hard to unit-test | Run hardcodes HTTP client | Extract `RunLoop(ctx, Heartbeater, Converger)` with interfaces; fake Heartbeat response + recording Converge |

Portable rule: when two concurrent loops own the same supervisor resource (streamers, connections), construct once at the process root and inject — never let each loop default-construct its own.

---

## 15. Hysteresis demotion tests — clock from challenger_since

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Demotion never fires at “T+30s from first beat” | Challenger timer starts only when the higher-ranked key appears; first beat has no challenger | Advance time **≥ hysteresis window after `rank_challenger_since`**, not after the first select beat |
| Mid-beat keeps the lower streamer | Correct hold under hysteresis | Assert challenger_key/since set and ideal key still `available` until elapsed |

Portable rule for control-loop thrash tests: freeze time (`setTestNow`), inject `now` into the authority, and measure hold/release against the persisted challenger timestamp.

---

## 16. Multi-UR concurrent merges on shared integration branch

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Stage B merge conflicts in shared shell views (`PaneView.vue`, stores, API clients) though REQ footprints were disjoint | Multiple URs land on the same integration branch (`new-work`) in parallel; footprints only exclude **in-flight** claims, not already-merged sibling URs | Resolve conflict by **keeping both** feature sets (do not drop either side’s fields). Prefer combine-not-choose for additive UI. Re-run package tests after conflict fix before archive |
| Footprint looked free at claim | Other UR merged between claim and integrate | Same — Stage B conflict path is expected under concurrent go runs |


---

## 17. Concurrent integration-base advance mid-parallel wave

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worker branch merges with content conflict on shared core (e.g. stream Registry) | Sibling UR/session merged into `new-work` while workers ran on older tip | Rebase/resolve onto **current** base before archive; re-run package tests for the conflicted package |
| `Stop`/`Start` API shape drifted (map of cancels vs entries) | Another REQ refactored the same type | Port the new method onto the **new** structure; do not force-old map over newer Converge design |
| Path-unit still Todo while all layer children Done | Relations never blocked path-unit on children | After last leaf archives, **close path-unit** with run-note (children Done) so dep chains (e.g. Upgrade path blocked by free-slot path) unlock |

Portable rule: parallel waves assume disjoint **Files:** but not a frozen integration tip — always merge against live base and treat path-unit Done as a graph unlock, not a second implementation pass.

---

## 18. Hard-cut route keys — fake side effects on the reject path

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| “Integer/old key → 404” feature test gets **500** (e.g. Pusher/broadcast) while red | Old key still binds; handler runs and hits real side effects | `Event::fake()` (or equivalent) on **both** ULID-ok and reject cases so a binding regression fails as 200/≠404, not infra 500 |
| Only put binding on one model | Routes type-hint several public models | Prefer `getRouteKeyName` + `resolveRouteBinding` on the shared public-id trait (`Str::isUlid` guard) so agent + HTTP surfaces stay aligned |

---

## 19. Public ULID hard-cut: one resolver, reject digits

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Caps still authorize when client sends `"1"` / integer PK as string | Lookup uses `find($id)` or `where('ulid', $id)` without rejecting pure digits | Central **`PublicId::find/findOrFail`**: require `Str::isUlid` **and** `!ctype_digit`; never fall through to PK |
| Payload helpers emit mixed int/string ids | Mapped `$model->id` in list/detail helpers | Emit only `PublicId::require($model)` for `id` and related `*_id`; load parent relations for FK public ids |
| Input DTOs still typed `int $workspace_id` | Schema lag after column migration | Change capability Input/Result id fields to `string`; resolve once at authorize/run edge; keep domain authorities on internal int PKs |

Portable rule: **external surface = ULID only; internal domain = bigint**. Reject digit-only public keys at the boundary so PK leaks cannot authorize or round-trip.

Agent/device wire is external too — not just HTTP/caps:

| Surface | Must emit public ULID |
|---------|------------------------|
| Claim complete `machine_id` | Device identity after claim |
| Heartbeat `desired_streams[].pane_id` | Stream targets for agent |
| Command poll wire `command_id` / `machine_id` + payload `pane_id` | Long-poll + create/destroy/send_keys |
| Agent attach/state response `pane_id` | Agent→server ack |

Do not leave `$model->id` in those paths after a hard-cut; audit `toWire` / DTO `toArray` / enqueue payloads in the same REQ as route binding.

---

## 20. SPA public-id hard-cut: fixtures + exceptions

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Suite fails only on `toEqual([1])` / URL `/workspaces/3/` after types are already `string` | Bulk-replaced object fields but not **call args** and **expected values** | When converting entity ids to ULID strings, rewrite fixtures, `toHaveBeenCalledWith`, URL regexes, and chip `value:` expectations in the same pass |
| Accidental conversion of PAT / Sanctum token `id: number` | “All `id: number`” codemod | Leave third-party / Sanctum token ids numeric until that surface emits public ULIDs; domain entities only (workspace/machine/pane/user) |
| Route/query still accepts `"12"` after cut | Client parser uses `Number()` / positive-int | Shared `parsePublicId`: ULID shape + reject pure digits; null out legacy localStorage int keys |

Portable rule: hard-cut client + tests as one unit; exclude non-public-id surfaces explicitly.

---

## 21. Go agent ULID hard-cut — empty sentinel, not zero

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Client parses claim/desired_streams but rest of package still `int64` | Only DTO fields flipped | Cascade **all** pane/machine/command id types in one REQ: config, commands, stream Registry maps, SessionName/ParseSessionName, attach/stream URL segments |
| Tests still skip on `paneID == 0` / `IsActive(0)` | Zero was the missing sentinel for int | Use **`""` empty string** as missing; `"0"` is a valid (legacy) id string and must not no-op Start/Stop |
| Resume ignores `ac-{ulid}` | ParseSessionName still requires digits | Accept non-empty suffix after `ac-`; reject only empty / wrong prefix |
| JSON number in old config fails Load | Hard cut: config `machine_id` is string | New claim rewrites config; fixtures use ULID strings — no silent int fallback |

Portable rule: external wire + local config + map keys + path segments change together; missing-id checks become empty-string, not zero.

---

## 22. Hard-cut identity: path-unit residual is a full suite, not a checklist

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Leaves green in isolation; path-unit `php artisan test` has dozens of 404/`validation_failed` | Feature/cap tests still pass **integer PKs** as route keys and capability `*_id` inputs | Path-unit owns a **full-package suite** pass after the last leaf; budget a residual “align tests to public id” pass (same UR) |
| Bulk `->id` → `->ulid` rewrites break Eloquent creates (FK constraint) | Codemod rewrote mass-assign `workspace_id`/`machine_id` on `Model::create` | Split surfaces: **external** (routes, invoke inputs, assertJson) use ULID; **internal FKs** stay bigint. Never codemod `create([...])` FK fields |
| `findOrFail($result->data->pane_id)` fails after result becomes ULID | Still treating result id as PK | `where('ulid', $publicId)->firstOrFail()` (or `PublicId::findOrFail`) |

Portable rule: hard-cut leaves may ship production code green with thin tests; the **path-unit gate** is the whole suite. Prefer targeted rewrites (URL strings + invoke arrays + JSON assertions) over global `->id` replace.

---

## 23. Duplicate UR-NNN milestones on one product Project

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `list_milestones` returns two `UR-018: …` names | Parallel intake / ship-loop used same next slug | Prefer milestone with open REQs + `Status: captured`; treat 100% progress / all Done as the closed twin. Do not dual-run both |
| `go UR-NNN` ambiguous | Same | Resolve by milestone id in run notes; consider renaming closed twin to avoid future collision |


---

## 24. Privileged PAT profile vs product profile name lists

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Adding a system/platform PAT profile breaks MCP/catalog parity tests that iterate `profileNames()` | Product mounts and privileged profiles were one list; tests expect every profile key in product MCP config | Split **productProfileNames()** (product mounts) from **profileNames()** (all mintable). MCP/agent config + parity tests iterate product only; mint validation uses all |
| Product tokens can call privileged caps | Scope gate treats SPA `*` as full power for every capability name | For privileged capability prefixes, deny `*` and product expansions; require explicit privileged profile allowlist |

Portable rule: when a new PAT profile must not appear on product MCP/CLI mounts, never fold it into the list parity tests treat as “must be mounted.” Gate privileged capability names separately from product `*` bypass.

---

## 25. Admin/SPA list UI evidence without temporary HTML

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Auth-gated list route exists but API is missing | Parallel server REQ not done | Playwright: seed `localStorage` session keys the SPA already uses, `page.route` mock list JSON, navigate to real route, screenshot |
| Evidence HTML would duplicate shell chrome | Route already mounts real view under shell layout | Prefer real route + mocks over a throwaway HTML mount; still vision-assert the PNG |

Portable rule: when the shell + route already land, inject session storage + intercept network instead of a temporary `evidence-*.html` (still delete any temp files if used).

---

## 26. Privileged capability catalog vs product surface-parity matrix

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Registering `system.*` (or other privileged) caps fails product surface parity that requires `agent` on every registry name | Privileged mount is http/mcp/cli only; product Manager needs agent | Split required surfaces: product = full set; privileged prefix = declared subset (and assert **not** on product agent mounts) |
| Catalog gap matrix regex only matches product `workspace\|machine\|pane.*` | Matrix was product-only | Add a **second matrix** for privileged names sourced from the PAT profile expansion; never fold privileged rows into the product matrix |
| Cap CRUD names exist but model is a sibling REQ | Catalog registration needs something to call | Ship **minimal** model + domain authority with the catalog cap REQ; leave product-side integration (quota waiver, HTTP controllers) to siblings |

Portable rule: privileged catalogs share discovery path but **not** product profile allowlists or product surface requirements — isolate in tests and PAT expansions (see §18).

---

## 27. Laravel monorepo worktree: `.env` for clean Pest

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Every Pest test is `WARN` with `file_get_contents(.../.env): Failed to open stream` | Real `composer install` in worktree package but no `.env` (gitignored; provisioner only links `vendor`) | Symlink or copy main `packages/server/.env` into the worktree package root before `php artisan test`. Assertions still pass (exit 0) without it — but WARN noise hides real failures; treat missing `.env` as part of Laravel worktree provision, not suite failure. |

Portable rule: for Laravel package worktrees, provision **autoload (vendor)** and **runtime env (`.env`)**; vendor alone is not enough for quiet green.


---

## 28. Cache store that normalizes on put — pass raw, wire the bound

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Store `truncated: false` though content was oversize | Controller pre-normalized then passed already-bound bytes into `put()`, which re-normalizes and sees size ≤ MAX | Pass **raw** content into the store (store owns normalize + truncated); assign **normalized** only to broadcast/response body |
| Double-work normalize looks “fine” in green tests that only assert string equality | Truncation flag / audit fields not asserted | Always assert `truncated` (or equivalent metadata) when the AC cares about bound storage |

Portable rule: one owner for normalize+metadata (the store); consumers that also need the bound payload call the same pure normalize helper for the wire, not the store’s return side-effect.


---

## 29. Integration-base checkout mid-parallel (Linear monorepo)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Merges land on unexpected branch (`ux/…`) while go started on `new-work` | Concurrent worktree holds `new-work`; shell checkout jumps; later Stage B merges follow current branch | Before every Stage B merge: assert `git branch --show-current` equals recorded ensure-integration-base tip. If another worktree owns the base, merge via that worktree (`git -C .worktrees/… merge`) or cherry-pick onto the base tip — never invent a new integration branch mid-UR |
| Sibling REQ UI disappeared after next packages/admin merge | Second worker branch started from pre-first-UI tip or overwrote shared router/nav | After each packages/* shell merge, `git log -1 --name-only` + re-check prior leaf files exist; if missing, restore from the prior REQ commit before archive |
| `php artisan test` in worktree fails facade root / wrong classes | Symlinked `vendor` from main checkout | Prefer real `composer install` in worktree package (field lesson §7); treat symlink as smoke-only |


---

## 30. Laravel monorepo worktree needs `.env` as well as vendor

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Pest tests WARN `file_get_contents(.../.env): Failed to open stream` after vendor install | Worktree has `composer install` but no `.env` / APP_KEY | Copy main checkout `packages/server/.env` (or `.env.example` + `key:generate`) into the worktree package before `php artisan test` |
| Symlinked vendor still boots wrong tree | ClassLoader base path | Prefer real `composer install` in worktree package (see §7); still pair with worktree-local `.env` |

Portable rule: provision monorepo PHP worktrees with **autoload + app env**, not vendor alone.

---

## 31. Privileged MCP mount isolation + tools/list pagination

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Product MCP parity tests fail after adding a system/privileged profile | Privileged profile was folded into `surfaces.mcp.profiles` (auto-register product mounts) | Keep product profiles list product-only; mount privileged path via a **sibling config key** (e.g. `system_mount`) + dedicated registrar after product boot |
| System PAT can list product tools (or product PAT hits system path) | Only tool allowlists differ; auth middleware is shared | Dual middleware: product mounts reject pure privileged tokens; system mount requires privileged PAT + admin flag (stricter than SPA `*` HTTP admin if AC says “system PAT only”) |
| Feature test “lists every system tool” fails though registry has all tools | laravel/mcp **paginates** `tools/list` (`nextCursor`) when allowlist > page size | Follow `result.nextCursor` until empty before asserting full name set |

Portable rule: privileged MCP = separate path + separate registrar + bidirectional token rejection; full-catalog assertions must paginate `tools/list`.

---

## 32. Playwright `page.route('**/api/**')` breaks Vite SPA module loads

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| UI evidence: blank app / MIME error loading `src/api/*.ts` as `application/json` | Glob `**/api/**` matches **Vite source paths** (`/src/api/client.ts`) as well as HTTP `/api/...` | Match only request **pathname** with `pathname.startsWith('/api/')` (or host+path), never a bare `**/api/**` substring |
| `addInitScript` + real route works after fix | Session seed was fine; route was intercepting ESM | Keep field lesson §19 session+route pattern; tighten the URL predicate |

Portable rule: in Vite monorepos, package folders named `api` live under `/src/api/` — Playwright network mocks must not treat those as backend routes.

---

## 33. Parallel `--parallel N` underused on shared HTTP footprint

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `--parallel 3` fills only 1–2 slots on a multi-CRUD admin UR | Every server leaf lists the same `routes/api.php` + `app/Http` + `tests` tree in `**Files:**` | Treat shared route/register files as exclusive: at most **one** in-flight server leaf; pair free slots with a **disjoint package** (e.g. admin SPA) |
| Path-unit residual blocks the whole package for a full worker | Path-unit `**Files:**` is broad (server + SPA) after children already Done | Residual-close with suite evidence + run-note (children Done) **before** leaf fan-out so pick order reaches implementable leaves |
| Claimable leaf already green on integration base | Prior residual / sibling landed domain+HTTP under a different issue id | Run the REQ’s verification filter first; if green and AC met, residual-archive — do not re-dispatch a full implement worker |

Portable rule: parallel width is limited by **declared footprint intersection**, not by N. Capture should keep shared choke files honest; run should residual-close ready path-units and already-landed leaves quickly, then fill N with non-overlapping packages.

---

## 34. Admin HTTP destroy ≠ product soft-end authority

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Guidance says “reuse DestroyX where safe” but admin DELETE 403s / RuntimeException | Product destroy checks controller/owner role (`canControl`) or only soft-ends state | Keep **Admin\*::delete** as hard-delete + audit (mirror sibling AdminMachine/AdminUser pattern); document why product soft-end is unsafe for platform admin |
| Admin list payload missing parent names | Shared payload only emits parent public ids | Extend **SystemXPayload** once with `workspace_name` / host context fields the admin SPA already types |

Portable rule: “reuse domain where safe” means role checks and lifecycle semantics must fit platform admin; when they don’t, extend the admin authority (audit + hard delete) rather than bypassing product access checks.

---

## 35. Vue evidence mounts: runtime-only build rejects `template:` strings

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Evidence page blank; console: "runtime compilation is not supported" / "alias vue to vue.esm-bundler.js" | Vite ships **runtime-only** Vue; `createApp({ template: '...' })` needs the full compiler build | Prefer **`h()` render functions** (or a real `.vue` SFC) for temporary evidence mounts — do not flip the whole app alias just for evidence |
| Playwright `wait-for-selector` times out on chip testid | App never mounted because of the template warning | Fix the mount first; re-screenshot only after DOM has the testid |

Portable rule: temporary UI evidence under Vite + Vue must use SFC or `h()`, not inline `template` strings, unless the project already aliases `vue` → `vue/dist/vue.esm-bundler.js`.

---

## 36. SPA UI evidence: mock capability + broadcasting paths (not only `/api/`)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Seeded auth + `/api/*` mocks still bounce to login | TerminalView / Echo call **`/capabilities/*`** or **`/broadcasting/auth`**; Vite proxies those to Laravel → **401** → `setUnauthorizedHandler` clears session | Intercept with `pathname.startsWith('/api/') \|\| …('/capabilities') \|\| …('/broadcasting') \|\| …('/sanctum')` and fulfill JSON; keep field lesson §24 (never `**/api/**`) |
| Board/grid mounts then evaporates mid-screenshot | Race: panes load OK, then snapshot capability 401 fires logout | Mock capability invoke success (`{ ok: true, data: … }`) before navigation settles |

Portable rule: auth-gated SPA evidence must mock **every same-origin backend prefix the shell uses**, not only `/api/`.

---

## 37. Overlay shell roots need a real layout box (not only fixed children)

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Playwright: `waitForSelector('[data-testid=shell]')` times out with “resolved to hidden” though DOM has `data-open=true` | Root node has **zero layout size** — only children use `position: fixed`; Playwright treats zero-box elements as hidden | Give the shell root `position: fixed; inset: 0` (and put backdrop/panel as absolute children); keep `pointer-events: none` on the root with `auto` on interactive children |
| Drawer works visually in a browser but automated ui step fails | Manual look uses painted fixed children; visibility API does not | Same fix — root must own the viewport box for evidence and a11y hit-testing consistency |

Portable rule: for overlay/drawer chrome, the **test-id root** must have a non-zero box, not only absolutely/fixed descendants.

---

## 38. Limit-recovery UI must not disable the trigger

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Product wants a “drop/free a slot then continue” modal at plan limit, but users never see it | Primary action is `disabled` when `at_limit` (tooltip only) | Keep the action **enabled**; open the recovery modal on click (and still handle API 422 if client usage is stale) |
| Modal lists nothing useful | Candidates filtered to wrong set (e.g. same machine only) | Prefer workspace-wide concurrent-quota consumers the user can free |

Portable rule: if the happy path at limit is a recovery dialog, **do not** hard-disable the control that starts that path; use busy/permission disables only.

---

## 39. Linear claim heartbeat: update existing comment only

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Two `<!-- do-work-claim -->` top-level comments on one Issue | Worker used `save_comment` **create** for heartbeat instead of patching the claim id | **Always** `list_comments` → find claim body with matching `agent_id` / marker → `save_comment` with that comment `id`. Never post a second claim root |
| Stale-slot / claim protocol confused | Dual claim stamps | Delete accidental duplicate claim comments immediately after noticing |

Portable rule: claim protocol is one active claim comment per Issue; heartbeat is an in-place edit of that comment’s `heartbeat:` line.

---

## 40. Live terminal streams: convertEol + mid-cut wire garbage

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| SPA paints solid black mid-line blocks (U+2588) / U+FFFD; TUI option lists unreadable | Server `substr(-$max)` starts mid-UTF-8 or half-CSI; paint path appends corrupt intermediate; mis-flagged redraw deltas concat two full screens | **(1)** Shared trailing bound that drops leading UTF-8 continuations + orphan CSI before wire/store. **(2)** Client paint sanitize for U+2588 runs + U+FFFD only (not blanket ANSI strip). **(3)** Agent Diff: non-prefix → `is_full`. Client safety net: **clear-screen only** (`ESC[2J` / `ESC[3J`) → replace buffer + `paintFull` |
| **All panes** staircase / diagonal text / sparse dots after a “TUI formatting” fix | Worker set xterm **`convertEol: false`** because capture has CSI | **Keep `convertEol: true`**. capture-pane `-p` emits LF without CR; convertEol maps LF→CRLF so progressive shells start at column 0. Disabling it breaks *every* non-TUI stream. Do **not** “fix” TUI by turning convertEol off |
| Blank / wiped panes after TUI “safety net” | Client treated bare **`ESC[H`** (cursor home) as full-screen redraw → `paintFull`/reset on mid-frame updates | Full-screen detect = **clear only** (`2J`/`3J`). Bare cursor-home is normal mid-TUI traffic — append, do not reset |
| “Fix” by stripping all ANSI | Kills legitimate color/cursor on healthy TUIs | Never strip SGR/cursor as the primary fix; only remove corrupt paint artifacts |

Portable rule: diagnose agent Diff → server bound → SPA paint **end-to-end**. Prefer bound + sanitize + clear-screen replace. **Never** set `convertEol: false` for capture-pane LF streams. Do not add cols/rows negotiation unless width mismatch is proven; do not strip all ANSI.

---

## 41. Layout thrash: RO on self-mutating host + compact stuck on expand

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Expand/resize: high-rate flicker + growing empty band under terminal | ResizeObserver watches the host that `applyHostLayout` / fit mutates → re-entry loop | Observe **stable parent** (clip box); skip refit when paint box same-size (epsilon); force refit only on real mode/layout change |
| Expand still thrash after thrash-guards | Shell hard-codes `compact` on every cell including expanded | Expanded mount = **non-compact** (full) fit; grid tiles stay compact; compact prop watch re-fits without buffer reset |
| convertEol “fix” for TUI | Turning `convertEol: false` to calm CSI | Never — see §30; thrash is layout/RO, not convertEol |

Portable rule: **do not RO-observe an element your fit path mutates**. Mode flips (compact/full) force one refit; size-stable frames no-op.

---

## 42. Hard-rename residual specs must not embed forbidden tokens

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Residual `rg 'OldName\|/old/'` fails only on the residual test file itself | Audit file lists forbidden patterns as contiguous string literals | Build patterns from **parts** (`re('Old', 'Name')` / `parts.join('')`) so the audit source never contains the product token as a continuous match |
| Verification allows “intentional historical comments” only | Negative route-guard tests still need the old path string | Keep legacy guards in **one** file (e.g. router.spec); residual suite skips that file; product sources must be clean |

Portable rule: residual greps are part of acceptance — residual **tests** must not be the only residual hits.

---

## 43. Evidence mounts: register named routes used by child RouterLinks

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Temp evidence page throws `No match for { name: '…' }`; shell never mounts | Evidence app uses `createMemoryHistory` with only `/`; child components render `RouterLink :to="{ name: 'machines' }"` (etc.) | Register every **named** route the tree resolves at setup time — even stub components |
| Shell root selector times out after PAGEERROR | Setup aborted mid-tree | Fix router first; re-check console pageerror before waiting on testids |

Portable rule: evidence routers must satisfy child `RouterLink` / `router.push` name lookups, not only the top-level path under test.

---

## 44. Dual-loop Registry: Start injects must register Lookup targets

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Stream open (Start after create) but send_keys uses payload/stale local_key | `StartFn` override returned without writing cancel-map entry; `Lookup` miss | Mirror `StartDesiredFn`: always register `{cancel, localKey}` (host optional) before/with inject |
| First heartbeat Converge thrash-restarts streamer after create_pane Start | Start left `host==""`; Converge treated host change as replace | If `localKey` matches and entry host empty, **fill host** — do not cancel/restart |
| Missing id sentinel | Int zero vs empty string after ULID hard-cut | Empty string not zero for missing pane id (see §15) |

Portable rule: inject hooks own **side effects only**; the supervisor map (streamers, connections) is still owned by the shared Registry so write-path Lookup and lifecycle Converge stay consistent.

---

## 45. Dual-gate terminal input + capability unwrap must not silent-succeed

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Role chip shows controlling but typing does nothing (no error) | `onData` gated only on permission (`canControl`) while board Focus / `keyboardActive` is a second gate; handlers half-bound when ownership flips | Single `inputEnabled = canControl && keyboardActive`; bind **and** dispose `onData` on that flag; wire flush uses the same predicate |
| Invoke returns 200 `{ ok: false, message }` and UI treats success | Unwrap only threw when `data` was present | **Always throw on `ok === false`** before reading `data`; surface humanized error on the action chrome with a testid |
| Evidence blank / keys not asserted | Stream path “fixed” by flipping convertEol | Do not touch stream paint for key-path REQs; keep `convertEol: true` (see §30) |

Portable rule: dual ownership gates (permission + focus) must share one enable flag for bind/send/dispose; capability envelopes never resolve `ok: false` as success.

---

## 46. Board / streaming list UI evidence: use product streaming states

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Seeded panes load but board shows empty (“0 streaming”) | List filter uses product **streaming** states (`active` / `idle` / `paused` / `waiting_for_input`), not labels like `running` | Mock pane `state` from the product streaming set before screenshotting board/grid chrome |
| Cell chrome never mounts for evidence | Same | Assert board-cell testid after mock; do not screenshot empty-state as chrome proof |

Portable rule: when a view partitions list rows by lifecycle state, evidence fixtures must use those exact state tokens — not colloquial synonyms.

---

## 47. Capability Result `array` ≠ JSON object map

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Cap invoke / MCP returns `output_invalid` / “unexpected format” though `run()` works in unit tests | Result DTO property typed PHP `array` → JSON Schema **`type: array` (list only)**; payload is an associative map (JSON **object**) | Type maps as nested SchemaProvider (`#[Field(of: …)]`) or override schema to `object` / `object\|null`; never rely on bare `array` for key-value payloads |
| Same after first agent heartbeat, null metrics worked | Null passes list-or-null; non-empty metrics map fails list check | Contract-test **both** empty/null **and** object snapshot through **OutputValidator**, not only direct `run()` |
| Nested Carbon / models in map | `exportValue` does not stringify Carbon | Wire-safe payload helper: ISO strings (or null) for all date fields before Result construction |

Portable rule: **PHP `array` in CapabilityData = JSON list**. Associative domain maps need object schemas + JSON-safe scalars. Prove with pipeline tests that call OutputValidator.

---

## 48. Shell generators for CI must run on bash 3.2

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Fixture test fails on macOS with `declare: -A: invalid option` | Script used bash 4+ associative arrays; `/bin/bash` on macOS is 3.2 | Parse checksums with a linear scan/`lookup` function; avoid `declare -A`, mapfile, and other bash-4 features |
| Works in CI (ubuntu bash 5) but fails locally | Same | Author + fixture-test with `#!/usr/bin/env bash` under macOS default bash before merge |

Portable rule: monorepo release/helper scripts maintainers run on Mac must be bash 3.2-clean; prove with a committed fixture test, not only Linux CI.


---

## 49. Sanctum logout tests: forgetGuards after token delete

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Feature test: token row deleted but next `$this->withToken($plain)->getJson(...)` still **200** | Same PHP process keeps auth guards resolved; Sanctum may reuse the already-authenticated user without re-looking up the deleted PAT | Call `Auth::forgetGuards()` before the post-logout request that asserts **401** |
| Production still correct | One request per PHP-FPM worker | Do **not** change product logout for the test; only clear guards in the test |

Portable rule: when asserting “revoked Bearer is unusable” in Laravel HTTP tests, clear guards between the revoke call and the re-auth attempt (and still assert the token row is gone).

---

## 50. SPA logout API + unauthorized handler re-entry

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `logout()` POSTs `/api/logout`, 401/403 fires `setUnauthorizedHandler` → calls `logout()` again; boolean `loggingOut` early-return skips `clearLocalSession` for awaiters | Re-entrancy flag returns without joining the in-flight promise | Share **one** `logoutPromise`; concurrent callers `return logoutPromise` so they await the same finally-clear |
| Local session stuck “logged in” after failed server revoke | Clear only on success | Always clear local storage in `finally` after best-effort POST (even network failure) |
| Unit tests assert no Authorization header | Token only on `tokenGetter`; store not wired | Pass `token: bearer` explicitly into `apiRequest` for logout/revoke paths |

Portable rule: intentional SPA sign-out = best-effort server revoke **then always local clear**; re-entry must join the shared promise, not a bare boolean skip.

---

## 51. Laravel `lockForUpdate` under sqlite Pest — prove atomicity, not SQL

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `DB::listen` never sees `for update` though code calls `lockForUpdate()` | `SQLiteGrammar::compileLock` is a no-op; phpunit often uses `:memory:` sqlite | Do **not** assert lock SQL on sqlite. Prove concurrent-safe intent with (1) sequential double-complete fails closed, (2) forced mid-write failure (model `updating` hook) so `token_hash`/`completed_at` (or equivalent pair) both roll back only when wrapped in `DB::transaction` |
| True multi-connection race | Needs MySQL/Postgres | Optional MySQL feature only when AC requires; default suite stays sqlite-friendly |

Portable rule: for transactional + row-lock domain writes, acceptance on sqlite = **atomicity rollback + sequential double-op**; document that production MySQL/Postgres gets real `FOR UPDATE`.

---

## 52. Sanctum feature tests after logout need guard reset

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Second request with deleted token still 200 / same user | `Auth::` / Sanctum guard caches the user from the first actingAs/Bearer call | Call `Auth::forgetGuards()` (or fresh HTTP client) between logout and the 401 assert |
| revoke-all tests flaky with multiple tokens | Same | Resolve `currentAccessToken()` once; assert token row deleted via DB, not only response |

Portable rule: after deleting the current PAT in a Pest feature test, **forget guards** before the next `$this->withToken(...)->getJson` so 401 is real.

---

## 53. SPA logout: single-flight + always clear local

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Double Sign out races two POSTs / leaves token | `logout()` fire-and-forget without shared promise | Share one in-flight logout promise; await from nav + 401 handler |
| Network fail leaves stolen token usable | Clear only after 2xx | `try { POST /api/logout } finally { clear localStorage }` |

Portable rule: server revoke is best-effort; **local clear is mandatory**.

---

## 54. Local-echo compose hold vs host slash/skill palettes

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| After `/`, local chars show but host skill/command list never filters | Compose mode holds host paints until Enter; first `/` clears hold once, then later printables re-assert local-echo hold; overlay heuristic misses small filter rewrites | Enter sticky **slash mode** on `/` that keeps painting host frames through filter keys; exit on Enter (skill run). Keep normal compose hold for non-slash lines |
| Overlay detection only fires on big menus | `+N non-empty lines` / large byte delta thresholds | Treat in-slash-mode frames as paint-through even for small deltas; unit-test filter rewrites |
| Fix by always painting host while typing | Drops local-echo contract; mid-type lag corruption returns | Dual policy: slash mode live host; non-slash hold until after Enter |

Portable rule: **host-drawn progressive UIs (slash palettes, completion menus) need sticky host-paint mode**, not a one-shot release on the first special key.

---

## 55. Email-verify gates need grandfathering + resend throttle + client signal

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Shipping `MustVerifyEmail` + invite/billing gates locks out every existing account | Historical signups have `email_verified_at` null; no migration | Deploy migration: set `email_verified_at = COALESCE(created_at, now())` for existing nulls; new signups stay unverified until link |
| Resend endpoint mail-bombs | Only `auth:sanctum` on verification resend | `throttle:6,1` (Breeze default) on resend route |
| SPA cannot prompt verify after 403 | Login/register payload omits verification state | Emit `email_verified_at` (ISO or null) on auth payloads / shared AuthUserPayload |
| SPA still drops the chip at runtime | Client `AuthUser` type / cast omits field; no normalize on persist | **Also** type `email_verified_at`, normalize on load/persist (null for legacy localStorage); tests need valid public-id fixtures if normalize calls `parsePublicId` |

Portable rule: when a new high-risk gate depends on a previously unused verification flag, **grandfather existing rows**, rate-limit resend, and **surface the flag on login** so clients can recover without opaque 403s.

---

## 56. Capacitor WebView CORS — always-merge shell origins

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Native shell login preflight fails though SPA uses Bearer tokens | CORS allowlist only lists Vite/Herd hosts; WebView Origin is `capacitor://localhost` or `https://localhost` | Always **merge** fixed Capacitor origins into `cors.allowed_origins` (env alone replaces defaults and drops them) |
| Operator “fixed” defaults in cors.php but prod/local still broken | `CORS_ALLOWED_ORIGINS` env fully overrides the default string | Prefer code-level merge of shell origins; document livepane.io / admin still in env for browser SPA |
| Touched `SANCTUM_STATEFUL_DOMAINS` for Capacitor | Assumed cookie SPA | Token-only + no `statefulApi()` → document Bearer path; CORS is the real gate |

Portable rule: for Bearer SPA shells, **CORS origin allowlist** is the native blocker; **always-merge** fixed WebView origins rather than relying on env defaults alone.


---

## 57. Worktree teardown can poison main package autoload

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Main `php artisan test` fails with class not found under `.worktrees/req-…` path after workers finish | Composer ClassLoader map still points at a removed worktree (symlink vendor / path repo dump during worktree install) | After Stage B teardown: `composer dump-autoload` (or reinstall) in the **main** package root before residual suites |
| `cap:sync` fails `Unable to find node_modules/@capacitor/android` on integration branch after package.json merge | Lock/deps merged but main checkout never ran `npm ci` | Run `npm ci` in `packages/web` on the integration base before residual `cap:sync` / path-unit close |

Portable rule: parallel worktree merges land files; **main** still needs a fresh autoload/deps install before integration residual gates.

---

## 58. Multi-server agent: Registry **per server**, not one shared process map

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| desired_streams / create_pane from server A hit server B’s token or cancel map | One process-wide stream Registry + client shared across multi-server stacks | **One client + Registry per ServerEntry**; share SessionHost plugins only (local discovery) |
| One control plane 5xx kills the whole agent | Main `errCh` exits on first loop error; heartbeat treats initial fail as fatal | Per-stack log-and-retry; root ctx cancel only on signal; initial heartbeat error is non-fatal |
| Dual-loop “share one Registry” lesson applied across servers | §11 meant share within one server (heartbeat Converge + command Start) | Keep §11 **within** a stack; multi-server multiplies full stacks |

Portable rule: multi-endpoint agents = N independent control stacks (client + heartbeat + commands + Registry). Dual-loop sharing is **intra-server**; isolation is **inter-server**.

---

## 59. Multi-server agent fan-out: Registry per endpoint + name-keyed claim

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| One control plane's 5xx kills the whole agent | Single shared errCh / first-fatal exit across servers | Per-server stack (client + heartbeat + commands + stream Registry); root cancel only on OS signal; remote errors retry in that stack only |
| Claim overwrites production when adding staging | Single-object config Save | Multi-server `Servers[]`; `UpsertServer` by free-form name; legacy single-object auto-migrates on Load |
| Parallel claim-merge + run-loop REQs conflict | Both list `cmd/.../main.go` | Serial those leaves; pair only disjoint packages in the same wave |

Portable rule: **N endpoints → N isolated supervisor stacks**; identity of a stack is config **name**, not a fixed enum of env keys.

---

## 60. Fail-closed quota earlier breaks “create then enforce on accept” fixtures

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Happy-path invite/create tests fail after adding assert-at-create | Free plan already at limit (owner fills max seats=1); fixtures still assume free can create pending rows | Happy-path fixtures need **seat room** (paid plan / higher limit). At-limit unit asserts `QuotaExceeded` on **create** |
| “Accept still enforces” tests die at invite step | Same — create now fail-closes | For defense-in-depth accept tests: **create under room**, then **downgrade / fill seats**, then accept; or insert the pending row directly |
| Feature cap invoke on free org `assertOk` fails with `domain_error` | Cap surfaces domain `QuotaExceeded` as `domain_error` | Assert `ok=false` + `domain_error` at create; keep a separate pro→free accept 422 path |

Portable rule: when moving quota fail-closed earlier in a multi-step flow, rewrite fixtures into (1) room for happy path, (2) at-limit on the new gate, (3) downgrade/fill for residual later-gate defense-in-depth.

---

## 61. At-limit list cards: free-slot primary chrome, Upgrade secondary

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Sessions at quota; Upgrade banner dominates; card End/Stop stay ghost outline | Free-slot recovery is demoted visually to secondary chrome | At `at_limit`, style free-slot actions (**End session** / **Stop watching**) as **primary** filled buttons; keep **Upgrade** outline secondary on the card |
| One label for both destroy and soft-unwatch | Shared “End” / “Drop” copy | Distinct labels: **DISCOVERED** concurrent → Stop watching; controller live (created) → End session |
| Free-slot control disabled when at limit | `disabled = busy \|\| at_limit` | Busy-only disable (see §27) |

Portable rule: when the product recovery path at a cap is free-a-slot, **list free-slot controls lead the card** (primary + enabled); billing Upgrade is optional secondary, never the only visible path.

---

## 62. Partial-confidence leaves sink verify without blocking shippable UX

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `go` stops at ~85% with full brief coverage (10/10 ranks) | Capture marked legal/ops/deep-integration leaves `partial`; each unacknowledged partial is −3 (cap −15) | Before go: either upgrade Integration to **high**, or put those ids in **acknowledged_partials** when partial is intentional (approval-gated / env-unknown) |
| Operator re-captures to chase score | Partials are not coverage gaps | Do **not** invent REQs — score math is partial-conf only |
| Force-run of a large multi-rank UR | Threshold gate is soft under `--force` | Prefer **force** (or acknowledge) then ship high-priority UX leaves first; residual-close path-units as children Done; leave ops/legal leaves for later waves |

Portable rule: **partial ≠ missing**. Approval-gated workstreams may stay partial forever; acknowledge them so go can auto-run, or use `--force` and pick implementable leaves by footprint.

---

## 63. Ops TLS/SNI already green on an ops REQ

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| AC is `curl -fsSIL https://host/` → 200 but journey report still said SSL broken | Cert issued after capture; LE Active between intake and worker | Re-probe runtime first; if green, **document repair + package a smoke script** — do not invent a failure or mutate Forge SSL from the worker |
| Deep links 200 but wrong body (home shell) | Separate from TLS: SPA `try_files` / stale deploy without postbuild mirrors | Keep content checks **optional** (`VERIFY_CONTENT=1`) unless AC requires titles/H1; note redeploy as residual, not `verification-failing` when AC is TLS-only |
| Worker wants to `forge deploy` to finish content residual | Deploy gate non-delegable | Document § nginx + postbuild; leave deploy to human/orchestrator |

Portable rule: for ops SSL REQs, **TLS probe is the AC**; process docs + smoke are the in-repo deliverable when production is already green.

---

## 64. Public release-only repo vs private monorepo install URLs

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Docs still advertise `raw.githubusercontent.com/<private-monorepo>/…/install.sh` for anonymous install | Ship status was “assets may be private”; later only a release-only public repo went live | **Prove with `curl -fsSIL` (no auth)** against the public asset host first. Point brew + curl install at the **public release repo**; document monorepo private residual as expected 404 |
| curl\|bash 404 though tarballs are public | Install script only lives in private monorepo tree | Attach install script as GoReleaser `extra_files` (and bootstrap current tag with `gh release upload` when needed) |
| Probe script reports 404 on browser download URL | Sent `Accept: application/vnd.github+json` on github.com/raw URLs | Use API Accept only on `api.github.com`; bare follow-redirects for asset URLs |

Portable rule: **anonymous install surface = public release host + public tap only**. Never teach monorepo raw URLs as the primary path when source stays private.

---

## 65. Policy `blocked_paths: .env.*` catches `.env.example`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `check-policy` exit 1 `blocked_path: …/.env.example matches .env.*` though no secrets | Config glob treats example env templates as blocked | Prefer documenting new env keys in `config/*.php` defaults + docs; if example must change, **exclude** `.env.example` from the worker commit before Stage B, or narrow `security.blocked_paths` to exact `.env` / `.env.local` (project config) |
| Reviewer passes; archive still blocked | Orchestrator treats exit 1 as hard block | Fix branch before `archive_req` — never skip policy |

Portable rule: Laravel monorepos almost always commit `.env.example`; token-boundary blocked_paths should not use a bare `.env.*` glob unless the project truly forbids example files.

---

## 66. Stage B merge blocked by native-shell rename + symlinks on integration tree

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `git merge` fails: `…/App.xcodeproj/project.pbxproj is beyond a symbolic link` / `Cannot save the current worktree state` | Concurrent Capacitor/iOS WIP on the integration checkout: tracked rename to `LivePane.*` plus `App.*` → symlink; git autostash cannot walk the path | Before Stage B: isolate foreign WIP (`stash` or move aside + `git checkout HEAD -- packages/web/ios`), merge worker branches, then restore WIP |
| Autostash keeps firing even with clean feature branches | Dirty index still holds the rename/symlink hybrid | Reset only the package path that is not in the REQ footprint — do not discard unrelated operator work without a side path (`/tmp/…` or named stash) |

Portable rule: **integration-base dirt from mobile/native renames blocks every merge**, not only iOS REQs. Orchestrator Stage B assumes a mergeable index; clear symlink-rename hybrids first.

---

## 67. Host inventory fields vs user-owned display labels

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| User renames a discovered/list item; next heartbeat restores host name (`42`, workspace id, …) | Reconcile/adopt **always writes** host `title` (or equivalent) onto the same column the UI shows | Split **host label** vs **user display**: set a `*_user_set` (or `custom_*`) flag on user edit; adopt/reconcile updates host fields but **never** overwrites display when the flag is set |
| List shows meaningless host ids (digits, opaque keys) as the primary name | UI prefers host session title over cwd/path/context | Display order: **user title if set → path/cwd (or other location) → host title → command → Untitled**; unit-test the helper |
| Path default “works in UI” but cards stay numeric | Agent inventory never sends cwd/path; only host title | Agent layer: report location (e.g. pane current path) on discovery rows; server stores it; SPA reads it |

Portable rule: **discovery reconcile owns host facts; user rename owns display identity**. One column for both without a user-set guard will thrash.

---

## 68. List-card identity UX — grill forks before capture

For briefs that rework **list/card identity** (name placement, chips, rename, default label), ideate gaps that **change the REQ graph** (not polish):

| Fork | Why it changes capture |
|------|------------------------|
| Who may rename (controller / owner / any viewer) | Authz domain + HTTP 403 cases |
| Default label source (host title vs path/cwd vs always-path-until-rename) | Display helper + agent inventory + server store |
| Edit gesture (pencil always-on vs click vs long-press mobile) | Component interaction tests + stop-propagation vs open-card |
| Surfaces (one list vs every card that shows the name) | Footprint: one shared helper + N mounts, or path-unit residual |

Self-answer pass may infer “no product PATCH yet” from routes — still **ask** permission + default + gesture; those are product calls, not codebase facts.

Portable rule: card-identity work is usually **server (user-set + API) + agent (location) + web (layout + edit)** under one path-unit; grill the four forks before splitting leaves.

---

## 69. Harness worktree path ≠ project `req/*` branch for Stage B

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Worker reports `done` + commit, but orchestrator looks under `{project}/.worktrees/req-…` and finds nothing / wrong tip | Host spawn with `isolation: worktree` puts the child under a **harness path** (e.g. `~/.grok/worktrees/…/subagent-<id>`) while do-work still creates/uses **`req/<id>`** on the shared repo | Stage B: resolve **`git log new-work..req/<id>`** (or Linear sanitize id) and **`git merge --no-ff req/<id>`** from the **recorded integration base**. Do not require the harness worktree path |
| Two worktree trees for one REQ | Worker also ran `git worktree add .worktrees/req-…` per run-worker.md | Teardown both after archive; prune; `git branch -d` only after no worktree holds the branch |
| Heartbeat/claim still on Linear | Correct — claim is not filesystem under Linear | Archive via Linear; git isolation is local |

Portable rule: **feature branch name is the merge handle**; harness worktree paths are ephemeral execution sandboxes. Always assert `git branch --show-current` equals the go/run integration base before merge (see §18).

---

## 70. Integration-base dirt: partial same-feature WIP blocks Stage B

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `git merge` aborts: local changes to `sessionList.ts` / API client would be overwritten | Main/integration checkout has **incomplete** uncommitted edits of the **same** files the worker branch completed | Prefer the **worker branch as truth**. `git checkout -- <paths>` or stash **only those paths**, merge, then drop the stash if it was half-done sibling WIP — do not merge on top of dirty same-path dirt |
| After `git stash` HEAD is a foreign branch | Stash/checkout in a multi-worktree monorepo switched the main shell off `new-work` | Immediately re-assert integration base (`git checkout <recorded-base>`); never Stage B from a surprise branch (see §18) |
| Partial WIP looked “helpful” | Prior agent or human started the same REQ on the integration tree | Integration base should stay merge-clean; implementation lives on `req/*` only |

Portable rule: **dirty same-footprint files on the integration tip are not a second feature branch** — clear them, merge the REQ branch, re-run package filters.

---

## 71. Audit footprint to unlock package-parallel leaves

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `--parallel N` still serialises agent + server though packages differ | Agent REQ `**Files:**` includes `packages/server/app/Domain/Sessions` “for cwd persist” while a server leaf already owns Adopt/Reconcile | At **audit** (or capture): put **wire/inventory** on agent footprint only; put **persist/API/flag** on server; AC text must match ownership so workers do not both edit server |
| Path-unit still lists every package | Residual-close after children Done — do not re-implement | §25 residual-close first |

Portable rule: **AC ownership drives footprint**. If two leaves share a package path only because of a cross-layer note, move the note to Integration/Depends and keep `**Files:**` to the package that will commit changes — that is what pick/overlap uses.

---

## 72. Capacitor iOS: env(safe-area-inset-*) = 0 under edge-to-edge WebView

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| SPA content draws under the iOS status bar / Dynamic Island though `viewport-fit=cover` and `--safe-area-top: env(...)` exist | Cap WKWebView paints full-bleed but reports `env(safe-area-inset-top)=0` (token cascade is fine; the env value is the lie) | Floor insets on native iOS only: `html.native-ios { --safe-area-*: max(env(...), Npx) }` toggled from a tiny pure probe (globalThis.Capacitor — **no** StatusBar-plugin-only). Keep real env when non-zero |
| Login/register padded with direct env() “look fine” while authenticated shell still clips | Shell uses CSS vars that resolve to 0; auth views use the same env and also get 0 — or shell padding is escaped by fixed chrome | Apply the floor to the **shared tokens** so shell, sticky top, fixed bottom-nav, toasts all inherit; dual-write env() then `var(--safe-area-*)` on `.app-shell` so custom-prop capture is not the only path |
| Desktop / Android over-padded after the floor | Root class applied on every platform | Gate class with `isNative && platform === 'ios'` only; desktop media queries stay untouched |
| UI evidence “passes” without proving the floor | Headless env is always 0 | Mock `html.native-ios` + force tokens to 0, overlay a status-bar band, vision-assert title/app-top **below** the band (screenshot under UR ui-evidence) |

Portable rule: **CSS env alone is not enough when Cap lies with 0** — keep viewport-fit=cover, prefer CSS over StatusBar-only, and floor shared safe-area tokens on native iOS so shell chrome cannot paint under system bands.


---

## 73. Fluid presence lists — grill holding pen + revive-on-return

For products where **host resources come and go** (discovered sessions, agents, devices) and the UI buckets live vs available:

| Fork | Why it changes capture |
|------|------------------------|
| Holding pen vs vanish | SPA often **omits** terminal states; product may need a third group so churn is visible |
| Membership (which states) | `gone` only vs completed/all non-live — changes partition + AC |
| Retention window + owner | SPA filter on `updated_at` vs server purge vs no window — changes server REQs |
| Temporary return | Inventory reappear must **revive** same identity (not skip terminal + insert duplicate) |
| Deliberate unwatch vs miss | Durable exclude ≠ temporary inventory gap — separate paths in AC |
| Surfaces | List-only vs list+nav vs board — footprint split |

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Terminal state “disappears” from UI | Partition only keeps live buckets | Add holding-pen bucket; unit-test partition |
| Host returns but list shows two rows or stays terminal | Adopt/match query **excludes** terminal rows | Revive non-excluded terminal rows on re-inventory; never create a second live row for the same host key |
| “Unavailable forever” after brief miss | Soft-unwatch/exclude conflated with inventory miss | Mark miss as terminal **without** durable exclude; exclude only on explicit user unwatch |
| Partition has holding pen but list/nav still two-bucket | Wire incomplete: only `partition` unit green | Same REQ: (1) list third group + testids, (2) prev/next ordered ids append holding pen after available, (3) empty-state when **all** buckets empty, (4) board/grid stays live-only. Holding-pen rows: identity chrome, **no** primary free-slot / Watch, prefer non-openable |

Portable rule: **fluid lists need three contracts** — (1) which states enter the holding pen, (2) how long they stay visible, (3) revive-on-return without duplicate identity. Grill those before splitting server/web leaves; agent inventory often already emits presence. **UI wire is a fourth surface** after partition exists: list group + nav order + empty gate + board exclusion.

---

## 74. Capacitor Stream off — bake Reverb + native loopback rewrite

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Header **Stream off** on device after login while REST works | `cap:sync` / prod native build only bakes API URL; `VITE_REVERB_*` stays loopback (`127.0.0.1:8080`) | Bake `VITE_REVERB_HOST` / `PORT` / `SCHEME` / `APP_KEY` in the same script as `VITE_API_URL` (match browser deploy contract, e.g. host:443 https) |
| Bake fixed but chip still off | `resolveReverbConnection` only rewrites loopback for **https:** pages; Cap origin is `capacitor://` / `ionic://` or `native=true` | Pure planner: **native or Cap protocol + loopback env → public WSS host** (forceTLS). CapacitorHttp does **not** patch WebSockets |
| Auth `/broadcasting/auth` 401 while WS host is correct | Separate from WS host — use absolute `apiBase()` bearer auth (already native-safe when API base is baked) | Do not “fix” Stream by only touching CORS; prove WSS host + key match server Reverb app |
| Local browser Herd/Vite still needs loopback | Over-eager native rewrite | Keep existing http-page + loopback behaviour; only rewrite when native/Cap context |
| Host/PORT/SCHEME baked but device still Stream off | `VITE_REVERB_APP_KEY` silently defaulted to `local-reverb-key` in cap:sync | **Fail closed** preflight on missing/empty/placeholder before native bake; require export of prod key (match API `REVERB_APP_KEY`). Never `:-local-reverb-key` for Cap dist |

Portable rule: **native shell = bake public Reverb at build + planner treats Cap/native like a non-HTTPS mixed-content case.** REST CORS/API base green does not imply Echo/Reverb green. **App key is part of the bake contract** — fail closed rather than ship a local placeholder.


---

## 75. `check-policy` exit codes: 1 blocks, 2 only requires review

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Orchestrator treats `check-policy` exit **2** as Stage B hard-stop | Confused with exit **1** (security block) | Exit map: **0** clear → continue; **1** blocked path/command → do **not** archive until fixed; **2** `review_required` (e.g. `files_changed_over`, `acceptance_criteria_over`, auth/billing risk tags) → **dispatch/pass post-build review**, then archive. Exit 2 is **not** a merge/archive veto once review returns `passed` |
| Large UI leaf (specs + views) always hits `files_changed_over: 8` | Risk threshold working as designed | Keep the threshold; ensure review notes the signal and still scopes the diff — do not raise the cap to silence exit 2 |

Portable rule: **exit 1 = security stop; exit 2 = review mandatory context**. Never skip review on exit 2 when `review.required: true`; never treat exit 2 like a blocked path.

---

## 76. Transport stream-off must not paint fatal session chrome

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Session body shows fatal error empty state while header is **Stream off** and REST/agent healthy | WS `failed` / channel `subscribe_error` mapped to status **`error`** (red chip + error body) instead of recoverable **`offline`** | Pure status reducer: transport failures → **offline** (clear errorMessage); keep **error** only for hard identity/config (e.g. invalid public id) |
| Empty copy still reads like a dead-end / “Something went wrong” | Offline empty reused hard-error language or API humanize fallback | Offline empty = Stream on/off product language + reconnect; unit-test never matches `/something went wrong/i` for offline/connecting |
| Agent help missing when stream is off | Empty helper skips agent line on error-class paths | Stream off ≠ agent offline — still append agent online/hb help when known (see §10b) |
| Bake silent `local-reverb-key` (Cap Stream off forever) | cap:sync defaulted placeholder APP_KEY | Fail-closed preflight before native bake (missing/empty/placeholder); export prod key matching server `REVERB_APP_KEY` (see §58) |

Portable rule: **transport down is recoverable stream chrome, not a session error page.** Align pane chip with header Stream off; reserve hard error for non-transport failures. Pair with fail-closed native Reverb key bake when Cap shells are in scope.

---

## 77. Monorepo brief packages vs `layers:` + Linear `Layer/*` labels

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Brief names a package (`admin`) but capture only tags `server`/`agent`/`web` | `.do-work/config.yml` `layers:` lag the monorepo packages table | At intake/capture for multi-package briefs: **expand `layers:`** (or record an explicit layer decision) so undeclared packages are not silently out of scope |
| `save_issue` fails: `Could not resolve label(s): "Layer/admin"` | Label never created on the team; body `**Layer:** admin` alone is not enough for Linear | **Create** `Layer/{name}` via `create_issue_label` (team-scoped) **before** first Issue that needs it; body header remains required either way |
| Worker/run treats admin SPA as `Layer/web` | Wrong footprint merge with product SPA | Keep **package-aligned** layers when packages are separate apps (`packages/admin` ≠ `packages/web`); Cap/iOS/Android shells that **build from web** stay **web**, not a fifth layer |

Portable rule: **brief packages ∩ monorepo packages must be in `layers:` (or deliberate opt-out).** New layer names need Linear labels pre-created under `backend: linear` before bulk `create_req`.


---

## 78. Fail-open analytics never holds a hot-path mutex

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Stream/registry/control loop stalls when analytics is enabled | Lifecycle hooks call capture **synchronously under a lock** while HTTP transport blocks | Emit analytics **after unlock** or via **goroutine** (`go client.Capture(...)`); unit-test with a recording transport + short wait when async |
| Missing key / 5xx breaks run | Analytics errors not fail-open | Empty key = no-op; swallow transport errors; never panic the product loop |
| PII leakage on agent events | Free-form props (cwd, title, command, path) | Strict **event + property allowlists**; force `app=<layer>`; distinct_id = public machine/user id only |

Portable rule: optional product analytics is **fire-and-forget + allowlist**; hot supervisors must not wait on the analytics network hop.

---

## 79. PHP PostHog dual-write tests: mutable log object, not `return [&$sent]`

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Recording transport "sent 0 events" though capture ran | Helper returns `[$client, &$sent]`; list-assignment **copies** the array and drops the reference | Hold rows on a **mutable object** (`$log->rows[] = …`) shared with the transport |
| Claim lifecycle analytics never fire in test though production path is wired | `app(CompleteX)` resolved before `instance(Analytics::class)` bind | Bind `PostHogClient` **and** the lifecycle wrapper **before** resolving the domain authority |
| Analytics inside `DB::transaction` rolls back with claim | Capture before commit | Emit **after** successful transaction return; keep fail-open so transport throw cannot undo claim |

Portable rule: **dual-write product-truth after commit**; unit tests use object logs for capture spies; bind both client and domain analytics before `app(Authority)`.

---

## 80. XcodeGen `project.pbxproj` multi-REQ merge conflicts

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Parallel/serial ios leaves all touch `LivePane.xcodeproj/project.pbxproj` | XcodeGen regenerates the whole project file whenever sources are added; two branches diverge the same UUID blob | Prefer **source files + `project.yml` as truth**. On Stage B conflict in `*.xcodeproj/project.pbxproj`: keep all Swift sources from both sides, run `xcodegen generate`, commit regenerated project |
| Integration tip dirt blocks merge after `make ios-test` | Local `xcodegen generate` dirty the committed pbxproj without a commit | `git checkout -- packages/ios/LivePane.xcodeproj` before Stage B merge, or always commit regen as part of the REQ |
| Footprint lists only sources but pbxproj still conflicts | Implicit regen artifact | Document in REQ Files that pbxproj may change; regenerate rather than hand-merge conflict markers |
| `--parallel N` serialises every ios leaf | Every REQ lists `…/LivePaneTests` (or equivalent) as a **directory** | Narrow `**Files:**` to concrete `*Tests.swift` paths per leaf before claim (audit Step footprint) |

Portable rule: **never hand-merge XcodeGen pbxproj** — merge sources, regenerate, re-test. **Parallel width for Xcode packages is limited by shared tests-dir footprints + pbxproj**, not by N alone.

**SPM first-build (SwiftTerm / Metal):** if `xcodebuild` fails with missing Metal Toolchain while resolving SwiftTerm, run `xcodebuild -downloadComponent MetalToolchain` once on the machine before treating the REQ as verification-failing. Document in package README for agent CI hosts.

**Simulator DESTINATION:** do not hardcode a single device name (`iPhone 16`) as the only path — discover an available iPhone Simulator or accept `DESTINATION=` override (macOS agent images lag plan prose).

**Native UI path-unit close:** product entry points (launch login, open session pane) are often **human** on Simulator; closure can be `degraded:evidence-by-test` via package suite + source presence when device/TestFlight is residual-by-clarification.

---

## 81. Cap (WebView shell) strip + PWA — grill package forks before capture

For briefs that **remove Capacitor/Cordova/hybrid shells** and/or **add PWA**, ideate gaps change the REQ graph. Grill before bulk `create_req` (same spirit as §52 card-identity / §57 fluid lists):

| Fork | Why it changes capture |
|------|------------------------|
| Pure native sibling package vs Cap under SPA package | Cap often lives under `packages/web` (config, ios/, android/, `@capacitor/*`); pure SwiftUI/Kotlin may be a **separate** package. “Remove Cap” ≠ delete pure native |
| “Android web” / “mobile web” | Often means **browser/PWA install** for phone users, or **product web + admin** packages — not Cap Android product work / TWA this UR |
| Strip depth | Shell dirs only vs full surface: client Cap branches (platform, push, safe-area floors, Reverb native rewrite) + **server** always-merge WebView CORS origins + Cap-only tests |
| PWA depth | Installable **online-first** (manifest + SW network-first) vs full offline Workbox shell (stale API risk) |
| Push | Cap push drop this UR vs Web Push in-scope |
| Layers | SPA package + admin SPA + server; agent usually no; pure native package often **keep / no REQ** |

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Capture deletes pure native or freezes wrong package | Brief said “native” / “Cap” loosely | Grill pure-native keep/drop; footprint Cap paths only under SPA package |
| Cap strip + PWA both claim `package.json` | Parallel leaves same footprint | **Serial**: strip Cap deps first, then add `vite-plugin-pwa` (or equivalent); path-unit blocked by both |
| Server still green on Cap CORS tests after Cap gone | Strip was client-only | Full surface strip includes `cors` always-merge + Cap origin tests; keep Bearer browser origins |
| Offline SW ships against live API/Reverb | “Set up PWA” without depth grill | Default online-first unless brief claims offline |

Portable rule: **dual-shell monorepos need package forks in clarifications**; Cap lessons in field-lessons (CORS, safe-area, Stream bake) stay as **historical reverse-migration** maps after Cap is removed — do not invent product Cap ops after strip.


---

## 82. Cap strip residual greps: product vs negative tests

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `rg 'capacitor://\|ionic://' packages/server` still hits after Cap CORS strip | Unit/feature tests use the scheme strings as **negative** expected values | Treat **product** residual as config/bootstrap/app only (`--glob '!**/tests/**'`). Keep deliberate negative tests; do not invent Cap origins in defaults |
| Always-merge still present after "removing comments" | `$capacitorWebViewOrigins` + `array_merge` left in `cors.php` | Delete the merge array entirely; defaults = browser Vite only from env/default string |
| Symlink `vendor` → TestCase / `configPath` missing in worktree | Composer ClassLoader base = main package | Real `composer install` in worktree package (see §7) + symlink `.env` (§21) |

Portable rule: **Cap strip residual = product surface clean**; negative tests may still name forbidden origins. Prefer full-tree product path globs over zero absolute hits.


---

## 83. SwiftUI: ObservableObject VMs over @Observable stores need published mirrors

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| List UI stays empty after `await store.fetch()` though store has rows | VM is `ObservableObject`; domain store is `@Observable` / Observation. Reading `store.machines` in a computed property does **not** fire `objectWillChange` | Mirror list/loading/error into `@Published` properties on the VM after each refresh/rename; or observe the store directly in the View with `@Bindable` / Observation |
| Tests pass (assert store/VM arrays) but Simulator list blank until force-redraw | Same | Same mirror pattern; unit-test the published surface, not only store internals |
| Two observation systems mixed without a rule | Login VMs already use Combine; domain uses `@Observable` | Prefer thin Combine VMs for list screens that need explicit refresh; keep pure domain helpers as free functions |

Portable rule: **one observation owner per view tree level**. If the View holds a Combine VM, the VM must publish every field the body reads after async work — do not rely on nested Observation notifications through an ObservableObject.

---

## 84. Online-first PWA (vite-plugin-pwa): pure config + NetworkFirst + nodenext imports

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| AC only “add PWA” but product is live API/auth SPA | Default Workbox Offline-first / CacheFirst shell serves stale admin/API chrome | Ship **installable online-first**: `NetworkFirst` navigations + short timeout; **`NetworkOnly` for `/api` `/sanctum` `/capabilities`**; denylist those on `navigateFallback`; description must not claim offline |
| Multi-app monorepo reuses one product name | Shared “LivePane” manifest | Distinct `name` / `short_name` / `id` per SPA (e.g. LivePane Admin / LP Admin / livepane-admin) |
| `vue-tsc -b` fails on `vite.config.ts` import of `./src/lib/pwaConfig` under `module: nodenext` | Extensionless relative import | Import `./src/lib/pwaConfig.ts` (and include that file in `tsconfig.node.json`); keep strategy as **pure module** unit-tested — do not assert only via dist smoke |
| Suite cannot import `virtual:pwa-register` | `injectRegister: 'auto'` or main always loads virtual module in unit env | Prefer `injectRegister: false` + explicit `registerSW` in `main.ts`; unit-test pure config, not the virtual module |

Portable rule: **online-first PWA = unit-tested manifest identity + NetworkFirst shell + NetworkOnly for auth/API**. Prove with `dist/manifest.webmanifest` + `dist/sw.js` on build, not offline demos. **Installability ≠ offline app.** Cap strip + PWA both claiming `package.json` → serial (see §65).

---

## 85. Cap/deps strip: regenerate lock without symlinked node_modules

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| After removing `@capacitor/*` (or similar) from package.json, lock still lists them under a nested `node_modules/@…` path | Worktree `node_modules` is a **symlink** to a main tree that still has the old packages; `npm install --package-lock-only` walks the linked tree | **Remove the symlink** (or use a temp empty dir), run `rm package-lock.json && npm install --package-lock-only`, then restore an **absolute** `node_modules` symlink for tests |
| Residual `rg` still hits lock after package.json is clean | Same | Verify lock root `packages[""].dependencies` has no stripped deps; regenerate as above before commit |

Portable rule: **lockfile generation must not see a foreign/stale dependency tree via symlink** when proving a dep strip.

---

## 86. Integration tip after package.json merges: install before close/build

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Close/path residual: `vue-tsc` / Vite fails `Cannot find module 'vite-plugin-pwa'` / `virtual:pwa-register` though worker builds were green | Workers installed deps **inside worktrees**; Stage B merges only files — **main** `node_modules` still pre-merge | On integration base before residual close or path-unit build gates: `npm install` (or `npm ci`) in each package whose lock/deps changed |
| Same class as Cap residual `npm ci` for native bake | §42 | Extend to any new build-time plugin (PWA, etc.), not only Cap |

Portable rule: **merge lands sources; tip install lands tools.** Path-unit / close that claims “build emits SW” must install on the **merged** checkout first (see also §42 main autoload after worktree teardown).

---

## 87. Residual greps must catch uncommitted secrets on the integration tip

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Residual `rg 'phc_\|sk-\|AKIA'` hits after all leaves archived “no secrets” | Worker committed empty placeholders; **local uncommitted dirt** on integration tip re-introduced a real key (dogfood / paste) between Stage B and residual | Before residual-close **and** before any metadata commit: run secret-shaped greps on the **working tree** (not only `git show HEAD`). If a match is **uncommitted**, `git checkout -- <path>` (or restore empty placeholder) — do not stage it. If a match is **committed**, treat as Stage B / policy failure and strip in a fix commit |
| Worker AC “Release.xcconfig has no phc_” was green | True at worker commit time | Residual owns tip honesty; worker evidence does not cover later tip dirt |

Portable rule: **archive evidence is historical; residual is tip-truth.** Secret-shaped residual greps run against the live integration checkout (tracked + dirty) before path-unit Done.

---

## 88. Native SDK bootstrap graph — serialize shared project.yml

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| `--parallel N` underfills on “SPM package” + “AppConfig / Info.plist keys” leaves | Both declare `project.yml` (and often regenerated `pbxproj`) | Capture graph: **SPM leaf first**, then **config/plist leaf**, then facade, then wire ∥ docs. Do not invent parallel width across those two |
| Facade leaf also lists whole `Support/` + `Tests/` dirs | Overlaps prior AppConfigTests / Support files if too broad | Narrow facade **Files:** to concrete new sources (`ProductAnalytics.swift`, matching `*Tests.swift`); leave AppConfig footprint to the config leaf |
| Path-unit residual re-implements wiring | Children already Done | Residual-close with package suite + secret greps (§71) + docs presence only |

Portable rule for native analytics/SDK URs: **package → config/fail-open → injectable facade → app wire → docs**, with **one choke file (`project.yml` / pbxproj regen) owned by at most one in-flight leaf**. Pair only docs with wire when footprints are truly disjoint (AGENTS/README vs App/Domain only).


---

## 89. Native cold restore must not wipe session on transport failure

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| User logs in; force-quit; reopen shows login though they never signed out | Cold-start restore validates token via network; **any** error (offline, TLS, 5xx, timeout) clears Keychain/local token | Clear durable token only on **definitive auth failure** (typically **401/403**) or explicit logout. On network/5xx: keep token, mark session ready (shell may show offline list errors) |
| “Auth persistence missing” when Keychain + restore already exist | Fail-closed wipe looks like missing storage | Audit restore **policy** before building a second store |
| Double clear / race on 401 | API client unauthorized hook + restore catch both clear | Prefer restore-owned clear for the probe, or suppress unauthorized fire during restore |
| Service keep-session green but app still boots login | Only `AuthService.restore` tested; root composition / splash-owned restore never maps session → shell root | Assert **composition root** after `bootstrap` (or equivalent long-lived owner): offline/5xx keep → authenticated root + token present; 401/403 + logout/clearLocal → unauthenticated + login. Bootstrap must live on a long-lived owner (app `.task`), not only a dismissible splash |

Portable rule: **token persistence ≠ online validate success.** Offline-friendly products keep the bearer across process death unless the server rejects it or the user signs out. Prove at **composition root**, not only the restore service.

---

## 90. Triple status chrome + session liveness — grill before capture

When a host session list shows **Available** but open chrome says **Agent offline** / **Waiting**, treat three **independent** signals (do not collapse them in copy or AC):

| Signal | Typical source | Means |
|--------|----------------|--------|
| List bucket (Available / streaming / Unavailable) | Resource **lifecycle state** on the server | Membership of list groups |
| Stream phase (Waiting / Live / Stream off) | Client ↔ realtime transport | Channel / bytes, not host process |
| Agent online | Parent link **heartbeat** for **this** workspace | Host agent for that claim only |

| Symptom | Likely cause | Default action |
|---------|--------------|----------------|
| Open blames agent while host agent is fine | Empty canvas **leads with** agent_offline over stream/session-dead | Empty hierarchy: checking spinner first → true agent offline → session gone on host → stream wait/idle. Never paint “agent offline” when parent-link online and only the child session is dead |
| Dead rows linger in Available | Inventory still “live” or only passive stale; no **session-alive probe** | Grill: passive TTL vs **server→agent ping** (exists?); on definitive no → terminal holding pen immediately; fail-open on timeout (no false-gone) |
| User confuses 15m with “no activity 15m” | Holding-pen retention vs idle/stream silence | Document separately: **hide window** for terminal rows vs **liveness probe** vs stream idle |

**Ideate forks that change the REQ graph** (same spirit as §57 fluid lists / §52 card identity):

| Fork | Why it changes capture |
|------|------------------------|
| Passive stale vs active ping while agent online | Server MarkUnreachable vs new agent command + domain |
| When to probe (list / open / idle N) | Client leaves + API surface |
| Empty copy when agent online + session dead | Pure chrome helpers + tests on every client surface |
| Checking spinner while probe/stream settle | Open path UX; suppress fatal empty until settle |
| Surfaces (native / SPA / admin residual) | Layer fan-out; admin often list-only residual |

Portable rule: **list membership ≠ agent heartbeat ≠ stream phase**. Capture must split server/agent probe work from client honesty chrome; grill liveness authority before implementing only UI labels.

