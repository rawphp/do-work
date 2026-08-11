#!/usr/bin/env bash
# dw-db-crud.test.sh — UR/REQ create, get, list, update, set-status, set-files, set-blocked-by.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DW="$LIB_DIR/dw-db.sh"
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED+1)); }

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 not installed"
  exit 0
fi

TMP="$(mktemp -d -t dw-crud.XXXXXX)"
mkdir -p "$TMP/.do-work"
bash "$DW" ensure "$TMP" >/dev/null || { echo "FAIL: ensure"; rm -rf "$TMP"; exit 1; }
db="$TMP/.do-work/work.db"

# --- create-ur ---
ur="$(bash "$DW" create-ur "$TMP" --title "My UR" --brief "the brief" --class feature)" \
  || { fail "create-ur failed"; rm -rf "$TMP"; exit 1; }
[ "$ur" = "UR-001" ] || fail "create-ur slug want UR-001 got $ur"

# get-ur
gout="$(bash "$DW" get-ur "$TMP" "$ur" 2>&1)" || fail "get-ur failed"
case "$gout" in *"$ur"*) : ;; *) fail "get-ur missing slug: $gout" ;; esac
case "$gout" in *"My UR"*) : ;; *) fail "get-ur missing title: $gout" ;; esac
case "$gout" in *"the brief"*) : ;; *) fail "get-ur missing brief: $gout" ;; esac
case "$gout" in *"feature"*) : ;; *) fail "get-ur missing class: $gout" ;; esac

# list-urs
lout="$(bash "$DW" list-urs "$TMP" 2>&1)" || fail "list-urs failed"
case "$lout" in *"$ur"*) : ;; *) fail "list-urs missing $ur: $lout" ;; esac

# --- create-req ---
req="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Do thing" --body "## Task
do it
## Acceptance Criteria
- [ ] works
" --priority 1 --files "lib/a.sh lib/b.sh" --layer domain --path-milestone M1)" \
  || { fail "create-req failed"; rm -rf "$TMP"; exit 1; }
[ "$req" = "REQ-001" ] || fail "create-req slug want REQ-001 got $req"

# default status backlog
status="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req';")"
[ "$status" = "backlog" ] || fail "default status want backlog got $status"

# get-req
rout="$(bash "$DW" get-req "$TMP" "$req" 2>&1)" || fail "get-req failed"
case "$rout" in *"$req"*) : ;; *) fail "get-req missing slug" ;; esac
case "$rout" in *"Do thing"*) : ;; *) fail "get-req missing title" ;; esac
case "$rout" in *"$ur"*) : ;; *) fail "get-req missing ur slug" ;; esac
case "$rout" in *"lib/a.sh"*) : ;; *) fail "get-req missing files" ;; esac

# list-reqs (all + filtered)
lall="$(bash "$DW" list-reqs "$TMP" 2>&1)" || fail "list-reqs failed"
case "$lall" in *"$req"*) : ;; *) fail "list-reqs missing $req" ;; esac
lur="$(bash "$DW" list-reqs "$TMP" --ur "$ur" 2>&1)" || fail "list-reqs --ur failed"
case "$lur" in *"$req"*) : ;; *) fail "list-reqs --ur missing $req" ;; esac

# --- update-req ---
bash "$DW" update-req "$TMP" "$req" --title "Do thing v2" --priority 3 \
  || fail "update-req failed"
rout2="$(bash "$DW" get-req "$TMP" "$req" 2>&1)"
case "$rout2" in *"Do thing v2"*) : ;; *) fail "update-req title not applied: $rout2" ;; esac
pri="$(sqlite3 "$db" "SELECT priority FROM reqs WHERE slug='$req';")"
[ "$pri" = "3" ] || fail "update-req priority want 3 got $pri"

# --- set-status: accepts in-progress, stores in_progress ---
bash "$DW" set-status "$TMP" "$req" in-progress || fail "set-status in-progress failed"
st="$(sqlite3 "$db" "SELECT status FROM reqs WHERE slug='$req';")"
[ "$st" = "in_progress" ] || fail "status want in_progress got $st (hyphen must normalize)"
bash "$DW" set-status "$TMP" "$req" backlog || fail "set-status backlog failed"

