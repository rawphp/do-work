#!/usr/bin/env bash
# Aggregate test runner for do-work's lib/ coordination primitives.
#
# Runs every plain-bash `*.test.sh` in this directory, plus every `*.bats`
# suite when the `bats` binary is available (otherwise it reports them as
# skipped rather than failing). Prints a one-line-per-suite result and a
# final summary, and exits non-zero if any suite fails.
#
# This is the canonical "run the whole suite" command:
#
#     bash lib/tests/run-all.sh
#
# Compatible with macOS bash 3.2.

set -u

TESTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pass=0
fail=0
skip=0
failed_suites=""

run_suite() {
  local name="$1"
  shift
  local out
  if out="$( "$@" 2>&1 )"; then
    printf 'PASS  %s\n' "$name"
    pass=$(( pass + 1 ))
  else
    printf 'FAIL  %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$(( fail + 1 ))
    failed_suites="$failed_suites $name"
  fi
}

# Plain-bash suites — the canonical style. `*.fixture.sh` and helpers are
# excluded by the `*.test.sh` glob.
for f in "$TESTS_DIR"/*.test.sh; do
  [ -e "$f" ] || continue
  run_suite "$( basename "$f" )" bash "$f"
done

# Bats suites — run only if bats is installed; never fail the run for a
# missing optional dependency.
bats_files=""
for f in "$TESTS_DIR"/*.bats; do
  [ -e "$f" ] || continue
  bats_files="$bats_files $f"
done

if [ -n "$bats_files" ]; then
  if command -v bats >/dev/null 2>&1; then
    for f in $bats_files; do
      run_suite "$( basename "$f" )" bats "$f"
    done
  else
    for f in $bats_files; do
      printf 'SKIP  %s (bats not installed)\n' "$( basename "$f" )"
      skip=$(( skip + 1 ))
    done
  fi
fi

echo "-----------------------------------------"
printf 'Suites: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
if [ "$fail" -ne 0 ]; then
  printf 'Failed:%s\n' "$failed_suites"
  exit 1
fi
exit 0
