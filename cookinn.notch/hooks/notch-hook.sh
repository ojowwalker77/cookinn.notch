#!/bin/bash
# Unified Claude Code hook for cookinn.notch
# Sends ALL hook events to the notch display app
#
# Install: Run ./install-hooks.sh or add to ~/.claude/settings.json

NOTCH_SERVER="http://localhost:27182"

# Read stdin (Claude Code sends JSON here)
INPUT=$(cat 2>/dev/null || echo '{}')

# Only proceed if jq is available
if ! command -v jq &> /dev/null; then
    exit 0
fi

# Parse fields from input (all errors suppressed)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // ""' 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')
TOOL_RESPONSE=$(echo "$INPUT" | jq -c '.tool_response // {}' 2>/dev/null || echo '{}')
PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"' 2>/dev/null || echo "default")
SOURCE=$(echo "$INPUT" | jq -r '.source // ""' 2>/dev/null || echo "")
REASON=$(echo "$INPUT" | jq -r '.reason // ""' 2>/dev/null || echo "")
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null || echo "")

# Token usage (from Stop events - usually null, we get real data from transcript)
USAGE=$(echo "$INPUT" | jq -c 'if .usage then .usage else null end' 2>/dev/null || echo 'null')

# Extract transcript path for token usage
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# Parse token usage from transcript JSONL (more reliable than hook usage field)
CONTEXT_PERCENT=""
CONTEXT_TOKENS=""

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get last assistant message with usage (JSONL = one JSON per line)
    # Look for lines with "type":"assistant" that have usage data
    LAST_USAGE=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
        grep '"type":"assistant"' | \
        tail -1 | \
        jq -c '.message.usage // empty' 2>/dev/null || echo "")

    if [ -n "$LAST_USAGE" ] && [ "$LAST_USAGE" != "null" ] && [ "$LAST_USAGE" != "" ]; then
        INPUT_TOKENS=$(echo "$LAST_USAGE" | jq -r '.input_tokens // 0' 2>/dev/null || echo "0")
        CACHE_READ=$(echo "$LAST_USAGE" | jq -r '.cache_read_input_tokens // 0' 2>/dev/null || echo "0")
        CACHE_CREATE=$(echo "$LAST_USAGE" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null || echo "0")

        # Calculate total context tokens (all count toward context window)
        CONTEXT_TOKENS=$((INPUT_TOKENS + CACHE_READ + CACHE_CREATE))

        # Calculate percentage of 200k context window
        if [ "$CONTEXT_TOKENS" -gt 0 ]; then
            CONTEXT_PERCENT=$(awk "BEGIN {printf \"%.2f\", $CONTEXT_TOKENS / 2000}" 2>/dev/null || echo "")
        fi
    fi
fi

# Extract project name from cwd
PROJECT_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "")
fi

# Build JSON payload
PAYLOAD=$(cat <<EOF
{
  "event": "$EVENT",
  "sessionId": "$SESSION_ID",
  "cwd": "$CWD",
  "projectName": "$PROJECT_NAME",
  "permissionMode": "$PERMISSION_MODE",
  "toolName": "$TOOL_NAME",
  "toolUseId": "$TOOL_USE_ID",
  "toolInput": $TOOL_INPUT,
  "toolResponse": $TOOL_RESPONSE,
  "source": "$SOURCE",
  "reason": "$REASON",
  "message": "$MESSAGE",
  "usage": $USAGE,
  "contextTokens": ${CONTEXT_TOKENS:-null},
  "contextPercent": ${CONTEXT_PERCENT:-null},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

# Send to notch server (fire and forget, all output suppressed)
(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${NOTCH_SERVER}/hook" \
    --connect-timeout 1 \
    --max-time 2 \
    >/dev/null 2>&1 || true) &

# Always exit 0 - never block Claude Code
exit 0
