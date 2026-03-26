#!/bin/bash
# Unpin current session from notch display
# Usage: Run /remove-from-notch in Claude Code

NOTCH_SERVER="http://localhost:27182"

# Get current working directory
CWD=$(pwd)

# Send unpin request with cwd
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"cwd\": \"$CWD\"}" \
    "${NOTCH_SERVER}/unpin" \
    --connect-timeout 2 \
    --max-time 5)

if echo "$RESPONSE" | grep -q '"ok":true'; then
    PROJECT=$(echo "$RESPONSE" | grep -o '"project":"[^"]*"' | cut -d'"' -f4)
    echo "Unpinned from notch: $PROJECT"
else
    echo "Failed to unpin: $RESPONSE"
fi
