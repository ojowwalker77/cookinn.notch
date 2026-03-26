# Slash Commands (Skills)

cookinn.notch installs two slash commands for Claude Code.

## /send-to-notch

Pin the current Claude Code session to the notch display.

```
/send-to-notch
```

This runs `~/.config/cookinn-notch/send-to-notch.sh` which sends a pin request to the app.

## /remove-from-notch

Unpin all sessions from the notch display.

```
/remove-from-notch
```

This runs `~/.config/cookinn-notch/remove-from-notch.sh` which clears all pinned sessions.

## Manual Installation

If commands aren't installed automatically, create these files:

### ~/.claude/commands/send-to-notch.md

```markdown
Pin this Claude Code session to the cookinn.notch display.

Run this command:
\`\`\`bash
~/.config/cookinn-notch/send-to-notch.sh
\`\`\`

Then confirm to the user that the session has been pinned to the notch display.
```

### ~/.claude/commands/remove-from-notch.md

```markdown
Unpin all sessions from the cookinn.notch display.

Run this command:
\`\`\`bash
~/.config/cookinn-notch/remove-from-notch.sh
\`\`\`

Then confirm to the user that the sessions have been unpinned from the notch display.
```

## How It Works

The commands communicate with cookinn.notch via HTTP on `localhost:27182`:

- **Pin**: `POST /pin` with session info from environment variables
- **Unpin**: `POST /unpin` to clear all pinned sessions

The app maintains a list of pinned project paths and only displays activity from those sessions.
