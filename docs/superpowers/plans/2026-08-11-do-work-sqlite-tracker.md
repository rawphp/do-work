# Do-work SQLite Tracker + HTML Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship opt-in `tracker.backend: sqlite` as a sole local work-item store behind the existing tracker port, with `lib/dw-db.sh` owning concurrency and `/do-work board` emitting a static HTML snapshot.

**Architecture:** Three backends (`markdown` | `linear` | `sqlite`) share `agents/tracker/port.md`. SQLite stores URs/REQs/claims/artifacts in `.do-work/work.db` via `sqlite3` + `lib/dw-db.sh`. Phase agents get a **1S** branch (port ops + dw-db only). Board is read-only HTML regenerated only by `/do-work board`. No history migration; empty DB on switch.

**Tech Stack:** Bash 3.2+, `sqlite3` CLI, plain `lib/tests/*.test.sh` (macOS-compatible), existing do-work agent markdown docs.

**Spec:** `docs/superpowers/specs/2026-08-11-do-work-sqlite-tracker-design.md` (second-amend).

## Global Constraints

- **Default backend stays `markdown`** — sqlite is opt-in only.
- **No dual-write** — when `backend: sqlite`, never treat `REQ-*.md` / `user-requests/` as live truth.
- **No migration** of markdown or Linear history into `work.db` in v1.
- **Hard-stop** on unusable sqlite (missing `sqlite3`, corrupt DB, bad `user_version`, missing `sqlite.md`) — never fall back to markdown or Linear.
- **External IDs are slugs** (`UR-NNN`, `REQ-NNN`); integer PKs are internal only.
- **DB status enum** uses underscore: `in_progress` (never store `in-progress`).
- **Slug alloc** = max **integer** suffix + 1, min width 3, grows past 3 — never `MAX(slug)` string.
- **Claim takeover** = in one transaction: release active → insert new active.
- **WAL** + `busy_timeout=5000` + outer CLI retries 3× (50/100/200ms).
- **Gitignore must** include `work.db`, `work.db-*`, `board/` (install/upgrade).
- **Evidence** paths: `.do-work/evidence/UR-NNN/{ui,closure}-evidence/` only under sqlite.
- **Gate locks** stay local: `.do-work/state/gate-owner.md` (not DB).
- **`lib/score-coverage.sh`** remains shared arithmetic — do not reimplement in dw-db.
- **TDD:** for each `lib/` deliverable, write `lib/tests/*.test.sh` first, run red, implement, green, commit.
- **Regression:** `bash lib/tests/run-all.sh` must stay green for existing markdown tests after every task.

## File map

| Path | Responsibility |
|------|----------------|
| `lib/sqlite-schema.sql` | Canonical schema `user_version=1` |
| `lib/dw-db.sh` | Sole agent-facing CLI for sqlite work-item ops |
| `lib/tests/dw-db-*.test.sh` | CLI + schema tests |
| `agents/tracker/sqlite.md` | Port op sequences for agents |
| `agents/tracker/port.md` | Accept `sqlite`; generalized hard-stop matrix |
| `agents/config.md` | Resolve/validate `sqlite`; config template keys |
| `agents/*.md` (phase list in Task 6) | **1S** branches |
| `agents/board.md` (or help + commands) | `/do-work board` agent stub |
| `references/commands.md`, `SKILL.md` | Document backend + board |
| `docs/troubleshooting.md`, `docs/HOW-IT-WORKS.md` | Operator docs |
| `agents/upgrade.md` | Gitignore must; refuse Linear migrate on sqlite |
| `lib/conformance-scan.sh` | Optional detector notes for sqlite |
| Project consumer `.gitignore` helpers | Patterns for work.db / board / evidence |

---

### Task 1: Load path accepts `sqlite` (config + port + SKILL)

**Files:**
- Modify: `agents/config.md` (template `tracker.backend` comment, Load Config step 6, schema table for `tracker.backend` + `tracker.sqlite.*`, hard-stop exceptions)
- Modify: `agents/tracker/port.md` (resolve branch, hard-stop section generalized beyond Linear-only)
- Modify: `SKILL.md` (hard-stops table / multi-tracker summary: three backends)
- Test: document-only task — verify with `rg` self-check; no bash unit test required beyond Task 2+

