#!/usr/bin/env bash
# Eligibility PARITY tests — assert the markdown eligibility copies agree.
#
# Runs identical dependency + footprint scenarios through lib/check-deps.sh,
# lib/check-footprint.sh, and lib/pick-req.sh, and asserts they AGREE on the
# cases where the three copies currently produce the same result. This is the
# contract harness that makes drift between the copies LOUD (F1 / UR-003).
#
# REQ-012 delivered the currently-passing agreement cases (1–5). REQ-013
# (markdown consolidation into lib/eligibility-common.sh) added the
# formerly-drifting cases (6–8); they are GREEN now because all three copies
# source one canonical helper. Pre-consolidation each would have FAILED:
#   * `**` globstar footprint — pick-req lacked check-footprint's `**` walker.
#   * dep-satisfied definition — check-deps used `archive/<id>-*.md` only,
#     pick-req also accepted exact `archive/<id>.md`.
#   * unmatched-glob semantics — check-footprint dropped unmatched globs
#     (nullglob), pick-req retained the literal token.
#
# Plain bash (no bats). Exit non-zero on first failure. macOS bash 3.2 compatible.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CHECK_DEPS="$LIB_DIR/check-deps.sh"
CHECK_FOOTPRINT="$LIB_DIR/check-footprint.sh"
PICK_REQ="$LIB_DIR/pick-req.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}
assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}
assert_not_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: did not expect substring '$needle' in '$haystack'" ;;
  esac
}

PICK_ERR_FILE="$(mktemp -t elig-pick.XXXXXX)"
ROOTS=""
cleanup() {
  [ -n "$ROOTS" ] && rm -rf $ROOTS
  rm -f "$PICK_ERR_FILE"
}
trap cleanup EXIT
register() { ROOTS="$ROOTS $1"; }

# mkproject — echo a fresh temp project root with .do-work/{archive,working}.
mkproject() {
  local root
  root="$(mktemp -d -t elig-parity.XXXXXX)"
  mkdir -p "$root/.do-work/archive" "$root/.do-work/working"
  echo "$root"
}

# write_req <root> <filename> <ur> <deps-value> <files-value>
write_req() {
  local root="$1" file="$2" ur="$3" deps="$4" files="$5"
  cat > "$root/.do-work/$file" <<EOF
# ${file%.md}

**UR:** $ur
**Files:** $files
**Depends on:** $deps
EOF
}

# run_pick <root> — capture pick-req stdout+stderr. Sets PICK_OUT / PICK_ERR.
run_pick() {
  local root="$1"
  PICK_OUT="$( cd "$root" && bash "$PICK_REQ" any test-agent 2>"$PICK_ERR_FILE" )"
  PICK_ERR="$(cat "$PICK_ERR_FILE")"
}
run_deps() { ( cd "$1" && bash "$CHECK_DEPS" ".do-work/$2" ); }
run_fp()   { ( cd "$1" && bash "$CHECK_FOOTPRINT" ".do-work/$2" ); }

# ============================================================================
# DEPS PARITY — check-deps.sh vs pick-req.sh dep filter
# ============================================================================

# Case 1: dep IS archived → both consider it satisfied.
CURRENT_CASE="deps-archived-agree"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  write_req "$R" "REQ-500-cand.md" "UR-900" "REQ-501" "src/cand.php"
  write_req "$R" "REQ-501-done.md" "UR-900" ""        "src/done.php"
  mv "$R/.do-work/REQ-501-done.md" "$R/.do-work/archive/"
  deps_out="$(run_deps "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_eq "" "$deps_out" "check-deps reports no missing dep when archived"
  assert_contains "REQ-500-cand.md" "$PICK_OUT" "pick-req picks REQ-500 (dep satisfied)"
  assert_not_contains "dep:" "$PICK_ERR" "pick-req does not dep-reject when satisfied"
}

# Case 2: dep NOT archived → both reject.
CURRENT_CASE="deps-missing-agree"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  write_req "$R" "REQ-500-cand.md" "UR-900" "REQ-501" "src/cand.php"
  deps_out="$(run_deps "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_eq "REQ-501" "$deps_out" "check-deps reports REQ-501 missing"
  assert_eq "" "$PICK_OUT" "pick-req does not pick dep-blocked REQ-500"
  assert_contains "dep:REQ-501" "$PICK_ERR" "pick-req dep-rejects with REQ-501"
}

# ============================================================================
# FOOTPRINT PARITY — check-footprint.sh vs pick-req.sh overlap filter
# ============================================================================

