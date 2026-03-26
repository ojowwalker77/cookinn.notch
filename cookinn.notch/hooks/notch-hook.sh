#!/bin/bash
# DEPRECATED: cookinn.notch now uses HTTP hooks for direct delivery.
# This script is no longer used. New installs use:
#   {"type": "http", "url": "http://localhost:27182/hook"}
#
# Unified Claude Code hook for cookinn.notch
# Sends ALL hook events to the notch display app

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
# Notification hook fields
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // ""' 2>/dev/null || echo "")

# Agent type (from SessionStart when --agent is used, v2.1.2+)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")

# Model info (v2.1.6+ status line fields, may be in hook payload)
MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // .model // ""' 2>/dev/null || echo "")
MODEL_DISPLAY_NAME=$(echo "$INPUT" | jq -r '.model.display_name // ""' 2>/dev/null || echo "")

# Cost tracking (v2.1.6+ status line fields)
COST_USD=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // ""' 2>/dev/null || echo "")

# Token usage (from Stop events - usually null, we get real data from transcript)
USAGE=$(echo "$INPUT" | jq -c 'if .usage then .usage else null end' 2>/dev/null || echo 'null')

# Claude Code v2.1.6+ provides native context_window fields
# Prefer these over manual transcript parsing
NATIVE_CONTEXT_PERCENT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // ""' 2>/dev/null || echo "")

CONTEXT_PERCENT=""
CONTEXT_TOKENS=""

if [ -n "$NATIVE_CONTEXT_PERCENT" ] && [ "$NATIVE_CONTEXT_PERCENT" != "null" ]; then
    # Use native context_window.used_percentage from Claude Code v2.1.6+
    CONTEXT_PERCENT="$NATIVE_CONTEXT_PERCENT"
else
    # Fallback: Parse from transcript JSONL for older Claude Code versions
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
        # Get last assistant message with usage (JSONL = one JSON per line)
        LAST_USAGE=$(tail -30 "$TRANSCRIPT_PATH" 2>/dev/null | \
            grep '"type":"assistant"' | \
            tail -1 | \
            jq -c '.message.usage // empty' 2>/dev/null || echo "")

        if [ -n "$LAST_USAGE" ] && [ "$LAST_USAGE" != "null" ] && [ "$LAST_USAGE" != "" ]; then
            INPUT_TOKENS=$(echo "$LAST_USAGE" | jq -r '.input_tokens // 0' 2>/dev/null || echo "0")
            CACHE_READ=$(echo "$LAST_USAGE" | jq -r '.cache_read_input_tokens // 0' 2>/dev/null || echo "0")
            CACHE_CREATE=$(echo "$LAST_USAGE" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null || echo "0")

            # Calculate total context tokens
            CONTEXT_TOKENS=$((INPUT_TOKENS + CACHE_READ + CACHE_CREATE))

            # Calculate percentage (assume 200k context, may not be accurate for all models)
            if [ "$CONTEXT_TOKENS" -gt 0 ]; then
                CONTEXT_PERCENT=$(awk "BEGIN {printf \"%.2f\", $CONTEXT_TOKENS / 2000}" 2>/dev/null || echo "")
            fi
        fi
    fi
fi

# Extract project name from cwd
PROJECT_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "")
fi

# Build JSON payload
# Use jq to safely escape string values and build valid JSON
PAYLOAD=$(jq -n \
  --arg event "$EVENT" \
  --arg sessionId "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg projectName "$PROJECT_NAME" \
  --arg permissionMode "$PERMISSION_MODE" \
  --arg toolName "$TOOL_NAME" \
  --arg toolUseId "$TOOL_USE_ID" \
  --argjson toolInput "$TOOL_INPUT" \
  --argjson toolResponse "$TOOL_RESPONSE" \
  --arg source "$SOURCE" \
  --arg reason "$REASON" \
  --arg message "$MESSAGE" \
  --arg notificationType "$NOTIFICATION_TYPE" \
  --arg agentType "$AGENT_TYPE" \
  --arg modelId "$MODEL_ID" \
  --arg modelDisplayName "$MODEL_DISPLAY_NAME" \
  --argjson costUsd "${COST_USD:-null}" \
  --argjson usage "$USAGE" \
  --argjson contextTokens "${CONTEXT_TOKENS:-null}" \
  --argjson contextPercent "${CONTEXT_PERCENT:-null}" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    event: $event,
    sessionId: $sessionId,
    cwd: $cwd,
    projectName: $projectName,
    permissionMode: $permissionMode,
    toolName: $toolName,
    toolUseId: $toolUseId,
    toolInput: $toolInput,
    toolResponse: $toolResponse,
    source: $source,
    reason: $reason,
    message: $message,
    notificationType: $notificationType,
    agentType: $agentType,
    modelId: $modelId,
    modelDisplayName: $modelDisplayName,
    costUsd: $costUsd,
    usage: $usage,
    contextTokens: $contextTokens,
    contextPercent: $contextPercent,
    timestamp: $timestamp
  }' 2>/dev/null)

# Fallback if jq fails (shouldn't happen but safety first)
if [ -z "$PAYLOAD" ]; then
  # Minimal fallback with essential fields - escape quotes in values
  SAFE_CWD=$(echo "$CWD" | sed 's/"/\\"/g')
  SAFE_TOOL=$(echo "$TOOL_NAME" | sed 's/"/\\"/g')
  PAYLOAD="{\"event\":\"$EVENT\",\"sessionId\":\"$SESSION_ID\",\"cwd\":\"$SAFE_CWD\",\"toolName\":\"$SAFE_TOOL\",\"notificationType\":\"$NOTIFICATION_TYPE\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
fi

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