# --- set-files ---
bash "$DW" set-files "$TMP" "$req" "lib/x.sh lib/y.sh" || fail "set-files failed"
files="$(sqlite3 "$db" "SELECT files FROM reqs WHERE slug='$req';")"
[ "$files" = "lib/x.sh lib/y.sh" ] || fail "set-files want 'lib/x.sh lib/y.sh' got '$files'"

# --- set-blocked-by: valid deps + invalid slug fails ---
req2="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Second")" || fail "create-req 2 failed"
bash "$DW" set-blocked-by "$TMP" "$req" "$req2" || fail "set-blocked-by valid failed"
dep_n="$(sqlite3 "$db" "SELECT COUNT(*) FROM deps d
  JOIN reqs a ON a.id=d.req_id JOIN reqs b ON b.id=d.depends_on_req_id
  WHERE a.slug='$req' AND b.slug='$req2';")"
[ "$dep_n" = "1" ] || fail "deps row missing after set-blocked-by"

# replace semantics: set to empty clears
bash "$DW" set-blocked-by "$TMP" "$req" "" || fail "set-blocked-by empty failed"
dep_n2="$(sqlite3 "$db" "SELECT COUNT(*) FROM deps d JOIN reqs a ON a.id=d.req_id WHERE a.slug='$req';")"
[ "$dep_n2" = "0" ] || fail "empty set-blocked-by should clear deps, got $dep_n2"

# invalid slug → non-zero exit
if bash "$DW" set-blocked-by "$TMP" "$req" "REQ-99999" 2>/dev/null; then
  fail "set-blocked-by invalid slug should exit non-zero"
fi

# create-req with deps flag
req3="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Third" --deps "$req2")" \
  || fail "create-req --deps failed"
dep_n3="$(sqlite3 "$db" "SELECT COUNT(*) FROM deps d
  JOIN reqs a ON a.id=d.req_id JOIN reqs b ON b.id=d.depends_on_req_id
  WHERE a.slug='$req3' AND b.slug='$req2';")"
[ "$dep_n3" = "1" ] || fail "create-req --deps did not insert dep row"

# parent slug
parent="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Parent path")" || fail "parent create failed"
child="$(bash "$DW" create-req "$TMP" --ur "$ur" --title "Child" --parent "$parent")" \
  || fail "create-req --parent failed"
parent_id="$(sqlite3 "$db" "SELECT parent_req_id FROM reqs WHERE slug='$child';")"
expect_pid="$(sqlite3 "$db" "SELECT id FROM reqs WHERE slug='$parent';")"
[ "$parent_id" = "$expect_pid" ] || fail "parent_req_id want $expect_pid got $parent_id"

# invalid parent slug → fail
if bash "$DW" create-req "$TMP" --ur "$ur" --title "bad" --parent "REQ-00000" 2>/dev/null; then
  fail "create-req invalid parent should fail"
fi

# invalid UR on create-req → fail
if bash "$DW" create-req "$TMP" --ur "UR-00000" --title "bad" 2>/dev/null; then
  fail "create-req invalid UR should fail"
fi

# cross-UR deps allowed
ur2="$(bash "$DW" create-ur "$TMP" --title "Other" --brief "o")" || fail "create-ur 2"
req_other="$(bash "$DW" create-req "$TMP" --ur "$ur2" --title "Other req")" || fail "create-req other"
bash "$DW" set-blocked-by "$TMP" "$req" "$req_other" || fail "cross-UR set-blocked-by failed"
cross="$(sqlite3 "$db" "SELECT COUNT(*) FROM deps d
  JOIN reqs a ON a.id=d.req_id JOIN reqs b ON b.id=d.depends_on_req_id
  WHERE a.slug='$req' AND b.slug='$req_other';")"
[ "$cross" = "1" ] || fail "cross-UR dep not stored"

# get missing → non-zero
if bash "$DW" get-req "$TMP" "REQ-00000" 2>/dev/null; then
  fail "get-req missing should fail"
fi
if bash "$DW" get-ur "$TMP" "UR-00000" 2>/dev/null; then
  fail "get-ur missing should fail"
fi

rm -rf "$TMP"
[ "$FAILED" -eq 0 ] || exit 1
echo "PASS dw-db-crud"