# Case 3: footprint free → both pass. (Create the files so both expanders agree
# unambiguously — see the unmatched-glob drift note above.)
CURRENT_CASE="footprint-free-agree"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  mkdir -p "$R/src"
  touch "$R/src/cand.php" "$R/src/other.php"
  write_req "$R" "REQ-500-cand.md" "UR-900" "" "src/cand.php"
  write_req "$R" "REQ-501-slot.md" "UR-900" "" "src/other.php"
  mv "$R/.do-work/REQ-501-slot.md" "$R/.do-work/working/"
  fp_out="$(run_fp "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_eq "" "$fp_out" "check-footprint reports no overlap"
  assert_contains "REQ-500-cand.md" "$PICK_OUT" "pick-req picks REQ-500 (footprint free)"
  assert_not_contains "overlap:" "$PICK_ERR" "pick-req does not overlap-reject when free"
}

# Case 4: literal path overlap → both report.
CURRENT_CASE="footprint-overlap-agree"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  mkdir -p "$R/src"
  touch "$R/src/shared.php"
  write_req "$R" "REQ-500-cand.md" "UR-900" "" "src/shared.php"
  write_req "$R" "REQ-501-slot.md" "UR-900" "" "src/shared.php"
  mv "$R/.do-work/REQ-501-slot.md" "$R/.do-work/working/"
  fp_out="$(run_fp "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_contains "REQ-501" "$fp_out" "check-footprint reports overlap with REQ-501"
  assert_eq "" "$PICK_OUT" "pick-req does not pick overlap-blocked REQ-500"
  assert_contains "overlap:REQ-501" "$PICK_ERR" "pick-req overlap-rejects with REQ-501"
}

# Case 5: empty Files → both pass (no overlap possible).
CURRENT_CASE="footprint-empty-agree"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  write_req "$R" "REQ-500-cand.md" "UR-900" "" ""
  write_req "$R" "REQ-501-slot.md" "UR-900" "" "src/cand.php"
  mv "$R/.do-work/REQ-501-slot.md" "$R/.do-work/working/"
  fp_out="$(run_fp "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_eq "" "$fp_out" "check-footprint empty Files → no overlap"
  assert_contains "REQ-500-cand.md" "$PICK_OUT" "pick-req picks REQ-500 (empty footprint)"
}

# ============================================================================
# FORMERLY-DRIFTING CASES (REQ-013) — now GREEN via shared canonical helper.
# ============================================================================

# Case 6: `**` globstar footprint overlap — both detect it.
# Pre-fix pick-req had no `**` walker; check-footprint did → they disagreed.
CURRENT_CASE="footprint-globstar-parity"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  mkdir -p "$R/src/deep/nested"
  touch "$R/src/deep/nested/a.ts"
  write_req "$R" "REQ-500-cand.md" "UR-900" "" "src/deep/nested/a.ts"
  write_req "$R" "REQ-501-slot.md" "UR-900" "" "src/**/*.ts"
  mv "$R/.do-work/REQ-501-slot.md" "$R/.do-work/working/"
  fp_out="$(run_fp "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_contains "REQ-501" "$fp_out" "check-footprint detects ** overlap with REQ-501"
  assert_eq "" "$PICK_OUT" "pick-req does not pick **-overlap-blocked REQ-500"
  assert_contains "overlap:REQ-501" "$PICK_ERR" "pick-req overlap-rejects ** peer REQ-501"
}

# Case 7: dep satisfied via bare archive/<id>.md (no slug) — both agree satisfied.
# Pre-fix check-deps used glob-only and would have reported it missing.
CURRENT_CASE="deps-exact-archive-parity"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  write_req "$R" "REQ-500-cand.md" "UR-900" "REQ-501" "src/cand.php"
  # Bare exact archive name (no -slug suffix).
  printf '# REQ-501\n\n**UR:** UR-900\n**Files:** src/done.php\n**Depends on:**\n' \
    > "$R/.do-work/archive/REQ-501.md"
  deps_out="$(run_deps "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_eq "" "$deps_out" "check-deps treats bare archive/<id>.md as satisfied"
  assert_contains "REQ-500-cand.md" "$PICK_OUT" "pick-req picks REQ-500 (dep satisfied via exact archive)"
  assert_not_contains "dep:" "$PICK_ERR" "pick-req does not dep-reject (exact archive satisfied)"
}

# Case 8: unmatched literal footprint — both retain the literal and report overlap.
# Pre-fix check-footprint dropped unmatched globs → missed the conflict.
CURRENT_CASE="footprint-unmatched-literal-parity"; CASES=$((CASES + 1))
{
  R="$(mkproject)"; register "$R"
  # NOTE: src/ and the file are intentionally NOT created — the path is a
  # not-yet-existing literal both copies must retain.
  write_req "$R" "REQ-500-cand.md" "UR-900" "" "src/nonexistent.php"
  write_req "$R" "REQ-501-slot.md" "UR-900" "" "src/nonexistent.php"
  mv "$R/.do-work/REQ-501-slot.md" "$R/.do-work/working/"
  fp_out="$(run_fp "$R" "REQ-500-cand.md")"
  run_pick "$R"
  assert_contains "REQ-501" "$fp_out" "check-footprint retains literal → reports overlap with REQ-501"
  assert_eq "" "$PICK_OUT" "pick-req does not pick literal-overlap-blocked REQ-500"
  assert_contains "overlap:REQ-501" "$PICK_ERR" "pick-req overlap-rejects literal peer REQ-501"
}

