#!/usr/bin/env bash
#
# Input validation and sanitization for omarchy-rails-worktree
#

# Source common functions if not already loaded
if [[ -z "${WORKTREE_CONFIG_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/common.sh
  source "${SCRIPT_DIR}/common.sh"
fi

# Validate branch name
validate_branch_name() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    die "Branch name cannot be empty"
  fi

  # Check for invalid characters in branch names
  # Git branch names cannot contain: spaces, ~, ^, :, ?, *, [, \, .., @{, //
  if [[ "$branch" =~ [[:space:]~^:?*\[\\\]] || "$branch" =~ \.\. || "$branch" =~ @\{ || "$branch" =~ // ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot contain spaces or special characters like ~^:?*[\\@{ or .."
  fi

  # Cannot contain slashes (would create subdirectories in .worktrees/)
  if [[ "$branch" =~ / ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot contain slashes ('/')"
  fi

  # Cannot start with a dot or slash
  if [[ "$branch" =~ ^\. ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot start with '.'"
  fi

  # Cannot end with .lock
  if [[ "$branch" =~ \.lock$ ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot end with '.lock'"
  fi

  return 0
}

# Prompt user for a valid branch name with retry on validation failure
# This is for interactive use - wraps validation with retry logic
# Returns the valid branch name on success, exits on max attempts or user cancellation
#
# Note: Keep validation logic in sync with validate_branch_name() above
prompt_for_valid_branch_name() {
  local branch_name=""
  local max_attempts=5
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    # Prompt for branch name
    if [[ $attempt -eq 1 ]]; then
      echo -e "\e[32mProvide a new or existing branch name\n\e[0m"
    else
      echo -e "\e[33mPlease try again with a valid branch name\n\e[0m"
    fi

    branch_name=$(gum input --placeholder="Branch name" --header="") || {
      die "Cancelled by user"
    }

    # Validation checks (inline to allow retry instead of exit)

    # Empty check
    if [[ -z "$branch_name" ]]; then
      warn "Branch name cannot be empty"
      ((attempt++))
      continue
    fi

    # Check for invalid characters in branch names
    # Git branch names cannot contain: spaces, ~, ^, :, ?, *, [, \, .., @{, //
    if [[ "$branch_name" =~ [[:space:]~^:?*\[\\\]] || "$branch_name" =~ \.\. || "$branch_name" =~ @\{ || "$branch_name" =~ // ]]; then
      warn "Invalid branch name: '$branch_name'. Branch names cannot contain spaces or special characters like ~^:?*[\\@{ or .."
      ((attempt++))
      continue
    fi

    # Cannot contain slashes (would create subdirectories in .worktrees/)
    if [[ "$branch_name" =~ / ]]; then
      warn "Invalid branch name: '$branch_name'. Branch names cannot contain slashes ('/')"
      ((attempt++))
      continue
    fi

    # Cannot start with a dot or slash
    if [[ "$branch_name" =~ ^\. ]]; then
      warn "Invalid branch name: '$branch_name'. Branch names cannot start with '.'"
      ((attempt++))
      continue
    fi

    # Cannot end with .lock
    if [[ "$branch_name" =~ \.lock$ ]]; then
      warn "Invalid branch name: '$branch_name'. Branch names cannot end with '.lock'"
      ((attempt++))
      continue
    fi

    # All validation passed - return the valid branch name
    echo "$branch_name"
    return 0
  done

  # Exceeded max attempts
  die "Maximum validation attempts ($max_attempts) exceeded"
}

# Validate and sanitize directory path
validate_directory() {
  local dir="$1"

  if [[ -z "$dir" ]]; then
    die "Directory path cannot be empty"
  fi

  # Expand tilde and resolve path
  dir="${dir/#\~/$HOME}"

  # Check for path traversal attempts
  if [[ "$dir" =~ \.\. ]]; then
    warn "Path contains '..' - normalizing path"
  fi

  # Normalize the path
  if [[ -e "$dir" ]]; then
    dir=$(realpath "$dir")
  else
    # If path doesn't exist, normalize the parent
    local parent
    parent=$(dirname "$dir")
    if [[ -e "$parent" ]]; then
      local basename
      basename=$(basename "$dir")
      dir="$(realpath "$parent")/${basename}"
    fi
  fi

  echo "$dir"
}

# Validate that directory exists
require_directory_exists() {
  local dir="$1"
  local description="${2:-Directory}"

  if [[ ! -d "$dir" ]]; then
    die "$description does not exist: $dir"
  fi
}

# Validate that directory does not exist
require_directory_not_exists() {
  local dir="$1"
  local description="${2:-Directory}"

  if [[ -e "$dir" ]]; then
    die "$description already exists: $dir"
  fi
}

# Validate that we're in a git repository
require_git_repository() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    die "Not in a git repository. Please run this command from within a git repository."
  fi
}

# Validate that directory is a git repository
validate_git_repository() {
  local dir="$1"

  require_directory_exists "$dir" "Project directory"

  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    die "Directory is not a git repository: $dir"
  fi
}

# Validate that directory is a Rails project
validate_rails_project() {
  local dir="$1"

  validate_git_repository "$dir"

  # Check for typical Rails files/directories
  if [[ ! -f "$dir/Gemfile" ]] || [[ ! -d "$dir/app" ]] || [[ ! -d "$dir/config" ]]; then
    die "Directory does not appear to be a Rails project: $dir"
  fi
}

# Validate worktree directory (must be in .worktrees/ subdirectory)
validate_worktree_directory() {
  local worktree_dir="$1"

  if [[ -z "$worktree_dir" ]]; then
    die "Worktree directory cannot be empty"
  fi

  # Safety check: Must be in .worktrees/ directory
  if [[ "$worktree_dir" != */.worktrees/* ]]; then
    die "Worktree must be in '.worktrees/' directory. Got: $worktree_dir"
  fi
}

# Sanitize input for safe display
sanitize_for_display() {
  local input="$1"

  # Remove control characters and other potentially problematic characters
  echo "$input" | tr -cd '[:print:]' | sed 's/[<>&]//g'
}

# Validate port number
validate_port() {
  local port="$1"

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    die "Invalid port number: $port"
  fi

  if [[ $port -lt 1024 || $port -gt 65535 ]]; then
    die "Port number out of range (1024-65535): $port"
  fi
}

# Check if port is available
is_port_available() {
  local port="$1"

  # Try to create a temporary listening socket on the port
  if command -v nc >/dev/null 2>&1; then
    # Use netcat to check if port is in use
    if nc -z localhost "$port" 2>/dev/null; then
      return 1  # Port is in use
    fi
  elif command -v lsof >/dev/null 2>&1; then
    # Use lsof to check if port is in use
    if lsof -i ":$port" >/dev/null 2>&1; then
      return 1  # Port is in use
    fi
  fi

  return 0  # Port appears to be available
}
