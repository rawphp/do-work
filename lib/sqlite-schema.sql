-- Canonical do-work sqlite tracker schema (design §6.1).
-- user_version is set by lib/dw-db.sh ensure after apply (PRAGMA user_version=1).
-- Compatible with sqlite3 CLI; IF NOT EXISTS for idempotent re-apply on empty DB create path.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS urs (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  class TEXT NOT NULL DEFAULT '',
  brief TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  closed_at TEXT
);

CREATE TABLE IF NOT EXISTS ur_artifacts (
  id INTEGER PRIMARY KEY,
  ur_id INTEGER NOT NULL REFERENCES urs(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL,
  UNIQUE (ur_id, kind)
);

CREATE TABLE IF NOT EXISTS reqs (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  ur_id INTEGER NOT NULL REFERENCES urs(id),
  title TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'backlog'
    CHECK (status IN ('backlog', 'in_progress', 'stopped', 'done')),
  layer TEXT NOT NULL DEFAULT '',
  parent_req_id INTEGER REFERENCES reqs(id),
  entry_point TEXT NOT NULL DEFAULT '',
  terminal_state TEXT NOT NULL DEFAULT '',
  path_milestone TEXT,
  files TEXT NOT NULL DEFAULT '',
  size TEXT NOT NULL DEFAULT '',
  priority INTEGER,
  criteria_approved TEXT NOT NULL DEFAULT '',
  closure_proof TEXT NOT NULL DEFAULT '',
  suite TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS deps (
  req_id INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
  depends_on_req_id INTEGER NOT NULL REFERENCES reqs(id),
  PRIMARY KEY (req_id, depends_on_req_id)
);

CREATE TABLE IF NOT EXISTS claims (
  id INTEGER PRIMARY KEY,
  req_id INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
  agent_id TEXT NOT NULL,
  claimed_at TEXT NOT NULL,
  heartbeat TEXT NOT NULL,
  session TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'released'))
);

-- At most one active claim per req (design §6.1 locked constraint).
CREATE UNIQUE INDEX IF NOT EXISTS claims_one_active_per_req
  ON claims(req_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS decisions (
  id INTEGER PRIMARY KEY,
  line TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Single-row calibration body (id=1); retro full-replace.
CREATE TABLE IF NOT EXISTS calibration (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  body TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS milestone_state (
  id INTEGER PRIMARY KEY,
  ur_id INTEGER NOT NULL UNIQUE REFERENCES urs(id) ON DELETE CASCADE,
  active TEXT,
  checklist_json TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS run_notes (
  id INTEGER PRIMARY KEY,
  req_id INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
  payload TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
