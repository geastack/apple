#!/usr/bin/env bash

# Optional workspace-wide resource lock for compiler-heavy native builds.
#
# Normal builds remain concurrent. Set GEA_SERIALIZE_HEAVY_BUILDS=1 only when
# an uncontaminated benchmark or a memory-constrained machine needs global
# serialization. Target/output correctness locks remain independent of this.

GEA_HEAVY_BUILD_LOCK_HELD="${GEA_HEAVY_BUILD_LOCK_HELD:-0}"
GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH="${GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH:-}"
GEA_HEAVY_BUILD_LOCK_TOKEN="${GEA_HEAVY_BUILD_LOCK_TOKEN:-}"

gea_heavy_build_lock_field() {
  local lock_path="$1"
  local field="$2"
  sed -n "s/^${field}=//p" "$lock_path" 2>/dev/null | head -n 1
}

gea_heavy_build_process_start() {
  local pid="$1"
  ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

gea_heavy_build_lock_owner_is_live() {
  local lock_path="$1"
  local owner_pid=""
  local recorded_start=""
  local current_start=""

  owner_pid="$(gea_heavy_build_lock_field "$lock_path" pid)"
  case "$owner_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if ! kill -0 "$owner_pid" 2>/dev/null; then
    return 1
  fi

  # A PID can be reused after a crashed owner. Match the process start time
  # when both the recorded and current platform expose it.
  recorded_start="$(gea_heavy_build_lock_field "$lock_path" process_start)"
  current_start="$(gea_heavy_build_process_start "$owner_pid")"
  if [ -n "$recorded_start" ] && [ -n "$current_start" ] && [ "$recorded_start" != "$current_start" ]; then
    return 1
  fi
  return 0
}

gea_report_heavy_build_lock_owner() {
  local lock_path="$1"
  local owner_pid=""
  local owner_kind=""
  local owner_label=""
  local owner_started=""

  owner_pid="$(gea_heavy_build_lock_field "$lock_path" pid)"
  owner_kind="$(gea_heavy_build_lock_field "$lock_path" kind)"
  owner_label="$(gea_heavy_build_lock_field "$lock_path" label)"
  owner_started="$(gea_heavy_build_lock_field "$lock_path" started_at)"
  echo "Another heavyweight build is already using this workspace:" >&2
  echo "  kind: ${owner_kind:-unknown}" >&2
  echo "  target: ${owner_label:-unknown}" >&2
  echo "  pid: ${owner_pid:-unknown}" >&2
  echo "  started: ${owner_started:-unknown}" >&2
  echo "Unset GEA_SERIALIZE_HEAVY_BUILDS or set GEA_ALLOW_CONCURRENT_HEAVY_BUILDS=1 to run concurrently." >&2
}

gea_acquire_heavy_build_lock() {
  local lock_path="$1"
  local kind="${2:-unknown}"
  local label="${3:-unknown}"
  local lock_parent=""
  local candidate=""
  local recovery_dir=""
  local token=""
  local process_start=""

  # Concurrency is the normal developer workflow. The workspace-wide lock is
  # deliberately opt-in for controlled benchmarks and low-memory machines.
  if [ "${GEA_SERIALIZE_HEAVY_BUILDS:-0}" != "1" ]; then
    return 0
  fi
  if [ "${GEA_ALLOW_CONCURRENT_HEAVY_BUILDS:-0}" = "1" ]; then
    echo "Heavy-build resource lock overridden for $kind '$label'." >&2
    return 0
  fi
  if [ "$GEA_HEAVY_BUILD_LOCK_HELD" = "1" ]; then
    echo "Heavy-build resource lock is already held by this process." >&2
    return 1
  fi

  lock_parent="$(dirname "$lock_path")"
  if [ ! -d "$lock_parent" ]; then
    echo "Heavy-build lock parent does not exist: $lock_parent" >&2
    return 1
  fi

  token="$$.$(date +%s).${RANDOM:-0}"
  candidate="$(mktemp "${lock_path}.candidate.XXXXXX")" || return 1
  recovery_dir="${lock_path}.recovery"
  process_start="$(gea_heavy_build_process_start "$$")"
  kind="${kind//$'\n'/ }"
  label="${label//$'\n'/ }"
  (
    umask 077
    {
      printf 'pid=%s\n' "$$"
      printf 'token=%s\n' "$token"
      printf 'process_start=%s\n' "$process_start"
      printf 'kind=%s\n' "$kind"
      printf 'label=%s\n' "$label"
      printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf 'host=%s\n' "$(hostname 2>/dev/null || echo unknown)"
      printf 'command=%s\n' "$0"
    } > "$candidate"
  )

  # `ln` installs a fully-written file atomically, avoiding mkdir+pid's small
  # window where a contender can mistake a new lock for stale state.
  if [ ! -d "$recovery_dir" ] && ln "$candidate" "$lock_path" 2>/dev/null; then
    rm -f "$candidate"
    GEA_HEAVY_BUILD_LOCK_HELD=1
    GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH="$lock_path"
    GEA_HEAVY_BUILD_LOCK_TOKEN="$token"
    return 0
  fi

  if gea_heavy_build_lock_owner_is_live "$lock_path"; then
    rm -f "$candidate"
    gea_report_heavy_build_lock_owner "$lock_path"
    return 1
  fi

  # Serialize stale-owner recovery. Re-read after winning recovery ownership,
  # because another contender may have replaced the stale file first.
  if ! mkdir "$recovery_dir" 2>/dev/null; then
    rm -f "$candidate"
    echo "Heavy-build lock ownership is changing; retry the build." >&2
    return 1
  fi
  if gea_heavy_build_lock_owner_is_live "$lock_path"; then
    rmdir "$recovery_dir" 2>/dev/null || true
    rm -f "$candidate"
    gea_report_heavy_build_lock_owner "$lock_path"
    return 1
  fi

  rm -f "$lock_path"
  if ! ln "$candidate" "$lock_path" 2>/dev/null; then
    rmdir "$recovery_dir" 2>/dev/null || true
    rm -f "$candidate"
    echo "Could not recover the stale heavy-build lock; retry the build." >&2
    return 1
  fi
  rmdir "$recovery_dir" 2>/dev/null || true
  rm -f "$candidate"
  GEA_HEAVY_BUILD_LOCK_HELD=1
  GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH="$lock_path"
  GEA_HEAVY_BUILD_LOCK_TOKEN="$token"
}

gea_release_heavy_build_lock() {
  local owner_pid=""
  local owner_token=""

  if [ "$GEA_HEAVY_BUILD_LOCK_HELD" != "1" ] || [ -z "$GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH" ]; then
    return 0
  fi
  owner_pid="$(gea_heavy_build_lock_field "$GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH" pid)"
  owner_token="$(gea_heavy_build_lock_field "$GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH" token)"
  if [ "$owner_pid" = "$$" ] && [ "$owner_token" = "$GEA_HEAVY_BUILD_LOCK_TOKEN" ]; then
    rm -f "$GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH"
  fi
  GEA_HEAVY_BUILD_LOCK_HELD=0
  GEA_HEAVY_BUILD_LOCK_ACTIVE_PATH=""
  GEA_HEAVY_BUILD_LOCK_TOKEN=""
}
