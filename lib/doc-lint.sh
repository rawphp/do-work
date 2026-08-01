#!/usr/bin/env bash
# doc-lint.sh — drift guard for the do-work live docs.
#
# Greps the live, normative docs (SKILL.md, README.md, docs/, agents/) for known
# stale ("drifted") patterns retired by past fixes, and exits non-zero with
# `file:line: pattern <name>` diagnostics when any fire. Each future doc-conflict
# fix should add its pattern here in the same commit (see CONTRIBUTING.md).
#
# Usage:
#   doc-lint.sh                 # scan the default live-doc roots under cwd
#   DOC_LINT_PATHS="a b" ...    # scan only the given files/dirs (space-separated)
#
# Excludes (never scanned): .do-work/, .git/, docs/superpowers/ (dated historical
# spec/plan tree), and any CHANGELOG.md. Archived REQs, changelog entries, and
# point-in-time design specs legitimately preserve retired terminology — scanning
# them would reproduce the UR-029 over-broad find-and-replace failure mode.
#
# Exit codes:
#   0  no drift found
#   1  at least one drift pattern fired

set -u

case "${1:-}" in
  -h|--help)
    sed -n '1,22p' "$0"
    exit 0
    ;;
esac

# Default live-doc roots, relative to cwd (the repo root). Missing roots are skipped.
DEFAULT_ROOTS="SKILL.md README.md docs agents"
ROOTS="${DOC_LINT_PATHS:-$DEFAULT_ROOTS}"

# is_excluded <path> — true if the path is in an archival/excluded location.
is_excluded() {
  case "$1" in
    */.do-work/*|.do-work/*) return 0 ;;
    */.git/*|.git/*) return 0 ;;
    */docs/superpowers/*|docs/superpowers/*) return 0 ;;
    */CHANGELOG.md|CHANGELOG.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Collect the markdown files to scan into a temp list (bash 3.2: no mapfile/arrays churn).
FILES_LIST="$(mktemp -t doc-lint-files.XXXXXX)"
trap 'rm -f "$FILES_LIST"' EXIT

for root in $ROOTS; do
  [ -e "$root" ] || continue
  if [ -f "$root" ]; then
    is_excluded "$root" && continue
    printf '%s\n' "$root" >> "$FILES_LIST"
  elif [ -d "$root" ]; then
    # All markdown files under the directory.
    find "$root" -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
      is_excluded "$f" && continue
      printf '%s\n' "$f"
    done >> "$FILES_LIST"
  fi
done

HITS=0

# report <file> <line-number> <pattern-name> <line-text>
report() {
  echo "$1:$2: pattern $3: $4"
  HITS=$((HITS + 1))
}

# --- Per-line pattern checks ---------------------------------------------------
# Each check scans one file's lines. line_no is 1-based.

scan_file() {
  local file="$1"
  local line_no=0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))

    # same-branch: retired isolation mode. Allowed only inside an explicit
    # retirement note (a line that also says it is "retired").
    case "$line" in
      *same-branch*)
        case "$line" in
          *retired*) : ;;  # explicit historical/retirement note — allowed
          *) report "$file" "$line_no" "same-branch" "$line" ;;
        esac
        ;;
    esac

    # --creative: no such flag exists (ideate is default-on).
    case "$line" in
      *--creative*) report "$file" "$line_no" "--creative" "$line" ;;
    esac

    # --grill: flag was removed.
    case "$line" in
      *--grill*) report "$file" "$line_no" "--grill" "$line" ;;
    esac

    # "resume or abort": stale run pre-flight prompt contradicting run.md.
    case "$line" in
      *"resume or abort"*) report "$file" "$line_no" "resume or abort" "$line" ;;
    esac
  done < "$file"
}

