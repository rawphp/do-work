#!/usr/bin/env bash
# cycle-check.sh — validate the **Depends on:** graph is acyclic.
#
# Usage:
#   cycle-check.sh           — check all REQs (backlog + working/ + archive/)
#   cycle-check.sh UR-NNN    — scope check to REQs whose **UR:** matches UR-NNN
#
# On cycle: prints the cycle path (e.g. REQ-007 → REQ-009 → REQ-007) to stdout
#           and exits 1.
# No cycle: silent, exits 0.
#
# Algorithm: iterative DFS cycle detection implemented entirely in awk so there
# is no shell-recursion stack — safe on linear chains of 1000+ REQs.
#
# Notes:
#   - UR-scoped mode: dep edges pointing to REQs whose **UR:** does NOT match
#     the scope are silently ignored (treated as satisfied leaves).
#   - REQ files are found in: .do-work/REQ-*.md (backlog), .do-work/working/,
#     .do-work/archive/  — all three are scanned.
#   - Multiple cycles: reports the first found (DFS order), exits 1.
#
# Compatible with macOS bash 3.2 and Linux bash >= 4.
# Standard POSIX tools only (grep, awk).

set -u

SCOPE="${1:-}"   # empty = all URs; otherwise e.g. "UR-030"
DOWORK=".do-work"

# --------------------------------------------------------------------------
# Collect candidate REQ files: backlog + working/ + archive/
# --------------------------------------------------------------------------
shopt -s nullglob 2>/dev/null || true

# Disable nounset while building arrays: bash 3.2 treats ${arr[@]} on an empty
# array as unbound when set -u is active. Re-enable after array construction.
set +u
BACKLOG_FILES=( "$DOWORK"/REQ-*.md )
WORKING_FILES=( "$DOWORK/working"/REQ-*.md )
ARCHIVE_FILES=( "$DOWORK/archive"/REQ-*.md )

ALL_FILES=( "${BACKLOG_FILES[@]}" "${WORKING_FILES[@]}" "${ARCHIVE_FILES[@]}" )
set -u

if [ "${#ALL_FILES[@]}" -eq 0 ]; then
  exit 0
fi

