# Claude Code CLI Integration for cookinn.notch

This directory contains hook scripts that enable Claude Code CLI to display activity in the MacBook notch via cookinn.notch.

## How It Works

```
┌──────────────────┐     Hook sends JSON      ┌─────────────────┐
│  Claude Code CLI │ ──────────────────────►  │  cookinn.notch   │
│                  │   via HTTP POST          │  (HTTP server)  │
│  PreToolUse      │   localhost:27182        │                 │
│  PostToolUse     │                          │  Displays in    │
│  SessionStart    │                          │  MacBook notch  │
│  SessionEnd      │                          │                 │
└──────────────────┘                          └─────────────────┘
```

## Quick Start

1. **Make sure cookinn.notch is running**
   The app starts an HTTP server on port 27182 to receive hook events.

2. **Install the hooks**
   ```bash
   cd /path/to/cookinn.notch/hooks
   ./install-hooks.sh
   ```

3. **Or manually configure**
   Add to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         { "type": "command", "command": "/path/to/hooks/pre-tool-use.sh" }
       ],
       "PostToolUse": [
         { "type": "command", "command": "/path/to/hooks/post-tool-use.sh" }
       ],
       "SessionStart": [
         { "type": "command", "command": "/path/to/hooks/session-start.sh" }
       ],
       "SessionEnd": [
         { "type": "command", "command": "/path/to/hooks/session-end.sh" }
       ]
     }
   }
   ```

4. **Restart Claude Code CLI**
   The hooks will now send events to cookinn.notch!

## Hook Scripts

| Script | Event | Description |
|--------|-------|-------------|
| `pre-tool-use.sh` | PreToolUse | Sent before each tool call (Read, Write, Bash, etc.) |
| `post-tool-use.sh` | PostToolUse | Sent after each tool completes |
| `session-start.sh` | SessionStart | Sent when Claude Code session begins |
| `session-end.sh` | SessionEnd | Sent when Claude Code session ends |
| `notch-hook.sh` | All | Generic hook that handles all event types |

## What You'll See

When Claude Code is active, the notch will display:
- **Grid Loader**: Animated 3x3 grid showing activity
- **Tool Name**: Current tool being executed (Reading, Writing, Running, etc.)
- **Tool Colors**:
  - 🔴 Red: Bash commands
  - 🔵 Cyan: Reading files
  - 🟢 Green: Writing files
  - 🟡 Yellow: Editing files
  - 🟣 Purple: Searching (Glob/Grep)
  - 🔵 Blue: Tasks
  - 💜 Indigo: Web fetching

## Troubleshooting

### Notch not showing activity?

1. Check if cookinn.notch is running (should appear in menu bar)
2. Verify the HTTP server is listening:
   ```bash
   curl http://localhost:27182/health
   # Should return: {"healthy":true,"provider":"claude-code"}
   ```
3. Check hook scripts are executable:
   ```bash
   chmod +x /path/to/hooks/*.sh
   ```
4. Verify hooks are configured in Claude Code:
   ```bash
   cat ~/.claude/settings.json
   ```

### Hooks not firing?

1. Make sure you're using Claude Code CLI (not VS Code extension)
2. Check Claude Code version supports hooks (v1.0+)
3. Try the test command:
   ```bash
   echo '{"session_id":"test","tool_name":"bash"}' | ./pre-tool-use.sh
   ```

### Permission issues?

The hooks run as background processes to not block Claude. If you see permission errors:
```bash
chmod +x /path/to/hooks/*.sh
```

## Requirements

- macOS with MacBook notch (M1/M2/M3 Pro/Max)
- cookinn.notch app running
- Claude Code CLI with hooks support
- `curl` (pre-installed on macOS)
- `jq` (optional, for better JSON parsing): `brew install jq`

## Provider Selection

cookinn.notch supports both OpenCode and Claude Code CLI simultaneously. The app will show activity from whichever tool is currently running. A small badge (OC/CC) indicates the provider when permissions are requested.