# bare-runtime-bash-lib: runtime docs under SKILL.md, agents/, and references/
# must invoke coordination scripts as `bash {skill-root}/lib/...` (Load Config
# step 8 / entry Project Root Detection). Bare `bash lib/` is a regression of
# the skill-root contract (UR-003 / ORI-242 / ORI-246).
# Allowlist skill-dev regression gates only under agents/ + references/:
# `bash lib/tests/...` and `bash lib/conformance-scan.sh` (tracker docs /
# CONTRIBUTING). On SKILL.md (skill entry), bare `bash lib/conformance-scan.sh`
# fails — entry conformance must use the skill-root form. A line that also
# says "never" is treated as a prohibition note documenting the anti-pattern
# (parity with same-branch + "retired"). Catalog identity `lib/*.sh` without a
# leading `bash ` is not matched.
scan_bare_runtime_bash_lib() {
  local file="$1"
  local line_no=0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    case "$line" in
      *'bash lib/'*)
        case "$line" in
          *'bash lib/tests/'*) : ;;  # skill-dev regression suite (any scoped path)
          *'bash lib/conformance-scan.sh'*)
            case "$file" in
              SKILL.md|*/SKILL.md)
                # Entry hole: do not allowlist bare conformance-scan on SKILL.md.
                # Permit only explicit prohibition notes (also say "never").
                case "$line" in
                  *never*) : ;;
                  *) report "$file" "$line_no" "bare-runtime-bash-lib" "$line" ;;
                esac
                ;;
              *) : ;;  # skill-dev gate under agents/ + references/
            esac
            ;;
          *) report "$file" "$line_no" "bare-runtime-bash-lib" "$line" ;;
        esac
        ;;
    esac
  done < "$file"
}

# --- Per-file structural check: judgment markers vs the file's own table -------
# A `> **JUDGMENT:** Jn ...` marker must have a matching `| Jn |` row in a
# Judgment Points table in the SAME file. Orphan markers indicate table drift.

scan_judgment_markers() {
  local file="$1"
  # Marker ids referenced inline (e.g. J2, J4) from JUDGMENT blocks.
  local marker_ids
  marker_ids="$(grep -Eo '\*\*JUDGMENT:\*\*[[:space:]]*J[0-9]+' "$file" 2>/dev/null \
    | grep -Eo 'J[0-9]+' | sort -u)"
  [ -z "$marker_ids" ] && return 0

  # Ids declared as table rows (a line whose first cell is the id, e.g. "| J2 |").
  local table_ids
  table_ids="$(grep -Eo '^\|[[:space:]]*J[0-9]+[[:space:]]*\|' "$file" 2>/dev/null \
    | grep -Eo 'J[0-9]+' | sort -u)"

  local id
  for id in $marker_ids; do
    case " $(echo $table_ids) " in
      *" $id "*) : ;;  # declared in the table — fine
      *)
        local mline
        mline="$(grep -nE "\*\*JUDGMENT:\*\*[[:space:]]*$id([^0-9]|$)" "$file" \
          | head -1 | cut -d: -f1)"
        report "$file" "${mline:-0}" "judgment-marker-orphan" "$id not in this file's Judgment Points table"
        ;;
    esac
  done
}

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue
  scan_file "$file"
  scan_judgment_markers "$file"
done < "$FILES_LIST"

# Path-scoped pass: SKILL.md + agents/ + references/ (runtime invocation fences).
# SKILL.md is the skill entry (ORI-246). Not folded into DEFAULT_ROOTS so
# references/ is not subject to unrelated patterns (e.g. judgment-marker tables
# that live in agents/). Use a temp list (not a pipeline) so HITS increments in
# report() are not lost to a subshell — bash 3.2 pipelines run the right-hand
# side in a subshell.
BARE_LIST="$(mktemp -t doc-lint-bare.XXXXXX)"
trap 'rm -f "$FILES_LIST" "$BARE_LIST"' EXIT
: > "$BARE_LIST"
if [ -f SKILL.md ]; then
  printf '%s\n' "SKILL.md" >> "$BARE_LIST"
fi
for root in agents references; do
  [ -d "$root" ] || continue
  find "$root" -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    is_excluded "$f" && continue
    printf '%s\n' "$f"
  done
done | sort -u >> "$BARE_LIST"
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue
  scan_bare_runtime_bash_lib "$file"
done < "$BARE_LIST"

if [ "$HITS" -ne 0 ]; then
  echo ""
  echo "doc-lint: $HITS drift hit(s) — fix the doc or extend the lint." >&2
  exit 1
fi

exit 0