# --------------------------------------------------------------------------
# Extract id from filename (REQ-NNN or REQ-MNNN-NNN)
# --------------------------------------------------------------------------
req_id_from_path() {
  local base
  base="$(basename "$1")"
  # Strip the trailing -<slug>.md suffix — the id is everything up to the
  # first hyphen after the last digit sequence(s).
  # Portable awk approach: match the id prefix.
  printf '%s' "$base" | awk '{
    if (match($0, /^REQ-M[0-9]+-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else if (match($0, /^REQ-[0-9]+/)) {
      print substr($0, RSTART, RLENGTH)
    } else {
      print ""
    }
  }'
}

# --------------------------------------------------------------------------
# Build edge list as "PARENT CHILD" lines, filtered by SCOPE, then run
# iterative DFS cycle detection in awk.
# --------------------------------------------------------------------------

# We pipe a stream of lines to awk; each line is either:
#   NODE <id>   — declare a node (all in-scope REQ ids)
#   EDGE <from> <to>  — dep edge (from depends on to)
#
# awk builds the adjacency list and runs iterative DFS.

{
  for f in "${ALL_FILES[@]}"; do
    [ -e "$f" ] || continue

    req_id="$(req_id_from_path "$f")"
    [ -n "$req_id" ] || continue

    # Read **UR:** field
    ur_val="$(grep -m1 -E '^\*\*UR:\*\*[[:space:]]*' "$f" 2>/dev/null \
              | sed -E 's/^\*\*UR:\*\*[[:space:]]*//' \
              | sed 's/[[:space:]]*$//')"

    # If scoped, only include REQs matching the scope UR.
    if [ -n "$SCOPE" ] && [ "$ur_val" != "$SCOPE" ]; then
      continue
    fi

    printf 'NODE %s\n' "$req_id"

    # Read **Depends on:** field
    deps_raw="$(grep -m1 -E '^\*\*Depends on:\*\*[[:space:]]*' "$f" 2>/dev/null \
                | sed -E 's/^\*\*Depends on:\*\*[[:space:]]*//' \
                | sed 's/[[:space:]]*$//')"

    [ -n "$deps_raw" ] || continue

    # Split comma-separated deps and emit EDGE lines.
    printf '%s' "$deps_raw" | awk -v from="$req_id" '
    {
      n = split($0, parts, ",")
      for (i = 1; i <= n; i++) {
        dep = parts[i]
        # trim whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", dep)
        if (dep != "") {
          printf "EDGE %s %s\n", from, dep
        }
      }
    }'
  done
} | awk -v scope="$SCOPE" '
# -----------------------------------------------------------------------
# Iterative DFS cycle detection.
# Input lines: NODE <id>  or  EDGE <from> <to>
# -----------------------------------------------------------------------
/^NODE / {
  id = $2
  in_scope[id] = 1
  if (!(id in adj)) {
    adj[id] = ""   # ensure node exists in adj map
    adj_count[id] = 0
  }
}
/^EDGE / {
  from = $2
  to   = $3
  # Record the edge. Store as space-separated list for each node.
  # adj[from] = "to1 to2 to3 ..."
  if (adj_count[from] == 0) {
    adj[from] = to
  } else {
    adj[from] = adj[from] " " to
  }
  adj_count[from]++
}
END {
  # For each unvisited node, run iterative DFS.
  for (start in in_scope) {
    if (visited[start]) continue

    # Stack-based DFS.
    # stack[]: ids to visit
    # stack_edge_idx[]: which child edge index we are currently at
    # on_path[]: nodes on current DFS path (for cycle detection)
    # path_order[]: ordered list of nodes on current path

    stack_top = 0
    stack[stack_top] = start
    stack_edge_idx[stack_top] = 0
    delete on_path
    delete path_order
    path_len = 0

    while (stack_top >= 0) {
      node = stack[stack_top]

      if (!visited[node] && !on_path[node]) {
        # First visit to this node: mark on path
        on_path[node] = 1
        path_order[path_len] = node
        path_len++
      }

      # Get next unvisited child
      found_child = 0
      if (adj_count[node] > 0) {
        n_children = split(adj[node], children, " ")
        # Resume from where we left off
        edge_start = stack_edge_idx[stack_top]
        for (ci = edge_start + 1; ci <= n_children; ci++) {
          child = children[ci]
          # Skip edges to nodes outside scope (if scoped)
          if (scope != "" && !(child in in_scope)) {
            continue
          }

          # Update resume index
          stack_edge_idx[stack_top] = ci

          if (on_path[child]) {
            # Cycle detected — build cycle string.
            # Find where child appears in path_order
            cycle_start = -1
            for (k = 0; k < path_len; k++) {
              if (path_order[k] == child) {
                cycle_start = k
                break
              }
            }
            # Print cycle path
            cycle_str = child
            for (k = cycle_start; k < path_len; k++) {
              cycle_str = cycle_str " → " path_order[k]
            }
            # Actually: path_order[cycle_start] IS child, so build from there:
            # child → path_order[cycle_start+1] → ... → node → child
            cycle_str = child
            for (k = cycle_start + 1; k < path_len; k++) {
              cycle_str = cycle_str " → " path_order[k]
            }
            cycle_str = cycle_str " → " child
            print cycle_str
            exit 1
          }

          if (!visited[child]) {
            # Push child
            stack_top++
            stack[stack_top] = child
            stack_edge_idx[stack_top] = 0
            found_child = 1
            break
          }
        }
      }

      if (!found_child) {
        # Backtrack: pop this node
        on_path[node] = 0
        # Remove node from path_order (it is at path_len-1)
        path_len--
        visited[node] = 1
        stack_top--
      }
    }
  }
  exit 0
}
'
