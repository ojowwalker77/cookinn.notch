#!/bin/bash
#
# Install cookinn.notch hooks for Claude Code CLI
#
# This script configures Claude Code to send ALL events to cookinn.notch
# Run this once to set up the integration
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/notch-hook.sh"
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_DIR/settings.json"

echo "Installing cookinn.notch hooks for Claude Code..."
echo ""

# Make hook script executable
chmod +x "$HOOK_SCRIPT"

echo "Hook script location:"
echo "  $HOOK_SCRIPT"
echo ""

# Check if Claude settings directory exists
if [ ! -d "$CLAUDE_SETTINGS_DIR" ]; then
    echo "Creating Claude settings directory..."
    mkdir -p "$CLAUDE_SETTINGS_DIR"
fi

# Generate hooks configuration (all events use the same unified hook)
HOOKS_CONFIG=$(cat <<EOF
{
  "hooks": {
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }],
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "$HOOK_SCRIPT" }] }]
  }
}
EOF
)

echo "Hooks configuration:"
echo "--------------------"
echo "$HOOKS_CONFIG"
echo ""

# Check if jq is available for automatic installation
if command -v jq &> /dev/null; then
    echo ""
    read -p "Would you like to automatically add hooks to ~/.claude/settings.json? (y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
            # Backup existing settings
            cp "$CLAUDE_SETTINGS_FILE" "$CLAUDE_SETTINGS_FILE.backup"
            echo "Backed up existing settings to $CLAUDE_SETTINGS_FILE.backup"

            # Merge hooks into existing settings
            MERGED=$(jq --argjson hooks "$HOOKS_CONFIG" '. * $hooks' "$CLAUDE_SETTINGS_FILE")
            echo "$MERGED" > "$CLAUDE_SETTINGS_FILE"
        else
            # Create new settings file
            echo "$HOOKS_CONFIG" > "$CLAUDE_SETTINGS_FILE"
        fi

        echo ""
        echo "Hooks installed successfully!"
        echo "Restart Claude Code to apply changes."
    fi
else
    echo ""
    echo "Note: Install 'jq' for automatic configuration: brew install jq"
    echo "Otherwise, manually add the hooks config to ~/.claude/settings.json"
fi

echo ""
echo "Make sure cookinn.notch is running before using Claude Code."
echo "The notch app listens on http://localhost:27182 for hook events."
echo ""
echo "Done!"
