# Hooks Configuration

cookinn.notch uses Claude Code hooks to receive activity events. The app auto-installs these on first launch, but you can also configure them manually.

## Automatic Setup

Hooks are automatically installed when you first launch the app. If you need to reinstall, use the menu bar icon → "Setup..."

## Manual Setup

Add the following to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "Stop": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "SubagentStop": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "Notification": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "SessionStart": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "TeammateIdle": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "TaskCompleted": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "TaskCreated": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "CwdChanged": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "PreCompact": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "PostCompact": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "PostToolUseFailure": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }],
    "StopFailure": [{ "hooks": [{ "type": "http", "url": "http://localhost:27182/hook" }] }]
  }
}
```

## Hook Events

| Event | Description |
|-------|-------------|
| `PreToolUse` | Tool is about to be executed |
| `PostToolUse` | Tool has finished executing |
| `Stop` | Claude stopped responding |
| `SubagentStop` | A subagent task completed |
| `Notification` | Claude sent a notification |
| `SessionStart` | New Claude Code session started |
| `SessionEnd` | Session ended |
| `UserPromptSubmit` | User submitted a prompt |
| `TeammateIdle` | Agent team teammate about to idle |
| `TaskCompleted` | Task marked as completed |
| `TaskCreated` | Task is being created |
| `CwdChanged` | Working directory changed |
| `PreCompact` | Context window compaction starting |
| `PostCompact` | Context window compaction finished |
| `PostToolUseFailure` | Tool call failed |
| `StopFailure` | Turn ended due to error |

## Files

After installation, these files exist in `~/.config/cookinn-notch/`:

```
~/.config/cookinn-notch/
├── send-to-notch.sh     # Pin current session
└── remove-from-notch.sh # Unpin all sessions
```