**Interfaces:**
- Produces: effective backend may be `sqlite`; agents know to load `agents/tracker/sqlite.md`
- Consumes: existing Load Config / port load path pattern

- [ ] **Step 1: Update `port.md` resolve rules**

In `agents/tracker/port.md` load path step 2, change so:

```text
- missing/empty → markdown
- markdown → markdown
- linear → linear
- sqlite → sqlite
- else → hard-stop unknown backend
```

Replace Linear-only hard-stop section with a **three-backend matrix** matching design §5.3:

| Condition | markdown | linear | sqlite |
|-----------|----------|--------|--------|
| Backend doc missing | n/a | hard-stop | hard-stop |
| MCP/team/status_map fail | n/a | hard-stop | n/a |
| DB corrupt / bad user_version / no sqlite3 | n/a | n/a | hard-stop |
| Fallback to another backend | never | never | never |

Add note: mid-flight leave-claimed applies to all backends (sqlite = active claims row).

Also update `migrate_markdown_to_linear` notes: **refuse** when effective backend is already `sqlite`.

- [ ] **Step 2: Update `config.md` Load Config**

In step 6 resolve:

```text
- If tracker.backend is `sqlite` → effective backend = sqlite
```

Add step **7b** (or extend after Linear step 7): when effective backend is `sqlite`:

1. Require `sqlite3` on PATH — else hard-stop with install hint.
2. Do **not** run Linear validation or product_project bind.
3. Load `port.md` then `agents/tracker/sqlite.md` (if missing → hard-stop).
4. Defer DB ensure to first `ensure_product_container` / `dw-db ensure` (Task 2).

Template YAML:

```yaml
tracker:
  backend: markdown          # markdown | linear | sqlite
  sqlite:
    path: ""                 # default .do-work/work.db
    board_path: ""           # default .do-work/board/index.html
    busy_timeout_ms: 5000
  linear:
    # unchanged
```

Schema table rows for `tracker.backend` (include sqlite) and `tracker.sqlite.path`, `board_path`, `busy_timeout_ms`.

Hard-stop exceptions list: add sqlite unusable (missing binary/doc/corrupt DB after ensure attempts).

- [ ] **Step 3: Update `SKILL.md` multi-tracker summary**

Hard-stops / tracker table:

| backend | behavior |
|---------|----------|
| unset/markdown | local files |
| linear | Linear sole store |
| sqlite | `.do-work/work.db` sole store |

One line: no dual-write; greenfield on switch; `/do-work board` sqlite-only.

- [ ] **Step 4: Self-check**

```bash
rg -n 'sqlite' agents/config.md agents/tracker/port.md SKILL.md | head -40
rg -n 'markdown \| linear[^-]' agents/config.md agents/tracker/port.md
# should not leave exclusive "markdown | linear" without sqlite where backend is defined
```

- [ ] **Step 5: Commit**

```bash
git add agents/config.md agents/tracker/port.md SKILL.md
git commit -m "docs: accept sqlite tracker backend in load path and hard-stop matrix"
```

---

### Task 2: Schema + `dw-db ensure` + gitignore helpers

**Files:**
- Create: `lib/sqlite-schema.sql`
- Create: `lib/dw-db.sh` (skeleton: `ensure`, path resolve, open helper)
- Create: `lib/tests/dw-db-ensure.test.sh`
- Modify: `agents/upgrade.md` (gitignore must for work.db / board)
- Modify: any install bootstrap that writes consumer `.gitignore` (search `references/commands.md` install template / upgrade legacy gitignore)

**Interfaces:**
- Produces: `bash lib/dw-db.sh ensure <project-root>` creates `.do-work/work.db` with `user_version=1`
- Produces: env/config path default `{project}/.do-work/work.db`
- Consumes: `sqlite3` on PATH

- [ ] **Step 1: Write failing test `lib/tests/dw-db-ensure.test.sh`**

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW_DB="$LIB_DIR/dw-db.sh"
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED+1)); }

TMP="$(mktemp -d -t dw-db-ensure.XXXXXX)"
mkdir -p "$TMP/.do-work"

# Expect fail until implemented
if [ ! -x "$DW_DB" ] && [ ! -f "$DW_DB" ]; then
  fail "dw-db.sh missing"
fi

