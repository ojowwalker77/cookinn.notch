# Hooks Configuration

cookinn.notch uses Claude Code hooks to receive activity events. The app auto-installs these on first launch, but you can also configure them manually.

## Automatic Setup

Hooks are automatically installed when you first launch the app. If you need to reinstall, use the menu bar icon → "Setup..."

## Manual Setup

Add the following to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.config/cookinn-notch/notch-hook.sh"
          }
        ]
      }
    ]
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

## Files

After installation, these files exist in `~/.config/cookinn-notch/`:

```
~/.config/cookinn-notch/
├── notch-hook.sh       # Main hook script (receives events)
├── send-to-notch.sh    # Pin current session
└── remove-from-notch.sh # Unpin all sessions
```
