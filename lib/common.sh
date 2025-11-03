#!/usr/bin/env bash
#
# Common functions for omarchy-rails-worktree
#

# Constants
readonly WORKTREE_CONFIG_DIR="${HOME}/.config/omarchy-rails-worktree"
readonly WORKTREE_PROJECTS_FILE="${WORKTREE_CONFIG_DIR}/projects"
readonly WORKTREE_LOCK_DIR="${WORKTREE_CONFIG_DIR}/locks"
readonly WORKTREE_RECENT_FILE="${WORKTREE_CONFIG_DIR}/recent_worktrees"
readonly MAX_RECENT_ITEMS=3
readonly SERVER_BASE_PORT=3000

# Error handling utilities
die() {
  echo -e "\e[31mError: $*\e[0m" >&2
  exit 1
}

warn() {
  echo -e "\e[33m⚠️  Warning: $*\e[0m" >&2
}

info() {
  echo -e "\e[32m$*\e[0m"
}

# Dependency checking
check_dependencies() {
  local missing_deps=()

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    die "Missing required dependencies: ${missing_deps[*]}"
  fi
}

# Git worktree functions
worktree_list() {
  git worktree list --porcelain 2>/dev/null | grep -E "^branch" | sed 's/branch refs\/heads\///g'
}

get_worktree_dir() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    die "get_worktree_dir: branch name required"
  fi

  git worktree list --porcelain 2>/dev/null | \
    grep -B2 -E "^branch refs/heads/${branch}$" | \
    head -n 1 | \
    sed 's/^worktree //'
}

worktree_exists() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    return 1
  fi

  worktree_list | grep -qxF "$branch"
}

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

# Project directory management
ensure_config_dir() {
  if [[ ! -d "$WORKTREE_CONFIG_DIR" ]]; then
    mkdir -p "$WORKTREE_CONFIG_DIR" || die "Failed to create config directory: $WORKTREE_CONFIG_DIR"
  fi
}

add_project_to_config() {
  local project_dir="$1"

  ensure_config_dir

  # Avoid duplicates
  if [[ -f "$WORKTREE_PROJECTS_FILE" ]] && grep -qxF "$project_dir" "$WORKTREE_PROJECTS_FILE"; then
    info "Project already registered: $project_dir"
    return 0
  fi

  echo "$project_dir" >> "$WORKTREE_PROJECTS_FILE"
}

get_projects_list() {
  if [[ ! -f "$WORKTREE_PROJECTS_FILE" ]]; then
    return 0
  fi

  cat "$WORKTREE_PROJECTS_FILE"
}

# Zellij session management
get_session_name() {
  local app_name="$1"
  local branch="$2"

  echo "${app_name}-${branch}"
}

session_exists() {
  local session_name="$1"

  if ! command -v zellij >/dev/null 2>&1; then
    return 1
  fi

  zellij list-sessions -n 2>/dev/null | grep -qE "^${session_name} "
}

session_is_alive() {
  local session_name="$1"

  if ! session_exists "$session_name"; then
    return 1
  fi

  local session_info
  session_info=$(zellij list-sessions -n 2>/dev/null | grep -E "^${session_name} ")

  # Check if session is not marked as EXITED
  if echo "$session_info" | grep -q "EXITED"; then
    return 1
  fi

  return 0
}

kill_zellij_session() {
  local session_name="$1"

  if ! command -v zellij >/dev/null 2>&1; then
    return 0
  fi

  if session_is_alive "$session_name"; then
    info "Killing active session: $session_name"
    zellij kill-session "$session_name" 2>/dev/null
    sleep 0.5  # Give it time to shutdown gracefully
  fi

  if session_exists "$session_name"; then
    info "Deleting session: $session_name"
    zellij delete-session "$session_name" 2>/dev/null
  fi
}

# Link shared resources
link_shared_resource() {
  local source_path="$1"
  local target_path="$2"
  local resource_name="$3"

  if [[ ! -e "$source_path" ]]; then
    warn "$resource_name not found: $source_path - skipping"
    return 1
  fi

  # Ensure target directory exists
  local target_dir
  target_dir=$(dirname "$target_path")
  mkdir -p "$target_dir"

  # Create symlink
  local absolute_source
  absolute_source=$(realpath "$source_path")
  ln -sf "$absolute_source" "$target_path"

  info "Linked $resource_name"
  return 0
}

# Recent worktree history tracking
record_worktree_access() {
  local project_dir="$1"
  local branch="$2"

  if [[ -z "$project_dir" ]] || [[ -z "$branch" ]]; then
    return 1
  fi

  ensure_config_dir

  local timestamp
  timestamp=$(date +%s)

  # Format: timestamp|project_dir|branch
  local entry="${timestamp}|${project_dir}|${branch}"

  # Create temp file for atomic update
  local temp_file="${WORKTREE_RECENT_FILE}.tmp.$$"

  # Remove old entries for this exact project+branch combination
  if [[ -f "$WORKTREE_RECENT_FILE" ]]; then
    grep -v "|${project_dir}|${branch}$" "$WORKTREE_RECENT_FILE" > "$temp_file" 2>/dev/null || true
  else
    touch "$temp_file"
  fi

  # Add new entry
  echo "$entry" >> "$temp_file"

  # Keep only last N entries (sorted by timestamp, newest first)
  sort -t'|' -k1 -rn "$temp_file" | head -n "$MAX_RECENT_ITEMS" > "${temp_file}.sorted"

  # Atomic replace
  mv "${temp_file}.sorted" "$WORKTREE_RECENT_FILE"
  rm -f "$temp_file"

  return 0
}

calculate_time_ago() {
  local timestamp="$1"
  local now
  now=$(date +%s)
  local diff=$((now - timestamp))

  if [[ $diff -lt 60 ]]; then
    echo "just now"
  elif [[ $diff -lt 3600 ]]; then
    local minutes=$((diff / 60))
    echo "${minutes}m ago"
  elif [[ $diff -lt 86400 ]]; then
    local hours=$((diff / 3600))
    echo "${hours}h ago"
  elif [[ $diff -lt 604800 ]]; then
    local days=$((diff / 86400))
    if [[ $days -eq 1 ]]; then
      echo "yesterday"
    else
      echo "${days}d ago"
    fi
  else
    echo "long ago"
  fi
}

generate_recent_items() {
  if [[ ! -f "$WORKTREE_RECENT_FILE" ]] || [[ ! -s "$WORKTREE_RECENT_FILE" ]]; then
    return 0
  fi

  # Read and format recent items (already sorted by timestamp, newest first)
  while IFS='|' read -r timestamp project_dir branch; do
    # Skip malformed lines
    if [[ -z "$timestamp" ]] || [[ -z "$project_dir" ]] || [[ -z "$branch" ]]; then
      continue
    fi

    # Skip if project no longer exists
    if [[ ! -d "$project_dir" ]]; then
      continue
    fi

    local project_name
    project_name=$(basename "$project_dir")

    local time_ago
    time_ago=$(calculate_time_ago "$timestamp")

    # Format: "⚡ project › branch (time ago)" with embedded metadata
    # Use special separator that won't appear in normal text
    echo "⚡ ${project_name} › ${branch} (${time_ago})|RECENT|${project_dir}|${branch}"
  done < "$WORKTREE_RECENT_FILE"
}

parse_recent_selection() {
  local selection="$1"

  # Extract metadata: display|RECENT|project_dir|branch
  local display marker project_dir branch
  IFS='|' read -r display marker project_dir branch <<< "$selection"

  # Return project_dir and branch on separate lines
  echo "$project_dir"
  echo "$branch"
}
