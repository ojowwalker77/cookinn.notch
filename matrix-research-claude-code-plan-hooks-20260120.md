# Research: Claude Code Plan Mode Hooks

**Date:** 2025-01-20
**Query:** How to detect when Claude finishes a plan and access the plan content

## Summary

**Yes, you can detect plan completion and access plan content** using the `PermissionRequest` hook with `ExitPlanMode` matcher.

## Key Findings

### 1. Hook Event: `PermissionRequest`

Claude Code fires `PermissionRequest` when `ExitPlanMode` tool is called (plan complete). This is the hook to intercept.

```json
{
  "PermissionRequest": [
    {
      "matcher": "ExitPlanMode",
      "hooks": [
        {
          "type": "command",
          "command": "your-handler-script.sh",
          "timeout": 1800
        }
      ]
    }
  ]
}
```

### 2. Hook Input Data

The hook receives JSON via stdin containing:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "plan",
  "hook_event_name": "PermissionRequest",
  "tool_name": "ExitPlanMode",
  "tool_input": {
    "plan": "## Implementation Plan\n\n1. First step...\n2. Second step...",
    "allowedPrompts": [...]
  }
}
```

**Key field:** `tool_input.plan` contains the full plan content!

### 3. Hook Output (Decision)

Return JSON to control behavior:

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask"
  },
  "systemMessage": "Feedback for Claude"
}
```

- `allow` - Approve the plan, exit plan mode
- `deny` - Reject the plan, Claude continues planning
- `ask` - Show permission dialog to user

### 4. All Available Hook Events

| Event | Description |
|-------|-------------|
| `PreToolUse` | Before tool execution |
| `PostToolUse` | After tool completes |
| `PermissionRequest` | Permission dialog shown (use for ExitPlanMode!) |
| `Notification` | Claude sends notification |
| `UserPromptSubmit` | User submits prompt |
| `Stop` | Agent finished responding |
| `SubagentStop` | Subagent finished |
| `PreCompact` | Before context compaction |
| `SessionStart` | Session begins |
| `SessionEnd` | Session ends |

### 5. Reference Implementation: Plannotator

[Plannotator](https://github.com/backnotprop/plannotator) by @backnotprop demonstrates this pattern:

```typescript
// apps/hook/server/index.ts
const eventJson = await Bun.stdin.text();
const event = JSON.parse(eventJson);
const planContent = event.tool_input?.plan || "";
const permissionMode = event.permission_mode || "default";
```

### 6. Known Issues

- **Bug #15755 (FIXED)**: Previously, returning `allow` didn't exit plan mode properly
- Ensure Claude Code is up to date for proper behavior

## Implementation for cookinn.notch

To display plan completion in the notch widget:

1. **Add hook config** for `PermissionRequest` → `ExitPlanMode`
2. **Extract plan content** from `tool_input.plan`
3. **Send to notch server** with new event type (e.g., `"PlanComplete"`)
4. **Display in UI** - could show plan summary, approval buttons, etc.

### Example Hook Script

```bash
#!/bin/bash
input=$(cat)
event_name=$(echo "$input" | jq -r '.hook_event_name')
tool_name=$(echo "$input" | jq -r '.tool_name')

if [[ "$event_name" == "PermissionRequest" && "$tool_name" == "ExitPlanMode" ]]; then
  plan_content=$(echo "$input" | jq -r '.tool_input.plan // ""')
  session_id=$(echo "$input" | jq -r '.session_id')
  cwd=$(echo "$input" | jq -r '.cwd')

  # Send to notch server
  curl -s -X POST http://localhost:27182/hook \
    -H "Content-Type: application/json" \
    -d "{
      \"event\": \"PlanComplete\",
      \"sessionId\": \"$session_id\",
      \"cwd\": \"$cwd\",
      \"planContent\": $(echo "$plan_content" | jq -Rs .)
    }" &
fi

# Let the permission dialog proceed normally
exit 0
```

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Plannotator GitHub](https://github.com/backnotprop/plannotator)
- [Bug #15755 - ExitPlanMode Allow Issue](https://github.com/anthropics/claude-code/issues/15755)
- [Context7 - Claude Code Docs](https://context7.com/anthropics/claude-code)
