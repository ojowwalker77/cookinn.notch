#!/bin/bash
#
# cookinn.notch Install Script
# Sets up Claude Code hooks for the cookinn.notch app
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Paths
CONFIG_DIR="$HOME/.config/cookinn-notch"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOK_SCRIPT="$CONFIG_DIR/notch-hook.sh"

# Status helpers
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Find the app bundle
find_app_bundle() {
    # Allow override via environment variable
    if [[ -n "$APP_PATH" ]]; then
        if [[ -d "$APP_PATH" ]]; then
            echo "$APP_PATH"
            return 0
        else
            error "APP_PATH specified but not found: $APP_PATH"
            return 1
        fi
    fi

    # Check common locations
    local locations=(
        "/Applications/cookinn.notch.app"
        "$HOME/Applications/cookinn.notch.app"
        "/Applications/Utilities/cookinn.notch.app"
    )

    for loc in "${locations[@]}"; do
        if [[ -d "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    error "Could not find cookinn.notch.app"
    echo "  Checked: ${locations[*]}" >&2
    echo "  Set APP_PATH environment variable to override" >&2
    return 1
}

# Check for jq
check_jq() {
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed"
        echo ""
        echo "Install jq using one of these methods:"
        echo "  brew install jq"
        echo "  sudo port install jq"
        echo ""
        exit 1
    fi
}

# Create config directory
setup_config_dir() {
    if [[ -d "$CONFIG_DIR" ]]; then
        warning "Directory already exists: $CONFIG_DIR"
    else
        mkdir -p "$CONFIG_DIR"
        success "Created $CONFIG_DIR"
    fi
}

# Copy hook scripts
copy_hooks() {
    local app_bundle="$1"
    local hooks_source="$app_bundle/Contents/Resources/hooks"

    if [[ ! -d "$hooks_source" ]]; then
        error "Hooks directory not found: $hooks_source"
        exit 1
    fi

    local copied=0
    local skipped=0

    for script in "$hooks_source"/*.sh; do
        if [[ -f "$script" ]]; then
            local basename=$(basename "$script")
            local dest="$CONFIG_DIR/$basename"

            if [[ -f "$dest" ]] && cmp -s "$script" "$dest"; then
                ((skipped++))
            else
                cp "$script" "$dest"
                ((copied++))
            fi
        fi
    done

    if [[ $copied -gt 0 ]]; then
        success "Copied $copied hook script(s)"
    fi
    if [[ $skipped -gt 0 ]]; then
        warning "Skipped $skipped unchanged script(s)"
    fi
    if [[ $copied -eq 0 && $skipped -eq 0 ]]; then
        error "No .sh files found in $hooks_source"
        exit 1
    fi
}

# Make scripts executable
make_executable() {
    chmod +x "$CONFIG_DIR"/*.sh 2>/dev/null || true
    success "Made scripts executable"
}

# Update Claude settings
update_settings() {
    # Create .claude directory if needed
    if [[ ! -d "$CLAUDE_DIR" ]]; then
        mkdir -p "$CLAUDE_DIR"
    fi

    # Define our hook configuration (no matcher = match all events)
    local our_hook="$HOME/.config/cookinn-notch/notch-hook.sh"
    local hook_entry="{\"hooks\": [{\"type\": \"command\", \"command\": \"$our_hook\"}]}"

    # Hook types we need to register
    local hook_types=(
        "PreToolUse"
        "PostToolUse"
        "Stop"
        "SubagentStop"
        "Notification"
        "SessionStart"
        "SessionEnd"
        "UserPromptSubmit"
    )

    # Start with existing settings or empty object
    local settings="{}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        settings=$(cat "$SETTINGS_FILE")
        # Validate JSON
        if ! echo "$settings" | jq . > /dev/null 2>&1; then
            error "Existing settings.json is not valid JSON"
            exit 1
        fi
    fi

    # Build the hooks object
    local hooks_json=$(echo "$settings" | jq '.hooks // {}')

    for hook_type in "${hook_types[@]}"; do
        # Get existing hooks for this type
        local existing=$(echo "$hooks_json" | jq --arg type "$hook_type" '.[$type] // []')

        # Check if our hook is already registered (handle both new object and legacy string formats)
        local already_exists=$(echo "$existing" | jq --arg hook "$our_hook" '
            any(.[]; .hooks | any(if type == "object" then .command == $hook else . == $hook end))
        ')

        if [[ "$already_exists" == "true" ]]; then
            continue
        fi

        # Add our hook entry
        hooks_json=$(echo "$hooks_json" | jq --arg type "$hook_type" --argjson entry "$hook_entry" '
            .[$type] = (.[$type] // []) + [$entry]
        ')
    done

    # Merge hooks back into settings
    local new_settings=$(echo "$settings" | jq --argjson hooks "$hooks_json" '.hooks = $hooks')

    # Write settings
    echo "$new_settings" | jq . > "$SETTINGS_FILE"
    success "Updated $SETTINGS_FILE"
}

# Main
main() {
    echo ""
    echo "cookinn.notch Setup"
    echo "=================="
    echo ""

    # Preflight checks
    check_jq

    local app_bundle
    app_bundle=$(find_app_bundle) || exit 1

    # Setup steps
    setup_config_dir
    copy_hooks "$app_bundle"
    make_executable
    update_settings

    echo ""
    echo "Setup complete! Restart Claude Code to activate."
    echo ""
}

main "$@"
