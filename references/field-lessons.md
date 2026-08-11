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
