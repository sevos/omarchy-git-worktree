# omarchy-rails-worktree

A powerful bash-based tool for managing Git worktrees in Rails projects with integrated Zellij terminal multiplexer sessions. This tool streamlines the workflow of working with multiple branches simultaneously, each with its own isolated development environment.

## Features

- **Worktree Management**: Create, open, and delete Git worktrees with ease
- **Environment Isolation**: Automatic port allocation and separate environment files for each worktree
- **Session Management**: Integrated Zellij terminal sessions for each worktree
- **Project Registry**: Manage multiple Rails projects from a single interface
- **Interactive Menu System**: User-friendly menu navigation using dmenu-style interface
- **Safe Operations**: Input validation, error handling, and file-based locking for port allocation
- **Shared Resources**: Automatic linking of master.key and Claude settings across worktrees

## Prerequisites

### Required Dependencies

- **bash** (>= 4.0)
- **git** - for worktree management
- **gum** - for interactive prompts ([charmbracelet/gum](https://github.com/charmbracelet/gum))
- **zellij** - terminal multiplexer ([zellij-org/zellij](https://github.com/zellij-org/zellij))

### Omarchy Ecosystem Tools

This tool is part of the Omarchy ecosystem and requires these custom tools:
- **omarchy-launch-walker** - dmenu-style menu launcher
- **omarchy-launch-terminal** - terminal launcher
- **omarchy-launch-floating-terminal-with-presentation** - floating terminal helper

### Optional Dependencies

- **notify-send** - for desktop notifications (recommended)
- **alacritty** - terminal emulator (or configure alternative)

## Installation

1. Clone this repository:
   ```bash
   git clone <repository-url> ~/.local/share/omarchy-rails-worktree
   ```

2. Add the bin directory to your PATH:
   ```bash
   export PATH="$HOME/.local/share/omarchy-rails-worktree/bin:$PATH"
   ```

3. Verify installation:
   ```bash
   omarchy-rails-worktree --help
   ```

## Project Structure

```
omarchy-rails-worktree/
├── bin/
│   ├── omarchy-rails-worktree           # Main menu interface
│   ├── omarchy-rails-worktree-init      # Register new Rails projects
│   ├── omarchy-rails-worktree-create    # Create new worktrees
│   └── omarchy-rails-worktree-delete    # Delete worktrees
├── lib/
│   ├── common.sh                        # Shared utility functions
│   └── validation.sh                    # Input validation functions
├── share/
│   └── zellij-layout.kdl               # Zellij layout configuration
└── README.md
```

## Usage

### Registering a Rails Project

Before creating worktrees, register your Rails project:

```bash
omarchy-rails-worktree-init /path/to/your/rails/project
```

Or run without arguments for an interactive prompt:

```bash
omarchy-rails-worktree-init
```

The tool will validate that the directory:
- Exists and is accessible
- Is a Git repository
- Contains Rails project files (Gemfile, app/, config/)

### Using the Main Menu

Launch the interactive menu:

```bash
omarchy-rails-worktree
```

Navigate through the menu to:
1. **Open project** - Select a registered Rails project
2. **Add project** - Register a new Rails project

After selecting a project:
- **Open worktree** - Open an existing worktree in Zellij
- **Add worktree** - Create a new worktree
- **Delete worktree** - Remove an existing worktree

### Creating a Worktree

From your Rails project directory:

```bash
omarchy-rails-worktree-create feature-branch
```

Or run without arguments for an interactive prompt.

This will:
1. Create a Git worktree in `./trees/feature-branch/`
2. Allocate a unique port (starting from 3010, incrementing by 10)
3. Copy or create `.env` file with the allocated port
4. Link shared resources (master.key, Claude settings)
5. Run `bin/setup` and optionally `bin/ci` for validation

**Example:**
```bash
cd ~/projects/my-rails-app
omarchy-rails-worktree-create fix-auth-bug
# Creates worktree at ~/projects/my-rails-app/trees/fix-auth-bug
# Allocates port 3010 (or next available)
```

### Deleting a Worktree

```bash
omarchy-rails-worktree-delete feature-branch
```

This will:
1. Validate the worktree exists and is in the `trees/` directory
2. Show confirmation prompt
3. Kill and delete the associated Zellij session
4. Remove the Git worktree and directory

**Safety:** Only worktrees in the `trees/` subdirectory can be deleted to prevent accidental deletion of the main repository.

### Opening a Worktree

Use the main menu to:
1. Select "Open project"
2. Choose your Rails project
3. Select "Open worktree"
4. Choose the branch

The tool will:
- Change to the worktree directory
- Create or attach to the Zellij session named `<app>-<branch>`
- Launch the session with the configured layout

## How It Works

### Port Allocation

Each worktree gets a unique port to run the Rails server without conflicts:

- **Base port:** 3000
- **Port calculation:** `3000 + (offset * 10)`
- **Port locking:** File-based locks prevent race conditions when creating multiple worktrees simultaneously
- **Automatic cleanup:** Stale locks (older than 1 hour) are automatically removed

Example:
- Main repository: port 3000 (not managed)
- First worktree: port 3010
- Second worktree: port 3020
- Third worktree: port 3030

### Directory Structure

For a Rails project at `/home/user/myapp`:

```
/home/user/myapp/                  # Main repository
├── trees/                         # Worktrees directory
│   ├── feature-a/                # Worktree for feature-a branch
│   │   ├── .env                  # Environment with PORT=3010
│   │   └── config/
│   │       └── master.key       # Symlink to main repository
│   ├── feature-b/                # Worktree for feature-b branch
│   │   ├── .env                  # Environment with PORT=3020
│   │   └── config/
│   │       └── master.key       # Symlink to main repository
```

### Shared Resources

The following files are automatically linked from the main repository:
- `config/master.key` - Rails credentials
- `.claude/settings.local.json` - Claude Code settings

This ensures all worktrees share the same credentials and configuration.

### Zellij Sessions

Each worktree gets its own Zellij session with format: `<app-name>-<branch-name>`

Example: For app "myapp" and branch "feature-auth", the session name is `myapp-feature-auth`

The tool intelligently:
- Creates a new session if it doesn't exist
- Attaches to an existing running session
- Recreates a session if it exited abnormally

## Configuration

### Config Directory

Configuration is stored in `~/.config/omarchy-rails-worktree/`:
- `projects` - List of registered Rails projects (one path per line)
- `locks/` - Port allocation lock files

### Zellij Layout

The default Zellij layout is defined in `share/zellij-layout.kdl`. Customize this file to change the terminal layout for your worktree sessions.

## Error Handling and Safety

### Input Validation

- Branch names are validated against Git naming rules
- Directory paths are normalized and checked for path traversal attempts
- Projects are validated as Git repositories and Rails applications

### Error Handling

All scripts use:
- `set -euo pipefail` for strict error handling
- Proper exit codes
- Informative error messages
- Cleanup traps for resource locks

### Safety Features

- **Worktree deletion** is restricted to the `trees/` subdirectory only
- **Port locks** prevent race conditions during concurrent worktree creation
- **Branch name validation** prevents invalid or malicious input
- **Path validation** protects against directory traversal attacks

## Troubleshooting

### "Missing required dependencies" error

Install the missing tool(s) listed in the error message. See [Prerequisites](#prerequisites).

### Port conflicts

If you see port conflicts:
1. Check `~/.config/omarchy-rails-worktree/locks/` for stale locks
2. Locks older than 1 hour are automatically cleaned up
3. Manually remove stale locks if needed: `rm ~/.config/omarchy-rails-worktree/locks/port_*.lock`

### Worktree creation fails

Check that:
1. You're in a Git repository
2. The branch name is valid (no spaces or special characters)
3. The `trees/` directory is writable
4. `bin/setup` exists in your Rails project

### Zellij session issues

- List all sessions: `zellij list-sessions`
- Delete a session manually: `zellij delete-session <session-name>`
- Kill a running session: `zellij kill-session <session-name>`

## Development

### Running Tests

(Tests to be implemented)

### Shell Script Linting

Use ShellCheck to validate the scripts:

```bash
shellcheck bin/* lib/*
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

(Add license information)

## Credits

Part of the Omarchy ecosystem for Rails development workflow management.