out="$(bash "$DW_DB" ensure "$TMP" 2>&1)" || true
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 not installed"
  exit 0
fi

if [ ! -f "$TMP/.do-work/work.db" ]; then
  fail "work.db not created"
fi

ver="$(sqlite3 "$TMP/.do-work/work.db" 'PRAGMA user_version;')"
[ "$ver" = "1" ] || fail "user_version want 1 got $ver"

# idempotent second ensure
bash "$DW_DB" ensure "$TMP" || fail "second ensure failed"

# tables exist
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q urs || fail "missing urs"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q reqs || fail "missing reqs"
sqlite3 "$TMP/.do-work/work.db" ".tables" | grep -q claims || fail "missing claims"

# partial unique index for one active claim
sqlite3 "$TMP/.do-work/work.db" "SELECT sql FROM sqlite_master WHERE name='claims_one_active_per_req';" \
  | grep -qi unique || fail "missing claims_one_active_per_req"

rm -rf "$TMP"
[ "$FAILED" -eq 0 ] || exit 1
echo "PASS dw-db-ensure"
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
bash lib/tests/dw-db-ensure.test.sh
```

Expected: FAIL (missing dw-db.sh or work.db).

- [ ] **Step 3: Implement `lib/sqlite-schema.sql`**

Include (design §6):

- `PRAGMA user_version = 1;` (applied via ensure after create)
- Tables: `urs`, `ur_artifacts` UNIQUE(ur_id, kind), `reqs`, `deps`, `claims` + partial unique index `claims_one_active_per_req`, `decisions`, `calibration`, `milestone_state`, `run_notes`
- Columns per design (status CHECK or app-enforced: backlog|in_progress|stopped|done)

Minimal `urs`:

```sql
CREATE TABLE IF NOT EXISTS urs (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  class TEXT NOT NULL DEFAULT '',
  brief TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  closed_at TEXT
);
```

(Full DDL for all tables in the same file — implementers expand from design §6.1; every table in §6.1 must appear.)

- [ ] **Step 4: Implement `lib/dw-db.sh` skeleton**

```bash
#!/usr/bin/env bash
# dw-db.sh — sqlite work-item store CLI for do-work (tracker.backend: sqlite)
# Usage: dw-db.sh <command> [args...]
# Compatible with macOS bash 3.2.
set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCHEMA="$SCRIPT_DIR/sqlite-schema.sql"

die() { echo "dw-db: $*" >&2; exit 1; }

require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not on PATH (install sqlite)"
}

