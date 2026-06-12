#!/usr/bin/env bash
# retro-rollup.sh — deterministic aggregation over .do-work/runs/RUN-NNN.yml
# and the REQ files they reference. Emits machine-readable pattern stats for
# the retro agent (agents/retro.md) to interpret.
#
# Contract: docs/design/retro-learning.md §5a. Arithmetic only — no prose, no
# ranking-by-judgment, no file writes.
#
# Usage:
#   retro-rollup.sh            # analyzes ./.do-work/runs/
#
# Output lines (one fact per line):
#   runs=N
#   stop <shape-key> <reason>=<count>
#   stop_rate <shape-key>=<ratio>
#   escalation_rate=<ratio>
#   escalation <shape-key>=<count>
#   footprint under=<r> over=<r> exact=<r>
#   footprint_missed <glob>=<count>
#   recurrence <event>:<shape> weighted=<w> raw=<n>
#
# Shape key (§2a): <layer>/<ac-bucket>/<files-bucket>
#   ac-bucket:    ≤2AC | 3-4AC | >4AC
#   files-bucket: 1file | 2-3file | >3file
#
# Empty-state (§2e): prints `runs=0` and exits 0.
# Malformed entries: skipped with a warning on stderr, never crash.
#
# Compatible with macOS bash 3.2 (BSD) and Linux bash >= 4 (GNU).

set -u

DOWORK=".do-work"
RUNS_DIR="$DOWORK/runs"
# Recency window boundary (§2d). Injectable for deterministic tests.
NOW="${RETRO_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# ---------------------------------------------------------------------------
# Field extraction helpers
# ---------------------------------------------------------------------------

# Extract a scalar YAML field value from a ledger row file.
# Strips surrounding double quotes. Prints empty if absent.
ledger_scalar() {
  local field="$1" file="$2"
  grep -m1 -E "^${field}:[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^${field}:[[:space:]]*//; s/^\"//; s/\"$//"
}

