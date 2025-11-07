#!/bin/bash
# Interactive TUI for configuring Zellij tabs
# Supports enable/disable, reordering with Ctrl+Up/Down

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/zellij-manager.sh"

# Terminal control codes
CLEAR='\033[2J\033[H'
CURSOR_HIDE='\033[?25l'
CURSOR_SHOW='\033[?25h'
REVERSE='\033[7m'
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
DIM='\033[2m'

# State variables
declare -a TAB_IDS=()
declare -a TAB_NAMES=()
declare -a TAB_ENABLED=()
declare -a TAB_DESCRIPTIONS=()
declare CURRENT_LINE=0
declare PROJECT_DIR=""

# Initialize tab configuration
init_tab_config() {
    PROJECT_DIR="${1:?Project directory required}"
    local available_tabs
    local existing_config

    # Get available tabs
    available_tabs=$(detect_available_tabs "$PROJECT_DIR")

    # Try to load existing configuration
    existing_config=$(load_tab_config "$PROJECT_DIR" 2>/dev/null || echo "")

    # Build tab arrays
    local index=0

    # If we have existing config, use its order first
    if [[ -n "$existing_config" ]]; then
        # Add tabs from existing config in their original order
        while IFS= read -r tab_id; do
            [[ -z "$tab_id" ]] && continue

            # Only add if it's still available
            if echo "$available_tabs" | grep -q "^${tab_id}$"; then
                TAB_IDS[$index]="$tab_id"
                TAB_NAMES[$index]=$(get_tab_metadata "$tab_id" "name")
                TAB_DESCRIPTIONS[$index]=$(get_tab_metadata "$tab_id" "description")
                TAB_ENABLED[$index]="true"
                index=$((index + 1))
            fi
        done <<< "$existing_config"

        # Add any new tabs that weren't in the existing config
        while IFS= read -r tab_id; do
            [[ -z "$tab_id" ]] && continue

            # Skip if already added from existing config
            local already_added=false
            for existing_id in "${TAB_IDS[@]}"; do
                if [[ "$existing_id" == "$tab_id" ]]; then
                    already_added=true
                    break
                fi
            done

            if [[ "$already_added" == "false" ]]; then
                TAB_IDS[$index]="$tab_id"
                TAB_NAMES[$index]=$(get_tab_metadata "$tab_id" "name")
                TAB_DESCRIPTIONS[$index]=$(get_tab_metadata "$tab_id" "description")
                TAB_ENABLED[$index]="false"  # New tabs are disabled by default
                index=$((index + 1))
            fi
        done <<< "$available_tabs"
    else
        # No existing config, use available tabs and enable all by default
        while IFS= read -r tab_id; do
            [[ -z "$tab_id" ]] && continue

            TAB_IDS[$index]="$tab_id"
            TAB_NAMES[$index]=$(get_tab_metadata "$tab_id" "name")
            TAB_DESCRIPTIONS[$index]=$(get_tab_metadata "$tab_id" "description")

            # Check if tab is always enabled
            local is_always_enabled
            is_always_enabled=$(get_tab_metadata "$tab_id" "always_enabled")

            if [[ "$is_always_enabled" == "true" ]]; then
                TAB_ENABLED[$index]="true"
            else
                # Enable by default for first-time setup
                TAB_ENABLED[$index]="true"
            fi

            index=$((index + 1))
        done <<< "$available_tabs"
    fi
}

