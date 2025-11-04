#!/usr/bin/env bash
#
# Rails-specific utilities for omarchy-git-worktree
#
# Note: This file expects WORKTREE_LOCK_DIR to be defined by the caller
#       (typically from lib/common.sh)

# Constants
readonly SERVER_BASE_PORT=3000

# Use WORKTREE_LOCK_DIR from common.sh, or fall back to default if not set
if [[ -z "${WORKTREE_LOCK_DIR:-}" ]]; then
  WORKTREE_LOCK_DIR="${HOME}/.config/omarchy-git-worktree/locks"
fi

# Port allocation with file-based locking
safe_port_allocation() {
  local worktree_base_dir="$1"
  local max_attempts=100
  local offset=1

  # Ensure lock directory exists
  mkdir -p "$WORKTREE_LOCK_DIR"

  # Collect all currently used port offsets from .env files
  declare -a used_offsets

  if [[ -d "$worktree_base_dir" ]]; then
    while IFS= read -r worktree_dir; do
      if [[ -f "$worktree_dir/.env" ]]; then
        local port
        port=$(grep "^PORT=" "$worktree_dir/.env" 2>/dev/null | cut -d= -f2)
        if [[ -n "$port" ]]; then
          local calculated_offset=$(( (port - SERVER_BASE_PORT) / 10 ))
          used_offsets+=("$calculated_offset")
        fi
      fi
    done < <(find "$worktree_base_dir" -mindepth 1 -maxdepth 2 -type d 2>/dev/null)
  fi

  # Find the smallest available offset with file locking
  while [[ $offset -le $max_attempts ]]; do
    local lock_file="${WORKTREE_LOCK_DIR}/port_${offset}.lock"

    # Try to acquire lock (create file exclusively)
    if (set -o noclobber; echo "$$" > "$lock_file") 2>/dev/null; then
      # Got the lock, check if offset is in use
      local offset_in_use=false

      for used_offset in "${used_offsets[@]}"; do
        if [[ "$used_offset" == "$offset" ]]; then
          offset_in_use=true
          break
        fi
      done

      if [[ "$offset_in_use" == "false" ]]; then
        # Found available offset, keep the lock and return
        echo "$offset"
        return 0
      else
        # Offset in use, release lock and try next
        rm -f "$lock_file"
      fi
    fi

    offset=$((offset + 1))
  done

  die "Failed to allocate port after $max_attempts attempts"
}

release_port_lock() {
  local offset="$1"
  local lock_file="${WORKTREE_LOCK_DIR}/port_${offset}.lock"

  # Only remove if we own the lock
  if [[ -f "$lock_file" && "$(cat "$lock_file" 2>/dev/null)" == "$$" ]]; then
    rm -f "$lock_file"
  fi
}

# Cleanup old/stale locks (locks older than 1 hour)
cleanup_stale_locks() {
  if [[ -d "$WORKTREE_LOCK_DIR" ]]; then
    find "$WORKTREE_LOCK_DIR" -name "port_*.lock" -type f -mmin +60 -delete 2>/dev/null
  fi
}
