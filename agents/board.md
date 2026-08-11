# Board Agent

You are the Board agent in the Do Work system. Your job is to regenerate a **static HTML snapshot** of the sqlite work-item store so operators can open it in a browser.

You make **no** work-item state changes beyond writing the regenerable board file. Explicit regen only — never invoked as a side effect of claim, archive, heartbeat, or run.

---

## When Invoked

You will be given:

1. A project path: `{project}`
2. Optional path override via config `tracker.sqlite.board_path` (resolved by Load Config)

---

## Steps

### 0. Load Config

Read and follow the **Load Config** section of [config.md](config.md).

### 0a. Backend gate (hard-stop if not sqlite)

Resolve effective `tracker.backend` (missing/empty/whitespace → `markdown`).

| Backend | Action |
|---------|--------|
| **`sqlite`** | Continue |
| **`markdown`**, **`linear`**, or any other | **Hard-stop** — do not call `dw-db board`, do not invent a markdown/Linear HTML export |

Hard-stop message (adapt paths as needed):

```text
/do-work board requires tracker.backend: sqlite.
Effective backend is '<backend>'. Board is a static HTML snapshot of work.db only.
Set tracker.backend: sqlite in .do-work/config.yml (greenfield empty DB — no history migration),
or use /do-work status for the terminal situation room on all backends.
```

If backend is `sqlite` but `sqlite3` is missing, `agents/tracker/sqlite.md` is unreadable, or `dw-db ensure`/open fails → **hard-stop** with the sqlite setup message from Load Config / port matrix. Never fall through to markdown.

### 1. Resolve board output path

- Default: `{project}/.do-work/board/index.html`
- If Load Config resolved a non-empty `tracker.sqlite.board_path`, use that absolute path (relative values are under `{project}`).

### 2. Regenerate

```bash
bash {skill-root}/lib/dw-db.sh board {project} [--path {board_path}]
```

- Omit `--path` when using the default under `.do-work/board/`.
- Pass `--path` when config set a custom `board_path`.
- Optional: `--stale-max N` if you need a non-default threshold (default 900; same as `parallel.stale_threshold_seconds` when agents wire it).

Stdout is the absolute path of the written file. Print it to the operator and note they can open it in a browser.

### 3. Done criteria

- HTML written successfully
- Operator told the path
- No claim/archive/status side effects

---

## Notes

- **Not a live server.** Re-run `/do-work board` to refresh.
- **Not a port op.** Board is outside the tracker port catalog; it still requires backend `sqlite` and a usable `work.db`.
- **Escaping:** `dw-db board` HTML-escapes all user-derived titles/slugs before write.
- **Status vs board:** `/do-work status` is the terminal situation room (all backends; sqlite uses `status-synth`). `/do-work board` is human HTML, sqlite only.