# Draw the screen
draw_screen() {
    echo -ne "${CLEAR}"
    echo -ne "${CURSOR_HIDE}"

    # Header
    echo -e "${BLUE}┌─ Configure Zellij Tabs ────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET}%64s${BLUE}│${RESET}\n" ""

    # Tabs list
    for i in "${!TAB_IDS[@]}"; do
        local checkbox_color="${DIM}"
        local status_color="${DIM}"
        local status_text="DISABLED"

        # Set colors based on enabled state
        if [[ "${TAB_ENABLED[$i]}" == "true" ]]; then
            checkbox_color="${GREEN}"
            status_color="${GREEN}"
            status_text="ENABLED"
        fi

        # Highlight current line checkbox in yellow
        if [[ $i -eq $CURRENT_LINE ]]; then
            checkbox_color="${YELLOW}"
        fi

        echo -ne "${BLUE}│${RESET} "

        # Checkbox
        if [[ "${TAB_ENABLED[$i]}" == "true" ]]; then
            echo -ne "${checkbox_color}[✓]${RESET} "
        else
            echo -ne "${checkbox_color}[ ]${RESET} "
        fi

        # Tab name
        local tab_name="${TAB_NAMES[$i]}"
        [[ -z "$tab_name" ]] && tab_name="${TAB_IDS[$i]}"

        echo -ne "${tab_name}"

        # Padding to align status (account for different status text lengths)
        local name_len=${#tab_name}
        local status_len=${#status_text}
        # Line structure: "│ " (2) + "[✓] " (4) + name + padding + status + "  │" (3) = 66 total
        # So: 66 - 2 - 4 - name_len - status_len - 3 = padding
        local padding=$((57 - name_len - status_len))
        printf "%${padding}s" ""

        # Status
        echo -e "${status_color}${status_text}${RESET}  ${BLUE}│${RESET}"
    done

    # Empty line (64 spaces between borders)
    printf "${BLUE}│${RESET}%64s${BLUE}│${RESET}\n" ""

    # Footer with controls - calculate padding for each line
    local controls_line=" Controls:"
    local controls_padding=$((64 - ${#controls_line}))
    printf "${BLUE}│${RESET}${YELLOW}%s${RESET}%${controls_padding}s${BLUE}│${RESET}\n" "$controls_line" ""

    local space_line="   [Space] Toggle    [↑↓] Navigate    [Ctrl+↑↓] Move"
    local space_padding=$((64 - ${#space_line}))
    printf "${BLUE}│${RESET}${DIM}%s${RESET}%${space_padding}s${BLUE}│${RESET}\n" "$space_line" ""

    local enter_line="   [Enter] Save      [q/Esc] Cancel"
    local enter_padding=$((64 - ${#enter_line}))
    printf "${BLUE}│${RESET}${DIM}%s${RESET}%${enter_padding}s${BLUE}│${RESET}\n" "$enter_line" ""

    echo -e "${BLUE}└────────────────────────────────────────────────────────────────┘${RESET}"
}

# Toggle current tab enable/disable
toggle_tab() {
    if [[ "${TAB_ENABLED[$CURRENT_LINE]}" == "true" ]]; then
        # Check if it's an essential tab
        local always_enabled
        always_enabled=$(get_tab_metadata "${TAB_IDS[$CURRENT_LINE]}" "always_enabled")
        if [[ "$always_enabled" == "true" ]]; then
            return  # Can't disable essential tabs
        fi
        TAB_ENABLED[$CURRENT_LINE]="false"
    else
        TAB_ENABLED[$CURRENT_LINE]="true"
    fi
}

# Move tab up in order
move_tab_up() {
    if [[ $CURRENT_LINE -gt 0 ]]; then
        local idx=$CURRENT_LINE
        local prev=$((idx - 1))

        # Swap all properties
        local tmp_id="${TAB_IDS[$idx]}"
        local tmp_name="${TAB_NAMES[$idx]}"
        local tmp_enabled="${TAB_ENABLED[$idx]}"
        local tmp_desc="${TAB_DESCRIPTIONS[$idx]}"

        TAB_IDS[$idx]="${TAB_IDS[$prev]}"
        TAB_NAMES[$idx]="${TAB_NAMES[$prev]}"
        TAB_ENABLED[$idx]="${TAB_ENABLED[$prev]}"
        TAB_DESCRIPTIONS[$idx]="${TAB_DESCRIPTIONS[$prev]}"

        TAB_IDS[$prev]="$tmp_id"
        TAB_NAMES[$prev]="$tmp_name"
        TAB_ENABLED[$prev]="$tmp_enabled"
        TAB_DESCRIPTIONS[$prev]="$tmp_desc"

        CURRENT_LINE=$((CURRENT_LINE - 1))
    fi
}

# Move tab down in order
move_tab_down() {
    if [[ $CURRENT_LINE -lt $((${#TAB_IDS[@]} - 1)) ]]; then
        local idx=$CURRENT_LINE
        local next=$((idx + 1))

        # Swap all properties
        local tmp_id="${TAB_IDS[$idx]}"
        local tmp_name="${TAB_NAMES[$idx]}"
        local tmp_enabled="${TAB_ENABLED[$idx]}"
        local tmp_desc="${TAB_DESCRIPTIONS[$idx]}"

        TAB_IDS[$idx]="${TAB_IDS[$next]}"
        TAB_NAMES[$idx]="${TAB_NAMES[$next]}"
        TAB_ENABLED[$idx]="${TAB_ENABLED[$next]}"
        TAB_DESCRIPTIONS[$idx]="${TAB_DESCRIPTIONS[$next]}"

        TAB_IDS[$next]="$tmp_id"
        TAB_NAMES[$next]="$tmp_name"
        TAB_ENABLED[$next]="$tmp_enabled"
        TAB_DESCRIPTIONS[$next]="$tmp_desc"

        CURRENT_LINE=$((CURRENT_LINE + 1))
    fi
}

# Read keyboard input
read_key() {
    local key
    IFS= read -rsn1 key

    case "$key" in
        $'\x1b')  # Escape sequence
            IFS= read -rsn2 -t 0.01 key2 || key2=""
            case "$key2" in
                '[A') echo "up" ;;
                '[B') echo "down" ;;
                '[1')
                    # Might be Ctrl+arrow
                    IFS= read -rsn3 -t 0.01 key3 || key3=""
                    case "$key3" in
                        ';5A') echo "ctrl_up" ;;
                        ';5B') echo "ctrl_down" ;;
                        *) echo "unknown" ;;
                    esac
                    ;;
                '') echo "escape" ;;
                *) echo "unknown" ;;
            esac
            ;;
        ' ') echo "space" ;;
        '') echo "enter" ;;
        'q'|'Q') echo "quit" ;;
        *) echo "unknown" ;;
    esac
}

# Save configuration and generate layout
save_and_exit() {
    echo -ne "${CURSOR_SHOW}"

    # Create temporary config file with enabled tabs in order
    local config_file
    config_file=$(mktemp)

    for i in "${!TAB_IDS[@]}"; do
        if [[ "${TAB_ENABLED[$i]}" == "true" ]]; then
            echo "${TAB_IDS[$i]}" >> "$config_file"
        fi
    done

    # Generate and save layout
    local layout_content
    layout_content=$(generate_layout "$config_file")
    save_layout "$PROJECT_DIR" "$layout_content"

    rm -f "$config_file"

    echo -e "${GREEN}✓ Layout saved to $PROJECT_DIR/.worktrees/.zellij-layout.kdl${RESET}"
}

# Cleanup on exit
cleanup() {
    echo -ne "${CURSOR_SHOW}"
    echo -ne "${RESET}"
}

# Main TUI loop
main() {
    PROJECT_DIR="${1:?Project directory required}"

    # Setup cleanup trap
    trap cleanup EXIT

    # Initialize configuration
    init_tab_config "$PROJECT_DIR"

    # Main loop
    while true; do
        draw_screen

        local action
        action=$(read_key)

        case "$action" in
            up)
                if [[ $CURRENT_LINE -gt 0 ]]; then
                    CURRENT_LINE=$((CURRENT_LINE - 1))
                fi
                ;;
            down)
                if [[ $CURRENT_LINE -lt $((${#TAB_IDS[@]} - 1)) ]]; then
                    CURRENT_LINE=$((CURRENT_LINE + 1))
                fi
                ;;
            space)
                toggle_tab
                ;;
            ctrl_up)
                move_tab_up
                ;;
            ctrl_down)
                move_tab_down
                ;;
            enter)
                save_and_exit
                break
                ;;
            escape|quit)
                echo -ne "${CURSOR_SHOW}"
                echo -e "${YELLOW}Configuration cancelled.${RESET}"
                exit 0
                ;;
        esac
    done
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
