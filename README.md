# cookinn.notch

A minimal companion for [Claude Code](https://claude.ai/code) on macOS. Shows what Claude is doing. Nothing more, nothing less.

https://github.com/user-attachments/assets/74e9dfa9-52a3-435a-98ff-15dbf05fc3d7

## Installation

### Homebrew

```bash
brew tap ojowwalker77/cookinn-notch
brew install --cask cookinn-notch
```

### Update

The app checks for updates automatically and notifies you in the menu bar. Click to update via Homebrew directly from the app.

Manual update:
```bash
brew update && brew upgrade cookinn-notch
```

### Manual

Download the latest `.dmg` from [Releases](https://github.com/ojowwalker77/cookinn.notch/releases).

## Usage

Sessions automatically appear in notch when started. No setup needed.

### Re-pin a session (after removal)

```
/send-to-notch
```

### Remove from notch

```
/remove-from-notch
```

## What it shows

- Current tool (Read, Edit, Bash, etc.)
- Project name
- Context window usage
- Activity patterns
- **Alert mode**: Pulses red when Claude needs your permission/input, with optional sound alerts

> Fun fact: The alert sound was designed and crafted by hand by the author (@ojowwalker77).

## Documentation

- [Hooks Configuration](docs/hooks.md) - How Claude Code hooks work
- [Slash Commands](docs/skills.md) - `/send-to-notch` and `/remove-from-notch`

## Requirements

- macOS 15.0 (Sequoia) or later
- Claude Code CLI

## License

MIT