# ============================================================================
# CROSS-BACKEND PARITY (REQ-014) — pin dw-db eligibility to the same contract.
# Each scenario builds an equivalent sqlite fixture and asserts dw-db's
# list-claimable makes the logically-correct decision. RESULT-parity, not
# mechanism-parity: dw-db's status-based deps / claims table are the correct
# sqlite analogue of markdown's archive/ + working/.
# ============================================================================
DWDB="$LIB_DIR/dw-db.sh"
mkdbproject() {
  local root
  root="$(mktemp -d -t elig-parity-db.XXXXXX)"
  bash "$DWDB" ensure "$root" >/dev/null 2>&1
  echo "$root"
}

# CB1: dep satisfied (depended-on REQ archived) → claimable.
CURRENT_CASE="xdb-dep-satisfied"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  B="$(bash "$DWDB" create-req "$R" --ur "$UR" --title B 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A --deps "$B" --files "src/a.php" 2>/dev/null)"
  bash "$DWDB" update-req "$R" "$B" --closure-proof "test" >/dev/null 2>&1
  bash "$DWDB" archive-req "$R" "$B" >/dev/null 2>&1   # B → done
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_contains "$A" "$lc" "dw-db lists A as claimable when its dep is done"
}

# CB2: dep unsatisfied (depended-on REQ not archived) → not claimable.
CURRENT_CASE="xdb-dep-unsatisfied"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  B="$(bash "$DWDB" create-req "$R" --ur "$UR" --title B 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A --deps "$B" --files "src/a.php" 2>/dev/null)"
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_not_contains "$A" "$lc" "dw-db omits A while its dep is not done"
}

# CB3: footprint free → claimable.
CURRENT_CASE="xdb-footprint-free"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  mkdir -p "$R/src"; touch "$R/src/a.php" "$R/src/c.php"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  C="$(bash "$DWDB" create-req "$R" --ur "$UR" --title C --files "src/c.php" 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A --files "src/a.php" 2>/dev/null)"
  bash "$DWDB" claim "$R" "$C" test-agent >/dev/null 2>&1   # C in-flight
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_contains "$A" "$lc" "dw-db lists A when footprint is free of in-flight C"
}

# CB4: footprint overlap (literal path) → not claimable.
CURRENT_CASE="xdb-footprint-overlap"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  mkdir -p "$R/src"; touch "$R/src/shared.php"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  C="$(bash "$DWDB" create-req "$R" --ur "$UR" --title C --files "src/shared.php" 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A --files "src/shared.php" 2>/dev/null)"
  bash "$DWDB" claim "$R" "$C" test-agent >/dev/null 2>&1   # C in-flight
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_not_contains "$A" "$lc" "dw-db omits A when footprint overlaps in-flight C"
}

# CB5: empty Files → claimable (no overlap possible).
CURRENT_CASE="xdb-footprint-empty"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  C="$(bash "$DWDB" create-req "$R" --ur "$UR" --title C --files "src/c.php" 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A 2>/dev/null)"   # no files
  bash "$DWDB" claim "$R" "$C" test-agent >/dev/null 2>&1
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_contains "$A" "$lc" "dw-db lists A when its footprint is empty"
}

# CB6: ** globstar footprint overlap → not claimable.
CURRENT_CASE="xdb-footprint-globstar"; CASES=$((CASES + 1))
{
  R="$(mkdbproject)"; register "$R"
  mkdir -p "$R/src/deep/nested"; touch "$R/src/deep/nested/a.ts"
  UR="$(bash "$DWDB" create-ur "$R" --title t --brief b 2>/dev/null)"
  C="$(bash "$DWDB" create-req "$R" --ur "$UR" --title C --files "src/**/*.ts" 2>/dev/null)"
  A="$(bash "$DWDB" create-req "$R" --ur "$UR" --title A --files "src/deep/nested/a.ts" 2>/dev/null)"
  bash "$DWDB" claim "$R" "$C" test-agent >/dev/null 2>&1
  lc="$(bash "$DWDB" list-claimable "$R" --ur "$UR" 2>/dev/null)"
  assert_not_contains "$A" "$lc" "dw-db omits A when ** footprint overlaps in-flight C"
}

echo "-----------------------------------------"
echo "Cases: $CASES run, $FAILED failed"
if [ "$FAILED" -ne 0 ]; then exit 1; fi
exit 0
