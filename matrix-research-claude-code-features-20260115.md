# Claude Code Features Research for cookinn.notch

**Research Date:** January 15, 2026
**Depth:** Standard
**Query:** New Claude Code features (v2.1.4-v2.1.7) useful for macOS notch display app

---

## Executive Summary

Claude Code v2.1.4-v2.1.7 introduced several features highly relevant to cookinn.notch:

1. **Native context window percentage fields** - No more manual calculation
2. **Enhanced notification hooks** - Permission prompts, idle detection
3. **Background task improvements** - Inline response display, better notifications
4. **New status line variables** - Rich session data available

---

## 1. Status Line Fields (HIGH VALUE)

### New in v2.1.6
```json
{
  "context_window": {
    "used_percentage": 13.5,
    "remaining_percentage": 86.5,
    "context_window_size": 200000,
    "total_input_tokens": 26000,
    "total_output_tokens": 1500,
    "current_usage": {
      "input_tokens": 1200,
      "cache_creation_input_tokens": 500,
      "cache_read_input_tokens": 24300
    }
  },
  "model": {
    "id": "claude-opus-4-5-20251101",
    "display_name": "Opus 4.5"
  },
  "cost": {
    "total_cost_usd": 0.15,
    "total_duration_ms": 45000,
    "total_lines_added": 150,
    "total_lines_removed": 23
  },
  "workspace": {
    "current_dir": "/path/to/project",
    "project_dir": "/path/to/project"
  },
  "session_id": "abc123",
  "version": "2.1.7"
}
```

### Implementation Opportunity
The hook script currently parses transcript JSONL manually. These native fields are **more accurate** because they account for:
- Reserved space for max output tokens
- Effective context window (not just raw 200k)
- Proper cache token handling

**Status:** ✅ Already implemented in hook script (with fallback)

---

## 2. Notification Hook Types (MEDIUM VALUE)

### Available Matchers for Notification Hooks
| Type | Description | cookinn.notch Use |
|------|-------------|-------------------|
| `permission_prompt` | Permission requests | ✅ Already used for "Waiting" state |
| `idle_prompt` | 60+ seconds idle, waiting for input | ⚠️ Could show "Idle - Waiting" |
| `auth_success` | Authentication success | Low priority |
| `elicitation_dialog` | MCP tool needs input | Could show "Input Needed" |

### Current Implementation Gap
cookinn.notch only handles `permission_prompt`. Adding `idle_prompt` would improve UX by showing when Claude is waiting for user input vs truly idle.

---

## 3. Background Task Features (MEDIUM VALUE)

### v2.1.7 Changes
- **Inline response display in task notifications** - Agent's final response shown directly
- **3-line cap with overflow summary** - Multiple tasks don't spam notifications

### v2.1.4 Changes
- `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` env var added

### Potential Enhancement
If users run background tasks, cookinn.notch could show a badge or indicator. Currently no hook for background task start/completion exists in the public API.

---

## 4. Hook Improvements (LOW-MEDIUM VALUE)

### v2.1.6 Changes
- Hook success message no longer shows trailing colon when hook has no output
- Hook progress messages now update during PostToolUse execution

### v2.1.3 Changes
- Tool hook timeout increased: 60s → 10 minutes
- Fixed trust dialog issues with hooks

### v2.1.2 Changes
- `agent_type` added to SessionStart hook input (when `--agent` specified)

### Implementation Opportunity
cookinn.notch could show different indicators for different agent types (Plan, Explore, etc).

---

## 5. Context Window Fixes (HIGH VALUE)

### v2.1.7 Fix
> Fixed context window blocking limit being calculated using the full context window instead of the effective context window (which reserves space for max output tokens)

This means the native `used_percentage` field is **more accurate** than manual calculation because it accounts for reserved output space.

---

## 6. New Settings (LOW VALUE)

### v2.1.7
- `showTurnDuration` - Hide "Cooked for 1m 6s" messages

### v2.1.6
- Search in `/config` command
- Date filtering in `/stats` (7d/30d/All)

---

## Recommendations for cookinn.notch

### High Priority
1. ✅ **Use native context_window.used_percentage** - Already implemented
2. ⬜ **Add idle_prompt notification handling** - Show "Waiting for Input" state

### Medium Priority
3. ⬜ **Show agent_type in UI** - When using Plan/Explore agents
4. ⬜ **Track total_cost_usd** - Could show session cost in expanded view

### Low Priority
5. ⬜ **Background task indicator** - If API exposes this in future
6. ⬜ **Model display_name** - Show "Opus 4.5" instead of full model ID

---

## Sources

- [Claude Code Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [Claude Code Releases](https://github.com/anthropics/claude-code/releases)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Status Line Docs](https://code.claude.com/docs/en/statusline)
- [shanraisshan/claude-code-status-line](https://github.com/shanraisshan/claude-code-status-line)
- [ClaudeLog Changelog](https://claudelog.com/claude-code-changelog/)
- [Releasebot Updates](https://releasebot.io/updates/anthropic/claude-code)
