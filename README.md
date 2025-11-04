# omarchy-git-worktree

A powerful bash-based tool for managing Git worktrees with integrated Zellij terminal multiplexer sessions. This tool streamlines the workflow of working with multiple branches simultaneously, each with its own isolated development environment. Includes optional Rails-specific features through a modular system.

## Features

- **Worktree Management**: Create, open, and delete Git worktrees with ease
- **Environment Isolation**: Automatic port allocation and separate environment files for each worktree
- **Session Management**: Integrated Zellij terminal sessions for each worktree
- **Project Registry**: Manage multiple projects from a single interface
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
   git clone <repository-url> ~/.local/share/omarchy-git-worktree
   ```

2. Add the bin directory to your PATH:
   ```bash
   export PATH="$HOME/.local/share/omarchy-git-worktree/bin:$PATH"
   ```

3. Verify installation:
   ```bash
   omarchy-git-worktree --help
   ```

## Project Structure

```
omarchy-git-worktree/
├── bin/
│   └── omarchy-git-worktree           # Main menu interface
├── lib/
│   ├── common.sh                        # Shared utility functions and command implementations
│   └── validation.sh                    # Input validation functions
├── modules/
│   ├── rails/                           # Rails-specific setup module
│   └── claude/                          # Claude Code integration module
├── share/
│   └── zellij-layout.kdl               # Zellij layout configuration
└── README.md
```

## Usage

All operations are performed through the interactive menu interface. The tool is designed for menu-only workflow.

### Launch the Interactive Menu

```bash
omarchy-git-worktree
```

### Main Menu Options

The main menu provides access to:
- **Browse all projects** - View and open registered projects
- **Add worktree** - Create a new worktree in a registered project
- **Delete worktree** - Remove an existing worktree
- **Add project** - Register a new project

Recent worktrees are shown at the top for quick access.

### Registering a Project

1. Launch `omarchy-git-worktree`
2. Select **"Add project"**
3. Enter the path to your project (or browse interactively)

The tool will validate that the directory:
- Exists and is accessible
- Is a Git repository
- Adds `.worktrees/` to your global gitignore

### Creating a Worktree

1. From the main menu, select **"Add worktree"**
2. Choose the project
3. Enter a branch name (new or existing)

This will:
1. Create a Git worktree in `./.worktrees/<branch>/`
2. Allocate a unique port (starting from 3010, incrementing by 10)
3. Copy or create `.env` file with the allocated port
4. Link shared resources (master.key, Claude settings via modules)
5. Run module setup scripts (Rails: `bin/setup`, Claude: link settings)
6. Add to recent worktrees for quick access

**Example result:**
```
Creates worktree at ~/projects/my-rails-app/.worktrees/feature-auth
Allocates port 3010 (or next available)
Links master.key and Claude settings
Runs bin/setup and bin/ci (if available)
```

### Deleting a Worktree

1. From the main menu, select **"Delete worktree"**
2. Choose the project and worktree from the unified list
3. Confirm deletion

This will:
1. Validate the worktree exists and is in the `.worktrees/` directory
2. Show confirmation prompt
3. Kill and delete the associated Zellij session
4. Remove the Git worktree and directory
5. Remove from recent worktrees

**Safety:** Only worktrees in the `.worktrees/` subdirectory can be deleted to prevent accidental deletion of the main repository.

### Opening a Worktree

Two ways to open a worktree:

**Quick access (recent worktrees):**
1. Launch `omarchy-git-worktree`
2. Select from the recent worktrees shown at the top (⚡ icon)

**Browse all worktrees:**
1. Select **"Browse all projects"**
2. Choose your project
3. Select **"Open worktree"**
4. Choose the branch

The tool will:
- Change to the worktree directory
- Create or attach to the Zellij session named `<app>-<branch>`
- Launch the session with the configured layout
- Track as a recent worktree for future quick access

## How It Works

### Port Allocation

Each worktree gets a unique port to run the development server without conflicts:

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

For a project at `/home/user/myapp`:

```
/home/user/myapp/                  # Main repository
├── .worktrees/                         # Worktrees directory
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

Configuration is stored in `~/.config/omarchy-git-worktree/`:
- `projects` - List of registered projects (one path per line)
- `recent_worktrees` - Recently accessed worktrees for quick access (max 3)
- `locks/` - Port allocation lock files for concurrent worktree creation

### Zellij Layout

The default Zellij layout is defined in `share/zellij-layout.kdl`. Customize this file to change the terminal layout for your worktree sessions.

## Error Handling and Safety

### Input Validation

- Branch names are validated against Git naming rules
- Directory paths are normalized and checked for path traversal attempts
- Projects are validated as Git repositories

### Error Handling

All scripts use:
- `set -euo pipefail` for strict error handling
- Proper exit codes
- Informative error messages
- Cleanup traps for resource locks

### Safety Features

- **Worktree deletion** is restricted to the `.worktrees/` subdirectory only
- **Port locks** prevent race conditions during concurrent worktree creation
- **Branch name validation** prevents invalid or malicious input
- **Path validation** protects against directory traversal attacks

## Troubleshooting

### "Missing required dependencies" error

Install the missing tool(s) listed in the error message. See [Prerequisites](#prerequisites).

### Port conflicts

If you see port conflicts:
1. Check `~/.config/omarchy-git-worktree/locks/` for stale locks
2. Locks older than 1 hour are automatically cleaned up
3. Manually remove stale locks if needed: `rm ~/.config/omarchy-git-worktree/locks/port_*.lock`

### Worktree creation fails

Check that:
1. You're in a Git repository
2. The branch name is valid (no spaces or special characters)
3. The `.worktrees/` directory is writable
4. Module setup scripts exist if using modules (e.g., `bin/setup` for Rails projects)

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