# resolve_db PROJECT_ROOT [override_path]
resolve_db() {
  local root="$1"
  local override="${2:-}"
  if [ -n "$override" ]; then
    case "$override" in
      /*) echo "$override" ;;
      *) echo "$root/$override" ;;
    esac
  else
    echo "$root/.do-work/work.db"
  fi
}

sql_exec() {
  local db="$1"; shift
  # busy_timeout + WAL on every connection
  sqlite3 "$db" "PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; $*"
}

cmd_ensure() {
  local root="${1:-}"
  [ -n "$root" ] || die "ensure: project root required"
  require_sqlite3
  mkdir -p "$root/.do-work" "$root/.do-work/state" "$root/.do-work/evidence" "$root/.do-work/board"
  local db
  db="$(resolve_db "$root")"
  if [ ! -f "$db" ]; then
    sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;"
    sqlite3 "$db" < "$SCHEMA"
    sqlite3 "$db" "PRAGMA user_version=1;"
  else
    local ver
    ver="$(sqlite3 "$db" 'PRAGMA user_version;')"
    [ "$ver" = "1" ] || die "unsupported schema user_version=$ver (supported=1); recreate empty work.db"
  fi
  echo "$db"
}

# outer retry helper for later write commands
with_retry() {
  local attempt=1
  local delays="0.05 0.1 0.2"
  local d
  set -- $delays
  while true; do
    if "$@"; then return 0; fi
    if [ "$attempt" -ge 3 ]; then return 1; fi
    d="$1"; shift || true
    sleep "${d:-0.2}"
    attempt=$((attempt+1))
  done
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    ensure) cmd_ensure "$@" ;;
    "") die "usage: dw-db.sh <command> ..." ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
```

- [ ] **Step 5: Run test — expect PASS**

```bash
bash lib/tests/dw-db-ensure.test.sh
bash lib/tests/run-all.sh
```

- [ ] **Step 6: Upgrade gitignore must**

In `agents/upgrade.md`, add a safe step (or expand install/config conformance):

When project has `.do-work/` and git, ensure `.gitignore` contains:

```
.do-work/work.db
.do-work/work.db-*
.do-work/board/
```

(Recommended also `.do-work/evidence/`.)

Document: if missing, append. Do not remove user rules.

Also refuse `/do-work upgrade migrate` (Linear) when `tracker.backend` is `sqlite` (preflight message).

- [ ] **Step 7: Commit**

```bash
git add lib/sqlite-schema.sql lib/dw-db.sh lib/tests/dw-db-ensure.test.sh agents/upgrade.md
git commit -m "feat(sqlite): schema and dw-db ensure with WAL and user_version=1"
```

---

### Task 3: Numeric slug alloc + UR/REQ CRUD

**Files:**
- Modify: `lib/dw-db.sh` — `create-ur`, `get-ur`, `list-urs`, `create-req`, `get-req`, `list-reqs`, `update-req`, `set-status`, `set-files`, `set-blocked-by`
- Create: `lib/tests/dw-db-crud.test.sh`
- Create: `lib/tests/dw-db-slug.test.sh`

**Interfaces:**
- `dw-db.sh create-ur <root> --title T --brief B [--class C]` → prints `UR-NNN`
- `dw-db.sh create-req <root> --ur UR-NNN --title T [--body ...] [--priority N] [--files ...] [--deps "REQ-1,REQ-2"] [--parent REQ-P] [--layer L] [--path-milestone M1]` → prints `REQ-NNN`
- All outputs use **slugs**; invalid parent/dep slug → exit 1 with error text

- [ ] **Step 1: Failing slug test**

```bash
# lib/tests/dw-db-slug.test.sh
# After ensure, insert UR-9 manually (or create until UR-009 then force title), then create-ur must yield UR-010 not UR-10/lexicographic wrong.
# Algorithm assertion: create three URs → UR-001, UR-002, UR-003
# Manually: INSERT slug UR-9 (if allowed) OR document that slugs always zero-padded so next after UR-009 is UR-010
# Critical: next_id = max(CAST(suffix AS INT))+1 formatted with width max(3, len)
```

Test body:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW="$LIB_DIR/dw-db.sh"
command -v sqlite3 >/dev/null || { echo SKIP; exit 0; }
TMP="$(mktemp -d -t dw-slug.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null
# force a high numeric suffix without zero-pad to prove numeric max
db="$TMP/.do-work/work.db"
sqlite3 "$db" "INSERT INTO urs(slug,title,class,brief,created_at) VALUES('UR-9','x','','b','2026-01-01');"
next="$(bash "$DW" create-ur "$TMP" --title t --brief brief)"
# Want UR-010 (9+1, width >= 3)
[ "$next" = "UR-010" ] || { echo "FAIL: got $next want UR-010"; exit 1; }
rm -rf "$TMP"
echo PASS
```

- [ ] **Step 2: Run — FAIL**

```bash
bash lib/tests/dw-db-slug.test.sh
```

- [ ] **Step 3: Implement slug helper + create-ur / create-req in transaction**

```bash
# inside dw-db.sh
next_slug() {
  # args: db table_prefix  e.g. UR or REQ
  local db="$1" kind="$2"  # kind=UR|REQ
  local max_n
  max_n="$(sqlite3 "$db" "SELECT COALESCE(MAX(CAST(substr(slug, instr(slug,'-')+1) AS INTEGER)), 0) FROM $( [ "$kind" = UR ] && echo urs || echo reqs ) WHERE slug LIKE '${kind}-%';")"
  local n=$((max_n + 1))
  local width=3
  local s="$n"
  while [ ${#s} -lt "$width" ]; do s="0$s"; done
  echo "${kind}-$s"
}

normalize_status() {
  case "$1" in
    in-progress) echo in_progress ;;
    *) echo "$1" ;;
  esac
}
```

Use `BEGIN IMMEDIATE;` … `COMMIT;` for create-ur/create-req.

- [ ] **Step 4: CRUD tests** (create, get, list, set-blocked-by invalid slug fails, cross-UR dep ok)

- [ ] **Step 5: Green + commit**

```bash
bash lib/tests/dw-db-slug.test.sh
bash lib/tests/dw-db-crud.test.sh
bash lib/tests/run-all.sh
git add lib/dw-db.sh lib/tests/dw-db-slug.test.sh lib/tests/dw-db-crud.test.sh
git commit -m "feat(sqlite): transactional UR/REQ CRUD with numeric slug allocation"
```

---

### Task 4: Claim, pick, deps, footprint, heartbeat, archive integrity

**Files:**
- Modify: `lib/dw-db.sh` — `list-claimable`, `pick`, `claim`, `heartbeat`, `check-deps`, `check-footprint`, `scan-stale`, `check-archive`, `archive-req`, `unblock`
- Create: `lib/tests/dw-db-claim.test.sh`
- Create: `lib/tests/dw-db-pick.test.sh`
- Create: `lib/tests/dw-db-archive.test.sh`

**Interfaces:**
- Exit codes: claim race → exit **2** + stderr `concurrent-conflict` (align with markdown claim lost spirit)
- `list-claimable` stdout: one REQ slug per line, ordered
- `pick` stdout: one slug or empty + exit 1 if none
- Heartbeat: UPDATE only; exit 1 if not owner
- Stale takeover: release then insert in one transaction
- `check-archive`: fail unless status done (or about to archive path sets done after checks matching markdown order — implement: archive-req runs checks requiring non-empty proof, no unchecked AC, then sets done + releases claim)

**Pick order (locked):**

1. priority DESC (NULL → 2)
2. numeric REQ suffix ASC
3. created_at ASC, slug ASC

**Milestone filter:** per-UR cursor (design §8.7).

- [ ] **Step 1: Failing claim race test**

Two sequential claims on same backlog REQ: first exit 0 status in_progress + active claim; second exit 2.

Stale test: set heartbeat old, second agent claim succeeds; old claim row `released`.

Heartbeat test: second INSERT active must fail unique index; heartbeat only updates.

- [ ] **Step 2: Implement claim/heartbeat/unblock**

```sql
-- claim transaction sketch
BEGIN IMMEDIATE;
-- re-read status and active claim
-- if foreign fresh active → ROLLBACK; exit 2
-- if stale active → UPDATE claims SET status='released' WHERE req_id=? AND status='active';
UPDATE reqs SET status='in_progress', updated_at=? WHERE id=?;
INSERT INTO claims(req_id, agent_id, claimed_at, heartbeat, session, status)
  VALUES (?, ?, ?, ?, ?, 'active');
COMMIT;
```

- [ ] **Step 3: Implement list-claimable + pick + footprint**

Footprint: reuse semantics of `check-footprint.sh` (whitespace/comma tokens, nullglob, expand against project root). Implement in bash calling project tree from `<root>` arg.

Deps: unsatisfied if any depends_on req status ≠ done.

- [ ] **Step 4: check-archive three criteria**

1. closure_proof non-empty  
2. no `- [ ]` under `## Acceptance Criteria` in body  
3. status is `done` after archive, or archive-req sets done only after 1–2 pass (match markdown: check-archive before move — require proof+AC; status becomes done in archive-req)

- [ ] **Step 5: Tests green + commit**

```bash
bash lib/tests/dw-db-claim.test.sh
bash lib/tests/dw-db-pick.test.sh
bash lib/tests/dw-db-archive.test.sh
bash lib/tests/run-all.sh
git add lib/dw-db.sh lib/tests/dw-db-claim.test.sh lib/tests/dw-db-pick.test.sh lib/tests/dw-db-archive.test.sh
git commit -m "feat(sqlite): claim pick footprint archive coordination via dw-db"
```

---

### Task 5: Artifacts, decisions, calibration, milestones, run notes

**Files:**
- Modify: `lib/dw-db.sh` — `append-ideate`, `append-clarifications`, `write-verify`, `write-close`, `append-decision`, `write-calibration`, `read-calibration`, `set-active-milestone`, `get-active-milestone`, `list-milestone-reqs`, `append-run-note`
- Create: `lib/tests/dw-db-artifacts.test.sh`
- Create: `agents/tracker/sqlite.md` (full port op index → dw-db commands)

**Interfaces (artifact semantics):**

| kind | write |
|------|--------|
| ideate | append |
| clarifications | append |
| open_gaps | replace |
| capture_summary | replace |
| verify | replace |
| close | replace + set `urs.closed_at` on successful overall |

- [ ] **Step 1: Write artifact tests** (append ideate twice grows body; brief unchanged; close sets closed_at)

- [ ] **Step 2: Implement**

- [ ] **Step 3: Write `agents/tracker/sqlite.md`**

Structure mirror `linear.md` condensed:

- When to load  
- Hierarchy: product = project root + work.db  
- Port op index table → `bash {skill-root}/lib/dw-db.sh …`  
- Hard-stop template (sqlite3 missing, corrupt DB, bad version)  
- Claim protocol summary pointing at dw-db  
- Evidence paths `.do-work/evidence/UR-NNN/…`  
- `write_gate_state` → local gate-owner only  
- Calibration non-port read/write via dw-db  
- `migrate_markdown_to_linear`: refuse under sqlite  

- [ ] **Step 4: Commit**

```bash
git add lib/dw-db.sh lib/tests/dw-db-artifacts.test.sh agents/tracker/sqlite.md
git commit -m "feat(sqlite): artifacts milestones decisions and sqlite.md port map"
```

---

### Task 6: Phase-agent 1S branches

**Files (each must gain explicit sqlite branch; no live `REQ-*.md` / `user-requests/` globs when backend=sqlite):**

| Agent | 1S behavior |
|-------|-------------|
| `status.md` | Step **1S**: `dw-db status-synth` (implement status-synth in Task 6a if not done — **must fold** derive+coverage+closed) |
| `intake.md` / `start.md` | `create-ur` |
| `ideate.md` | `append-ideate` |
| `question.md` | `append-clarifications` |
| `capture.md` / `audit.md` | create/update/list reqs via dw-db |
| `verify.md` | list+read + write-verify; score-coverage.sh stays shared |
| `run.md` | pick/claim via dw-db; no working/ |
| `run-worker.md` | read-req by slug; heartbeat; files from DB |
| `review.md` | read-req by slug |
| `resume.md` / `unblock.md` | dw-db claim/unblock by slug |
| `close.md` | write-close; evidence under evidence/ |
| `retro.md` | run_notes + calibration in DB |
| `log.md` | port-aware |
| `go.md` / `help.md` | mention board + sqlite |
| `upgrade.md` | already Task 2 refuse migrate |

**Also implement `dw-db status-synth` in this task if not present:**

Stdout sections approximate markdown synth + proven + coverage + closed from `ur_artifacts`/`closed_at`.

- [ ] **Step 1: Implement `status-synth` + test `lib/tests/dw-db-status.test.sh`**

Fixture: one done REQ with proof + AC checked → proven; UR with close artifact → closed=yes.

- [ ] **Step 2: Patch `status.md`**

Add branch table row:

| **`sqlite`** | Step **1S** — `bash {skill-root}/lib/dw-db.sh status-synth [UR-NNN]`; deadlock via `dw-db deadlock-check` or scan-stale; **never** glob working/ |

- [ ] **Step 3: Patch remaining agents**

For each agent file: Tracker load path already says `<backend>.md` — add explicit **1S** / **when sqlite** bullets mirroring **1L** pattern: call dw-db only; evidence path; hard-stop if dw-db fails.

Minimum for run.md:

```markdown
### When backend is sqlite
- list_claimable / claim / heartbeat / archive via `lib/dw-db.sh` only
- Worker receives REQ **slug** not filesystem path
- Do not mkdir user-requests or write REQ-*.md
```

- [ ] **Step 4: Grep gate**

```bash
# Agents must not document working/REQ as live path under sqlite without exclusion
rg -n 'working/REQ' agents/*.md
# Each should only appear inside markdown-backend sections
```

- [ ] **Step 5: Commit**

```bash
git add agents/*.md lib/dw-db.sh lib/tests/dw-db-status.test.sh
git commit -m "feat(sqlite): phase-agent 1S branches and status-synth parity"
```

---

### Task 7: `/do-work board` HTML snapshot

**Files:**
- Modify: `lib/dw-db.sh` — `board` command
- Create: `lib/tests/dw-db-board.test.sh`
- Create: `agents/board.md` (or extend `agents/help.md` + `references/commands.md`)
- Modify: `SKILL.md` Quick Reference row for `/do-work board`

**Interfaces:**
- `dw-db.sh board <project-root>` → writes `.do-work/board/index.html` (or config board_path), prints path
- HTML-escapes all user text (`<`, `>`, `&`, quotes)
- Includes `generated_at` ISO timestamp
- If called when... (CLI does not read config backend; **agent** hard-stops if backend ≠ sqlite). Optional: `board` works whenever DB exists.

- [ ] **Step 1: Failing board test**

Create UR/REQ with title `<script>alert(1)</script>`; board HTML must contain escaped entities not raw script tag executable form.

- [ ] **Step 2: Implement board**

Self-contained HTML, inline CSS, tables for URs + REQs by status, claimer, heartbeat age, stale banner (stale_max 900 default).

Escape function in bash:

```bash
html_escape() {
  # use sed/python-free: replace & first, then < > "
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}
```

- [ ] **Step 3: Agent + SKILL**

`agents/board.md`: Load Config → if backend ≠ sqlite hard-stop message → `dw-db board`.

SKILL quick reference:

`| /do-work board | Regenerate static HTML board from work.db (sqlite only). |`

- [ ] **Step 4: Commit**

```bash
bash lib/tests/dw-db-board.test.sh
bash lib/tests/run-all.sh
git add lib/dw-db.sh lib/tests/dw-db-board.test.sh agents/board.md SKILL.md references/commands.md
git commit -m "feat(sqlite): static HTML board generator with escaped content"
```

---

### Task 8: Docs, conformance notes, final regression

**Files:**
- Modify: `docs/troubleshooting.md` — sqlite section (switch greenfield, no migrate, board explicit, sqlite3 install, corrupt DB)
- Modify: `docs/HOW-IT-WORKS.md` — multi-tracker includes sqlite hierarchy (work.db)
- Modify: `docs/getting-started.md` if it lists backends
- Modify: `references/tracker.md` — sqlite keys
- Modify: `lib/conformance-scan.sh` header comment: missing user-requests not drift when sqlite; optional note
- Modify: design status line optional → `approved; plan in docs/superpowers/plans/...`

- [ ] **Step 1: Write troubleshooting section**

```markdown
## SQLite tracker backend
- Set tracker.backend: sqlite
- Requires sqlite3 on PATH
- Starts empty — prior markdown/Linear not imported
- /do-work board regenerates .do-work/board/index.html only when invoked
- work.db is gitignored
```

- [ ] **Step 2: Full test suite**

```bash
bash lib/tests/run-all.sh
```

Expected: all PASS (or skip only if sqlite3 missing — prefer fail CI if missing by documenting required tool).

- [ ] **Step 3: Port parity checklist** (manual in PR description)

Every op in `port.md` catalog appears in `agents/tracker/sqlite.md` with a dw-db command or local path (`write_gate_state`).

- [ ] **Step 4: Commit**

```bash
git add docs/ references/tracker.md lib/conformance-scan.sh
git commit -m "docs: sqlite tracker operator guide and multi-tracker HOW-IT-WORKS"
```

---

## Self-review (plan vs spec)

| Spec area | Task |
|-----------|------|
| Load path + hard-stop matrix | Task 1 |
| Schema, ensure, WAL, user_version, gitignore must | Task 2 |
| Numeric slug, CRUD, slug API, cross-UR deps | Task 3 |
| Claim/pick/footprint/stale release-insert/archive 3 checks/list-claimable | Task 4 |
| Artifacts, decisions, calibration, milestones, run notes, sqlite.md | Task 5 |
| Phase 1S inventory + status-synth parity | Task 6 |
| Board HTML escape, explicit command | Task 7 |
| Docs, refuse migrate, conformance | Task 8 |
| No migration | All tasks (no migrate op) |
| score-coverage shared | Task 6 verify note |
| Evidence paths | Task 5/6 |
| Default markdown regression | every task runs `run-all.sh` |

**Placeholder scan:** none intentional.

**Type consistency:** CLI name `lib/dw-db.sh`; commands hyphenated (`create-ur`, `list-claimable`, `status-synth`, `check-archive`); status storage `in_progress`.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-11-do-work-sqlite-tracker.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session with executing-plans and checkpoints  

Which approach?