# Extract the changed_files list (YAML block sequence) as a space-joined string.
ledger_changed_files() {
  local file="$1"
  awk '
    /^changed_files:/ { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      gsub(/"/, "", line)
      if (line != "" && line != "[]") print line
      next
    }
    in_list && /^[^[:space:]-]/ { in_list=0 }
  ' "$file" 2>/dev/null
}

# Extract a REQ **Field:** value (markdown bold field).
req_field() {
  local field="$1" file="$2"
  grep -m1 -E "^\*\*${field}:\*\*[[:space:]]*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}:\*\*[[:space:]]*//"
}

# Count acceptance criteria (- [ ] / - [x] lines) in a REQ file.
req_ac_count() {
  local file="$1"
  grep -c -E "^- \[[ xX]\]" "$file" 2>/dev/null || echo 0
}

# Locate the REQ file for a given REQ id across working/ and archive/ and root.
find_req_file() {
  local id="$1" d f
  for d in "$DOWORK/working" "$DOWORK/archive" "$DOWORK"; do
    [ -d "$d" ] || continue
    for f in "$d/$id"-*.md "$d/$id.md"; do
      [ -e "$f" ] && { printf '%s' "$f"; return 0; }
    done
  done
  return 1
}

# Bucket helpers (§2a).
ac_bucket() {
  local n="$1"
  if [ "$n" -le 2 ]; then echo "≤2AC"
  elif [ "$n" -le 4 ]; then echo "3-4AC"
  else echo ">4AC"; fi
}

files_bucket() {
  local n="$1"
  if [ "$n" -le 1 ]; then echo "1file"
  elif [ "$n" -le 3 ]; then echo "2-3file"
  else echo ">3file"; fi
}

# Count declared files in a REQ **Files:** line (comma-separated).
declared_files_count() {
  local files="$1"
  [ -z "$files" ] && { echo 0; return; }
  printf '%s' "$files" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -c '[^[:space:]]'
}

# Is ended_at within 30 days of NOW? Prints 1 (recent) or 0. Best-effort:
# if either timestamp is unparseable, returns 0 (not recent).
is_recent() {
  local ended="$1"
  [ -n "$ended" ] || { echo 0; return; }
  local now_e end_e
  now_e="$(ts_epoch "$NOW")"
  end_e="$(ts_epoch "$ended")"
  if [ -z "$now_e" ] || [ -z "$end_e" ]; then echo 0; return; fi
  local diff=$(( now_e - end_e ))
  [ "$diff" -lt 0 ] && diff=$(( -diff ))
  if [ "$diff" -le 2592000 ]; then echo 1; else echo 0; fi
}

# Convert an ISO-8601 UTC timestamp to epoch seconds (GNU or BSD date).
ts_epoch() {
  local ts="$1"
  [ -n "$ts" ] || return 0
  date -u -d "$ts" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
    || true
}

# ---------------------------------------------------------------------------
# Empty-state guard (§2e)
# ---------------------------------------------------------------------------

ROW_COUNT=0
if [ -d "$RUNS_DIR" ]; then
  for f in "$RUNS_DIR"/RUN-*.yml; do
    [ -e "$f" ] && ROW_COUNT=$((ROW_COUNT + 1))
  done
fi
if [ "$ROW_COUNT" -eq 0 ]; then
  echo "runs=0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pass 1: parse each ledger row into a flat record, joining to its REQ.
# Records are accumulated in a temp file: one TSV line per VALID row.
# Columns: req  shape  reason  model  recent  under  over  exact  missed_csv
# ---------------------------------------------------------------------------

TMP_ROWS="$(mktemp -t retro-rollup.XXXXXX)"
trap 'rm -f "$TMP_ROWS"' EXIT

analyzed=0
for f in "$RUNS_DIR"/RUN-*.yml; do
  [ -e "$f" ] || continue
  req_id="$(ledger_scalar "req" "$f")"
  # Malformed: a ledger row with no req field cannot be joined — skip + warn.
  if ! printf '%s' "$req_id" | grep -qE '^REQ-[0-9A-Za-z-]+$'; then
    echo "retro-rollup: skip malformed ledger row $(basename "$f") (no valid req field)" >&2
    continue
  fi

  model="$(ledger_scalar "model" "$f")"
  result="$(ledger_scalar "result" "$f")"
  review="$(ledger_scalar "review_outcome" "$f")"
  ended="$(ledger_scalar "ended_at" "$f")"
  changed="$(ledger_changed_files "$f")"

  # Stop reason: result, with review appended when done-but-flagged (§2a).
  reason="$result"
  if [ "$result" = "done" ] && [ -n "$review" ] && [ "$review" != "passed" ]; then
    reason="done-flagged"
  fi

  # Join to REQ file for shape + declared footprint.
  req_file="$(find_req_file "$req_id" || true)"
  if [ -n "$req_file" ] && [ -e "$req_file" ]; then
    layer="$(req_field "Layer" "$req_file")"
    [ -n "$layer" ] || layer="unknown"
    ac="$(req_ac_count "$req_file")"
    declared="$(req_field "Files" "$req_file")"
  else
    layer="unknown"; ac=0; declared=""
  fi
  fc="$(declared_files_count "$declared")"
  shape="${layer}/$(ac_bucket "$ac")/$(files_bucket "$fc")"

  recent="$(is_recent "$ended")"

  # Footprint join (§2c): compare declared set vs this row's changed set.
  # under = changed files not in declared; over = declared files not changed.
  declared_nl="$(printf '%s' "$declared" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')"
  under_n=0; missed_csv=""
  if [ -n "$changed" ]; then
    while IFS= read -r cf; do
      [ -z "$cf" ] && continue
      if ! printf '%s\n' "$declared_nl" | grep -Fxq "$cf"; then
        under_n=$((under_n + 1))
        if [ -z "$missed_csv" ]; then missed_csv="$cf"; else missed_csv="$missed_csv,$cf"; fi
      fi
    done <<EOF
$changed
EOF
  fi
  over_n=0
  if [ -n "$declared_nl" ]; then
    while IFS= read -r df; do
      [ -z "$df" ] && continue
      if ! printf '%s\n' "$changed" | grep -Fxq "$df"; then
        over_n=$((over_n + 1))
      fi
    done <<EOF
$declared_nl
EOF
  fi
  exact=0
  [ "$under_n" -eq 0 ] && [ "$over_n" -eq 0 ] && exact=1

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$req_id" "$shape" "$reason" "$model" "$recent" "$under_n" "$over_n" "$exact" "$missed_csv" \
    >> "$TMP_ROWS"
  analyzed=$((analyzed + 1))
done

echo "runs=$analyzed"
if [ "$analyzed" -eq 0 ]; then
  # All rows were malformed; nothing to aggregate beyond the sentinel.
  exit 0
fi

# ---------------------------------------------------------------------------
# Pass 2: aggregate. One awk over the TSV emits every remaining §5a line.
# ---------------------------------------------------------------------------

awk -F'\t' '
function ratio(num, den,   r) {
  if (den == 0) return "0.00"
  return sprintf("%.2f", num / den)
}
{
  req=$1; shape=$2; reason=$3; model=$4; recent=$5
  under=$6; over=$7; exact=$8; missed=$9

  total++

  # --- §2a stop-reason frequency by shape ---
  sk = shape SUBSEP reason
  stop[sk]++
  if (!(sk in stop_seen)) { stop_order[++stop_n]=sk; stop_seen[sk]=1 }
  shape_total[shape]++
  if (reason != "done") shape_nondone[shape]++
  if (!(shape in shape_seen)) { shape_order[++shape_n]=shape; shape_seen[shape]=1 }

  # --- §2b escalation (per REQ: did any row use opus?) ---
  if (!(req in req_seen)) { req_order[++req_n]=req; req_seen[req]=1; req_shape[req]=shape }
  if (model == "opus") req_opus[req]=1

  # --- §2c footprint per row ---
  fp_total++
  if (under > 0) fp_under++
  if (over > 0 && under == 0) fp_over++   # pure over-prediction row
  if (exact == 1) fp_exact++
  if (missed != "") {
    n=split(missed, parts, ",")
    for (i=1;i<=n;i++) {
      g=parts[i]
      if (g != "") {
        missed_count[g]++
        if (!(g in missed_seen)) { missed_order[++missed_n]=g; missed_seen[g]=1 }
      }
    }
  }

  # --- §2d recurrence: (event, shape) across distinct REQs ---
  # Map a non-done result to a fingerprint event vocabulary (file-feedback.sh).
  evt=""
  if (reason == "verification-failing") evt="verify-fail"
  else if (reason == "ambiguous-criteria") evt="ambiguous-criteria"
  else if (reason == "stale-slot") evt="stale-slot"
  else if (reason == "concurrent-conflict") evt="concurrent-conflict"
  if (under > 0) {
    # footprint-miss event keyed to this shape
    ekey="footprint-miss" SUBSEP shape
    reg_event(ekey, req, recent)
  }
  if (evt != "") {
    ekey=evt SUBSEP shape
    reg_event(ekey, req, recent)
  }
}
function reg_event(ekey, req, recent,   rk) {
  # raw count = distinct REQs exhibiting (event,shape)
  rk = ekey SUBSEP req
  if (!(rk in rec_req_seen)) {
    rec_req_seen[rk]=1
    rec_raw[ekey]++
    rec_weighted[ekey] += (recent == "1" ? 2 : 1)
    if (!(ekey in rec_seen)) { rec_order[++rec_n]=ekey; rec_seen[ekey]=1 }
  }
}
END {
  # §2a stop lines
  for (i=1;i<=stop_n;i++) {
    sk=stop_order[i]
    split(sk, p, SUBSEP)
    printf "stop %s %s=%d\n", p[1], p[2], stop[sk]
  }
  # §2a stop_rate per shape
  for (i=1;i<=shape_n;i++) {
    s=shape_order[i]
    printf "stop_rate %s=%s\n", s, ratio(shape_nondone[s]+0, shape_total[s])
  }

  # §2b escalation_rate + per-shape escalation counts
  esc=0
  for (i=1;i<=req_n;i++) {
    r=req_order[i]
    if (req_opus[r]==1) { esc++; esc_shape[req_shape[r]]++; \
      if (!(req_shape[r] in esc_seen)) { esc_order[++esc_n]=req_shape[r]; esc_seen[req_shape[r]]=1 } }
  }
  printf "escalation_rate=%s\n", ratio(esc, req_n)
  for (i=1;i<=esc_n;i++) {
    s=esc_order[i]
    printf "escalation %s=%d\n", s, esc_shape[s]
  }

  # §2c footprint rates + most-missed globs
  printf "footprint under=%s over=%s exact=%s\n", \
    ratio(fp_under+0, fp_total), ratio(fp_over+0, fp_total), ratio(fp_exact+0, fp_total)
  # most-missed globs, descending by count (stable order on ties = first seen)
  for (i=1;i<=missed_n;i++) {
    best=-1; bi=0
    for (j=1;j<=missed_n;j++) {
      g=missed_order[j]
      if (g in missed_done) continue
      if (missed_count[g] > best) { best=missed_count[g]; bi=j }
    }
    if (bi==0) break
    g=missed_order[bi]; missed_done[g]=1
    printf "footprint_missed %s=%d\n", g, missed_count[g]
  }

  # §2d recurrences: only pairs appearing in >=2 distinct REQs, ranked by weight
  for (i=1;i<=rec_n;i++) {
    best=-1; bi=0
    for (j=1;j<=rec_n;j++) {
      e=rec_order[j]
      if (e in rec_printed) continue
      if (rec_raw[e] < 2) continue
      if (rec_weighted[e] > best) { best=rec_weighted[e]; bi=j }
    }
    if (bi==0) break
    e=rec_order[bi]; rec_printed[e]=1
    split(e, p, SUBSEP)
    printf "recurrence %s:%s weighted=%d raw=%d\n", p[1], p[2], rec_weighted[e], rec_raw[e]
  }
}
' "$TMP_ROWS"

exit 0
