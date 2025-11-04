#!/usr/bin/env bash
#
# Common functions for omarchy-rails-worktree
#

# Prevent multiple sourcing
if [[ -n "${OMARCHY_WORKTREE_COMMON_LOADED:-}" ]]; then
  return 0
fi
readonly OMARCHY_WORKTREE_COMMON_LOADED=1

# Get the directory containing this script
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Constants (only set if not already defined)
if [[ -z "${WORKTREE_CONFIG_DIR:-}" ]]; then
  readonly WORKTREE_CONFIG_DIR="${HOME}/.config/omarchy-rails-worktree"
  readonly WORKTREE_PROJECTS_FILE="${WORKTREE_CONFIG_DIR}/projects"
  readonly WORKTREE_LOCK_DIR="${WORKTREE_CONFIG_DIR}/locks"
  readonly WORKTREE_RECENT_FILE="${WORKTREE_CONFIG_DIR}/recent_worktrees"
  readonly MAX_RECENT_ITEMS=3
  readonly MODULES_DIR="${COMMON_LIB_DIR}/../modules"
fi

# Source validation functions if not already loaded
if [[ -z "$(type -t validate_branch_name 2>/dev/null)" ]]; then
  # shellcheck source=lib/validation.sh
  source "${COMMON_LIB_DIR}/validation.sh"
fi

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

