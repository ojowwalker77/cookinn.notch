#!/bin/bash
#
# cookinn.notch Uninstall Script
# Removes Claude Code hooks for cookinn.notch
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Paths
CONFIG_DIR="$HOME/.config/cookinn-notch"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_IDENTIFIER="cookinn-notch/notch-hook.sh"

# Parse arguments
FORCE=false
for arg in "$@"; do
    case $arg in
        -f|--force)
            FORCE=true
            shift
            ;;
    esac
done

echo ""
echo -e "${BOLD}${CYAN}cookinn.notch Uninstall${NC}"
echo -e "${CYAN}======================${NC}"
echo ""

# Check what exists
CONFIG_EXISTS=false
HOOKS_EXIST=false

if [[ -d "$CONFIG_DIR" ]]; then
    CONFIG_EXISTS=true
fi

if [[ -f "$SETTINGS_FILE" ]]; then
    if grep -q "$HOOK_IDENTIFIER" "$SETTINGS_FILE" 2>/dev/null; then
        HOOKS_EXIST=true
    fi
fi

# Nothing to do?
if [[ "$CONFIG_EXISTS" == false && "$HOOKS_EXIST" == false ]]; then
    echo -e "${GREEN}[✓]${NC} cookinn.notch is not installed (nothing to remove)"
    echo ""
    exit 0
fi

# Show what will be removed
echo "This will remove:"
if [[ "$CONFIG_EXISTS" == true ]]; then
    echo -e "  - ${YELLOW}~/.config/cookinn-notch/${NC} (hook scripts)"
fi
if [[ "$HOOKS_EXIST" == true ]]; then
    echo -e "  - ${YELLOW}Hook entries from ~/.claude/settings.json${NC}"
fi
echo ""

# Confirmation (unless force flag)
if [[ "$FORCE" == false ]]; then
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        exit 0
    fi
    echo ""
fi

# Remove config directory
if [[ "$CONFIG_EXISTS" == true ]]; then
    rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}[✓]${NC} Removed ~/.config/cookinn-notch/"
fi

# Remove hooks from settings.json
if [[ "$HOOKS_EXIST" == true ]]; then
    # Check if jq is available
    if command -v jq &> /dev/null; then
        # Create a temporary file
        TEMP_FILE=$(mktemp)

        # Use jq to remove hooks containing our identifier
        # This filters out any hook command that contains "cookinn-notch/notch-hook.sh"
        jq '
            if .hooks then
                .hooks |= with_entries(
                    if .value | type == "string" then
                        select(.value | contains("cookinn-notch/notch-hook.sh") | not)
                    elif .value | type == "array" then
                        .value |= map(select(contains("cookinn-notch/notch-hook.sh") | not)) |
                        select(.value | length > 0)
                    else
                        .
                    end
                )
            else
                .
            end
        ' "$SETTINGS_FILE" > "$TEMP_FILE"

        # Replace original file
        mv "$TEMP_FILE" "$SETTINGS_FILE"

        echo -e "${GREEN}[✓]${NC} Removed hooks from settings.json"
    else
        echo -e "${YELLOW}[!]${NC} jq not found - cannot automatically clean settings.json"
        echo -e "    Please manually remove hooks containing '${HOOK_IDENTIFIER}'"
        echo -e "    from: ${SETTINGS_FILE}"
    fi
fi

echo ""
echo -e "${GREEN}Uninstall complete.${NC} You may need to restart Claude Code."
echo ""
