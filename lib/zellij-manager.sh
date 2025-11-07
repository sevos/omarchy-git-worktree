#!/bin/bash
# Zellij Layout Manager
# Functions for detecting available tabs and generating layouts

set -euo pipefail

# Detect available tabs for a project
# Usage: detect_available_tabs <project_dir>
# Returns: newline-separated list of tab identifiers
detect_available_tabs() {
    local project_dir="${1:?Project directory required}"
    local available_tabs=()

    # Always include essential tabs
    available_tabs+=("editor")
    available_tabs+=("terminal")

    # Run module detection scripts
    for module_detect in "$MODULES_DIR"/*/detect; do
        if [[ -x "$module_detect" ]]; then
            # Run detection script with project directory
            while IFS= read -r tab; do
                [[ -n "$tab" ]] && available_tabs+=("$tab")
            done < <("$module_detect" "$project_dir" 2>/dev/null || true)
        fi
    done

    # Return unique tabs
    printf '%s\n' "${available_tabs[@]}" | sort -u
}

# Get tab metadata from tab template file
# Usage: get_tab_metadata <tab_id> <field>
# Returns: metadata value
get_tab_metadata() {
    local tab_id="$1"
    local field="$2"
    local tab_file

    # Find tab file by matching tab_id in detector metadata or filename
    for tab_file in "$SHARE_DIR"/zellij-tabs/*.kdl; do
        if [[ -f "$tab_file" ]]; then
            local detector
            detector=$(grep "^// META: detector=" "$tab_file" 2>/dev/null | cut -d'=' -f2 || echo "")
            local filename
            filename=$(basename "$tab_file" .kdl)

            # Match by detector name or by filename pattern
            if [[ "$detector" == "$tab_id" ]] || [[ "$filename" =~ -${tab_id}$ ]] || [[ "$filename" == "00-${tab_id}" ]] || [[ "$filename" == "01-${tab_id}" ]]; then
                # Extract metadata field
                grep "^// META: ${field}=" "$tab_file" 2>/dev/null | cut -d'=' -f2- || echo ""
                return 0
            fi
        fi
    done

    echo ""
}

# Get tab file path by tab ID
# Usage: get_tab_file <tab_id>
# Returns: path to tab file
get_tab_file() {
    local tab_id="$1"
    local tab_file

    # Find tab file by matching tab_id in detector metadata or filename
    for tab_file in "$SHARE_DIR"/zellij-tabs/*.kdl; do
        if [[ -f "$tab_file" ]]; then
            local detector
            detector=$(grep "^// META: detector=" "$tab_file" 2>/dev/null | cut -d'=' -f2 || echo "")
            local filename
            filename=$(basename "$tab_file" .kdl)

            # Match by detector name or by filename pattern
            if [[ "$detector" == "$tab_id" ]] || [[ "$filename" =~ -${tab_id}$ ]] || [[ "$filename" == "00-${tab_id}" ]] || [[ "$filename" == "01-${tab_id}" ]]; then
                echo "$tab_file"
                return 0
            fi
        fi
    done

    echo ""
}

# Generate Zellij layout from tab configuration
# Usage: generate_layout <tab_config_file>
# tab_config_file format: one tab ID per line, in order
# Returns: complete KDL layout content
generate_layout() {
    local tab_config_file="${1:?Tab configuration file required}"
    local layout_content

    # Start layout structure
    layout_content="layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location=\"zellij:tab-bar\"
        }
        children
        pane size=2 borderless=true {
            plugin location=\"zellij:status-bar\"
        }
    }
    "

    # Add each configured tab
    local first_tab=true
    while IFS= read -r tab_id; do
        [[ -z "$tab_id" ]] && continue
        [[ "$tab_id" =~ ^# ]] && continue  # Skip comments

        local tab_file
        tab_file=$(get_tab_file "$tab_id")

        if [[ -n "$tab_file" && -f "$tab_file" ]]; then
            # Add tab content (skip META comments)
            local tab_content
            tab_content=$(grep -v "^// META:" "$tab_file" || true)

            # Add focus to first tab if it doesn't have it
            if [[ "$first_tab" == "true" ]] && ! echo "$tab_content" | grep -q "focus=true"; then
                tab_content=$(echo "$tab_content" | sed 's/tab name="\([^"]*\)"/tab name="\1" focus=true/')
            fi

            layout_content+="
    $tab_content
    "
            first_tab=false
        fi
    done < "$tab_config_file"

    # Close layout structure
    layout_content+="
}
"

    echo "$layout_content"
}

# Save layout to project
# Usage: save_layout <project_dir> <layout_content>
save_layout() {
    local project_dir="${1:?Project directory required}"
    local layout_content="${2:?Layout content required}"
    local layout_file="$project_dir/.worktrees/.zellij-layout.kdl"

    # Create .worktrees directory if it doesn't exist
    mkdir -p "$project_dir/.worktrees"

    # Write layout file
    echo "$layout_content" > "$layout_file"

    echo "$layout_file"
}

# Load existing tab configuration from layout file
# Usage: load_tab_config <project_dir>
# Returns: newline-separated list of tab IDs in order
load_tab_config() {
    local project_dir="${1:?Project directory required}"
    local layout_file="$project_dir/.worktrees/.zellij-layout.kdl"

    if [[ ! -f "$layout_file" ]]; then
        echo ""
        return 1
    fi

    # Extract tab names and map back to tab IDs
    # This is a simple heuristic - look for 'tab name="..."' lines
    grep 'tab name=' "$layout_file" | sed 's/.*tab name="\([^"]*\)".*/\1/' | while read -r tab_name; do
        # Map tab name back to tab ID
        case "$tab_name" in
            "Editor") echo "editor" ;;
            "Terminal") echo "terminal" ;;
            "Claude") echo "claude" ;;
            "Web server") echo "rails-server" ;;
            "Rails Server") echo "rails-server" ;;
            "Rails Console") echo "rails-console" ;;
            *) echo "$tab_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' ;;
        esac
    done
}

# Get project-specific layout file path, or return global default
# Usage: get_layout_file <project_dir>
# Returns: path to layout file to use
get_layout_file() {
    local project_dir="${1:?Project directory required}"
    local project_layout="$project_dir/.worktrees/.zellij-layout.kdl"

    if [[ -f "$project_layout" ]]; then
        echo "$project_layout"
    else
        echo "$ZELLIJ_LAYOUT_FILE"
    fi
}
