#!/usr/bin/env bash

# Child-process lifecycle support for build-macos.sh. Keep this Bash 3.2
# compatible: macOS still ships that version as /bin/bash.
ACTIVE_BUILD_CHILD_PID=""
PIDS=()

macos_run_tracked_child() {
  if [[ -n "$ACTIVE_BUILD_CHILD_PID" ]]; then
    echo "Internal error: macOS build child $ACTIVE_BUILD_CHILD_PID is still active" >&2
    return 1
  fi

  "$@" &
  ACTIVE_BUILD_CHILD_PID="$!"
  local child_pid="$ACTIVE_BUILD_CHILD_PID"
  local status=0
  if wait "$child_pid"; then
    status=0
  else
    status="$?"
  fi
  ACTIVE_BUILD_CHILD_PID=""
  return "$status"
}

macos_build_process_tree() {
  local roots="$1"
  if [[ -n "${MACOS_BUILD_PROCESS_TABLE_FILE:-}" ]]; then
    cat "$MACOS_BUILD_PROCESS_TABLE_FILE"
  else
    ps -axo pid=,ppid= 2>/dev/null
  fi | awk -v roots="$roots" '
    BEGIN {
      count = split(roots, root, " ")
      for (i = 1; i <= count; i++) {
        if (root[i] ~ /^[0-9]+$/) wanted[root[i]] = 1
      }
    }
    {
      pid[NR] = $1
      parent[NR] = $2
    }
    END {
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; i++) {
          if ((parent[i] in wanted) && wanted[parent[i]] == 1 && !(pid[i] in wanted)) {
            wanted[pid[i]] = 1
            changed = 1
          }
        }
      }
      for (candidate in wanted) {
        if (wanted[candidate] == 1) print candidate
      }
    }
  '
}

macos_build_pid_is_running() {
  local pid="$1"
  local state=""
  kill -0 "$pid" 2>/dev/null || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  [[ -n "$state" && "$state" != Z* ]]
}

macos_terminate_and_reap_build_children() {
  local roots=()
  local tree=()
  local root_list=""
  local pid=""
  local duplicate=0
  local attempt=0
  local any_running=0

  if [[ "$ACTIVE_BUILD_CHILD_PID" =~ ^[0-9]+$ ]]; then
    roots+=("$ACTIVE_BUILD_CHILD_PID")
  fi
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    duplicate=0
    local existing=""
    for existing in ${roots[@]+"${roots[@]}"}; do
      if [[ "$existing" == "$pid" ]]; then duplicate=1; break; fi
    done
    if (( duplicate == 0 )); then roots+=("$pid"); fi
  done
  (( ${#roots[@]} > 0 )) || return 0

  root_list="${roots[*]}"
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && tree+=("$pid")
  done < <(macos_build_process_tree "$root_list")

  # Signal the captured descendants and their direct build parents while the
  # app-local lock is still held. The second pass escalates stubborn compiler
  # processes; all directly-owned children are then waited to avoid zombies.
  for pid in ${tree[@]+"${tree[@]}"}; do kill -TERM "$pid" 2>/dev/null || true; done
  attempt=0
  while (( attempt < 20 )); do
    any_running=0
    for pid in ${tree[@]+"${tree[@]}"}; do
      if macos_build_pid_is_running "$pid"; then any_running=1; break; fi
    done
    (( any_running != 0 )) || break
    sleep 0.05
    attempt=$((attempt + 1))
  done
  for pid in ${tree[@]+"${tree[@]}"}; do
    if macos_build_pid_is_running "$pid"; then kill -KILL "$pid" 2>/dev/null || true; fi
  done
  for pid in ${roots[@]+"${roots[@]}"}; do wait "$pid" 2>/dev/null || true; done

  ACTIVE_BUILD_CHILD_PID=""
  PIDS=()
}
