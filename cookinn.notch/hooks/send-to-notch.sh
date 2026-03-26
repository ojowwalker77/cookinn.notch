#!/bin/bash
# Pin current Claude Code session to notch display
# Usage: Run /send-to-notch in Claude Code

NOTCH_SERVER="http://localhost:27182"

# Get current working directory
CWD=$(pwd)

# Send pin request with cwd
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"cwd\": \"$CWD\"}" \
    "${NOTCH_SERVER}/pin" \
    --connect-timeout 2 \
    --max-time 5)

if echo "$RESPONSE" | grep -q '"ok":true'; then
    PROJECT=$(echo "$RESPONSE" | grep -o '"project":"[^"]*"' | cut -d'"' -f4)
    echo "Pinned to notch: $PROJECT"
else
    echo "Failed to pin: $RESPONSE"
fi
