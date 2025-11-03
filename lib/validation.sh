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

  # Cannot start with a dot or slash
  if [[ "$branch" =~ ^\. || "$branch" =~ ^/ ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot start with '.' or '/'"
  fi

  # Cannot end with .lock
  if [[ "$branch" =~ \.lock$ ]]; then
    die "Invalid branch name: '$branch'. Branch names cannot end with '.lock'"
  fi

  return 0
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

# Validate worktree directory (must be in trees/ subdirectory)
validate_worktree_directory() {
  local worktree_dir="$1"

  if [[ -z "$worktree_dir" ]]; then
    die "Worktree directory cannot be empty"
  fi

  # Safety check: Must be in trees/ directory
  if [[ "$worktree_dir" != */trees/* ]]; then
    die "Worktree must be in 'trees/' directory. Got: $worktree_dir"
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
