#!/usr/bin/env bash
# Eligibility PARITY tests — assert the markdown eligibility copies agree.
#
# Runs identical dependency + footprint scenarios through lib/check-deps.sh,
# lib/check-footprint.sh, and lib/pick-req.sh, and asserts they AGREE on the
# cases where the three copies currently produce the same result. This is the
# contract harness that makes drift between the copies LOUD (F1 / UR-003).
#
# Scope of this file (REQ-012): currently-passing agreement cases only. It must
# be GREEN on first commit. The known-drift assertions land red→green in the
# markdown-consolidation REQ, alongside the shared-helper refactor.
#
# KNOWN DRIFT — intentionally NOT asserted here yet:
#   * `**` globstar footprint: check-footprint.sh expands `**` via a manual
#     walker; pick-req.sh does plain bash glob (no `**` walker) → the two can
#     disagree on a footprint like `src/**/*.php`.
#   * dep-satisfied definition: check-deps.sh = `archive/<id>-*.md` only;
#     pick-req.sh = that OR exact `archive/<id>.md` → disagree on a bare
#     archive filename with no `-slug` suffix.
#   * unmatched-glob semantics: check-footprint.sh drops unmatched globs
#     (nullglob); pick-req.sh keeps the literal token → can disagree when a
#     declared path does not yet exist on disk.
# Each becomes a parity assertion in the consolidation REQ.
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

echo "-----------------------------------------"
echo "Cases: $CASES run, $FAILED failed"
if [ "$FAILED" -ne 0 ]; then exit 1; fi
exit 0