ensure_worktrees_globally_ignored() {
  echo "DEBUG: Inside ensure_worktrees_globally_ignored" >&2
  local gitignore_path

  # 1. Read git config for current global gitignore configuration
  gitignore_path=$(git config --global core.excludesfile 2>/dev/null || true)
  echo "DEBUG: git config gitignore_path='$gitignore_path'" >&2

  if [[ -n "$gitignore_path" ]]; then
    # Expand tilde if present
    gitignore_path="${gitignore_path/#\~/$HOME}"
    echo "DEBUG: Using configured gitignore: $gitignore_path" >&2
  else
    # 2. Check for existing default locations in $HOME
    if [[ -f "$HOME/.gitignore_global" ]]; then
      gitignore_path="$HOME/.gitignore_global"
      echo "DEBUG: Found existing ~/.gitignore_global" >&2
      info "Using existing global gitignore: $gitignore_path"
      git config --global core.excludesfile "$gitignore_path"
    else
      # 3. Initialize in XDG default and set in git config
      local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
      gitignore_path="$xdg_config_home/git/ignore"
      echo "DEBUG: Using XDG standard location: $gitignore_path" >&2
      info "Configuring global gitignore at: $gitignore_path"
      git config --global core.excludesfile "$gitignore_path"
    fi
  fi

  echo "DEBUG: Final gitignore_path='$gitignore_path'" >&2

  # Create parent directory if needed
  local parent_dir
  parent_dir=$(dirname "$gitignore_path")
  if [[ ! -d "$parent_dir" ]]; then
    mkdir -p "$parent_dir"
  fi

  # Add .worktrees/ pattern if not already present
  if [[ -f "$gitignore_path" ]] && grep -qxF ".worktrees/" "$gitignore_path"; then
    info ".worktrees/ already in global gitignore"
  else
    echo ".worktrees/" >> "$gitignore_path"
    info "Added .worktrees/ to global gitignore: $gitignore_path"
  fi

  echo "DEBUG: Finished ensure_worktrees_globally_ignored" >&2
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

remove_worktree_from_recent() {
  local project_dir="$1"
  local branch="$2"

  if [[ -z "$project_dir" ]] || [[ -z "$branch" ]]; then
    return 1
  fi

  ensure_config_dir

  # If no recent file exists, nothing to remove
  if [[ ! -f "$WORKTREE_RECENT_FILE" ]]; then
    return 0
  fi

  # Create temp file for atomic update
  local temp_file="${WORKTREE_RECENT_FILE}.tmp.$$"

  # Remove entries for this exact project+branch combination
  grep -v "|${project_dir}|${branch}$" "$WORKTREE_RECENT_FILE" > "$temp_file" 2>/dev/null || true

  # Atomic replace
  mv "$temp_file" "$WORKTREE_RECENT_FILE"

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

# Git repository finder (interactive selection from $HOME)
find_git_repos_under_home() {
  echo -e "\e[33mSearching for git repositories under $HOME...\e[0m" >&2

  local repos
  repos=$(find "$HOME" -path "$HOME/.*" -prune -o -type d -name .git -print 2>/dev/null | sed 's|/.git$||' | sort)

  if [[ -z "$repos" ]]; then
    die "No git repositories found under $HOME"
  fi

  local selected
  selected=$(echo "$repos" | gum filter --placeholder="Select a git repository..." --height=20) || {
    die "No repository selected"
  }

  echo "$selected"
}

# Command functions (formerly standalone scripts)

# Initialize and register a new project for worktree management
worktree_init_project() {
  # Check dependencies
  check_dependencies gum git

  # Get project directory from argument or interactive selector
  local PROJECT_DIRECTORY
  if [[ -z "${1:-}" ]]; then
    PROJECT_DIRECTORY=$(find_git_repos_under_home)
    echo "DEBUG: Selected directory: '$PROJECT_DIRECTORY'" >&2
  else
    PROJECT_DIRECTORY="$1"
  fi

  if [[ -z "$PROJECT_DIRECTORY" ]]; then
    die "Project directory cannot be empty"
  fi

  echo "DEBUG: Before validation: '$PROJECT_DIRECTORY'" >&2
  # Validate and normalize the directory path
  PROJECT_DIRECTORY=$(validate_directory "$PROJECT_DIRECTORY")
  echo "DEBUG: After validation: '$PROJECT_DIRECTORY'" >&2

  # Validate that it's a git repository
  echo "DEBUG: Checking directory exists..." >&2
  require_directory_exists "$PROJECT_DIRECTORY"
  echo "DEBUG: Changing to directory..." >&2
  cd "$PROJECT_DIRECTORY" || die "Failed to cd to $PROJECT_DIRECTORY"
  echo "DEBUG: Validating git repository..." >&2
  validate_git_repository "$PROJECT_DIRECTORY"

  # Add to projects list
  echo "DEBUG: Adding to config..." >&2
  add_project_to_config "$PROJECT_DIRECTORY"

  # Detect and add default branch to recent items
  echo "DEBUG: Detecting default branch..." >&2
  local default_branch
  # Try to get the default branch from origin/HEAD
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

  # Fallback: check current branch
  if [[ -z "$default_branch" ]]; then
    default_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi

  # Fallback: check for common default branches
  if [[ -z "$default_branch" ]]; then
    if git show-ref --verify --quiet refs/heads/main; then
      default_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      default_branch="master"
    fi
  fi

  if [[ -n "$default_branch" ]]; then
    echo "DEBUG: Adding '$default_branch' to recent items..." >&2
    record_worktree_access "$PROJECT_DIRECTORY" "$default_branch"
    info "Added default branch '$default_branch' to recent items"
  fi

  info "✓ Project registered: $PROJECT_DIRECTORY"
  info "You can now use 'omarchy-rails-worktree' to manage worktrees for this project"
}

# Create a new worktree for a branch
worktree_create_branch() {
  # Check dependencies
  check_dependencies gum git

  # Ensure we're in a git repository
  require_git_repository

  # Get branch name from argument or prompt
  local BRANCH_NAME
  if [[ -z "${1:-}" ]]; then
    echo -e "\e[32mProvide a new or existing branch name\n\e[0m"
    BRANCH_NAME=$(gum input --placeholder="Branch name" --header="") || exit 1
  else
    BRANCH_NAME="$1"
  fi

  if [[ -z "$BRANCH_NAME" ]]; then
    die "Branch name cannot be empty"
  fi

  # Validate branch name
  validate_branch_name "$BRANCH_NAME"

  # Check if worktree already exists
  if worktree_exists "$BRANCH_NAME"; then
    die "Worktree for branch '$BRANCH_NAME' already exists!"
  fi

  # Set up directories
  local PROJECT_DIR WORKTREE_BASE_DIR WORKTREE_DIR
  PROJECT_DIR="$(pwd)"
  WORKTREE_BASE_DIR="${PROJECT_DIR}/.worktrees"
  WORKTREE_DIR="${WORKTREE_BASE_DIR}/${BRANCH_NAME}"

  # Validate that worktree directory doesn't already exist
  if [[ -e "$WORKTREE_DIR" ]]; then
    die "Directory already exists: $WORKTREE_DIR"
  fi

  # Create git worktree
  info "🌳 Creating git worktree..."
  if git worktree add "$WORKTREE_DIR" "$BRANCH_NAME" 2>/dev/null; then
    info "Using existing branch: $BRANCH_NAME"
  else
    # If branch doesn't exist, create it from HEAD
    info "Creating new branch: $BRANCH_NAME"
    git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" || die "Failed to create worktree"
  fi

  # Verify worktree was created
  if ! git worktree list | grep -qF "$WORKTREE_DIR"; then
    die "Failed to create worktree"
  fi

  # Run module-specific setup scripts
  info "🔧 Running setup modules..."
  if [[ -d "$MODULES_DIR" ]]; then
    for module_setup in "$MODULES_DIR"/*/setup; do
      if [[ -x "$module_setup" ]]; then
        "$module_setup" "$WORKTREE_DIR" "$BRANCH_NAME" "$PROJECT_DIR"
      fi
    done
  fi

  info ""
  info "✓ Worktree created successfully!"
  info "  Branch: $BRANCH_NAME"
  info "  Path: $WORKTREE_DIR"

  # Record this worktree in recent access list
  record_worktree_access "$PROJECT_DIR" "$BRANCH_NAME"
}

# Delete a worktree and its associated session
worktree_delete_branch() {
  # Check dependencies
  check_dependencies gum git

  # Ensure we're in a git repository
  require_git_repository

  # Get branch name
  if [[ -z "${1:-}" ]]; then
    die "Branch name required"
  fi

  local BRANCH_NAME="$1"

  # Validate branch name
  validate_branch_name "$BRANCH_NAME"

  # Get worktree directory from git
  local ACTUAL_WORKTREE_DIR
  ACTUAL_WORKTREE_DIR=$(get_worktree_dir "$BRANCH_NAME")

  if [[ -z "$ACTUAL_WORKTREE_DIR" ]]; then
    die "Branch '$BRANCH_NAME' is not a valid worktree"
  fi

  # Validate worktree directory (must be in .worktrees/)
  validate_worktree_directory "$ACTUAL_WORKTREE_DIR"

  # Get project directory for removing from recent items
  local PROJECT_DIR
  PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  # Show confirmation prompt
  warn "You are about to delete:"
  echo -e "  Branch: \e[1m$BRANCH_NAME\e[0m"
  echo -e "  Path: \e[1m$ACTUAL_WORKTREE_DIR\e[0m"
  echo ""

  if ! gum confirm "Delete this worktree?"; then
    info "Cancelled"
    exit 0
  fi

  # Get session name (using APP_NAME from parent environment)
  local SESSION_NAME
  if [[ -z "${APP_NAME:-}" ]]; then
    # Fallback: derive from current directory
    APP_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  fi

  SESSION_NAME=$(get_session_name "$APP_NAME" "$BRANCH_NAME")

  # Clean up zellij session
  echo ""
  info "🧹 Cleaning up zellij session..."

  kill_zellij_session "$SESSION_NAME"

  # Remove git worktree
  echo ""
  info "🌳 Removing git worktree..."

  if git worktree remove "$ACTUAL_WORKTREE_DIR" --force 2>&1; then
    info "✓ Worktree deleted successfully"

    # Remove from recent items
    remove_worktree_from_recent "$PROJECT_DIR" "$BRANCH_NAME"

    notify-send "Worktree deleted" "Branch: $BRANCH_NAME" 2>/dev/null || true
    exit 0
  fi

  # Fallback: try prune and manual removal
  warn "Git worktree remove failed, trying manual cleanup..."

  git worktree prune 2>/dev/null || true

  if [[ -d "$ACTUAL_WORKTREE_DIR" ]]; then
    rm -rf "$ACTUAL_WORKTREE_DIR" 2>/dev/null || true

    if [[ ! -d "$ACTUAL_WORKTREE_DIR" ]]; then
      info "✓ Worktree deleted (manual cleanup)"

      # Remove from recent items
      remove_worktree_from_recent "$PROJECT_DIR" "$BRANCH_NAME"

      notify-send "Worktree deleted" "Branch: $BRANCH_NAME (manual cleanup)" 2>/dev/null || true
      exit 0
    fi
  fi

  die "Failed to delete worktree: $ACTUAL_WORKTREE_DIR"
}
