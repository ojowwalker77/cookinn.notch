# Changelog

All notable changes to cookinn.notch will be documented in this file.

## [1.10] - 2025-01-20

### Fixed
- **Early idle timeout**: Sessions in "thinking" state no longer timeout after 60 seconds. Thinking state now correctly respects `noTimeout: true` config, allowing Claude to think indefinitely without the pill going idle.

## [1.9] - 2025-01-15

### Added
- **Claude Code v2.1.6+ support**: Native status line fields integration
  - Agent type badge: Shows "Plan", "Explore" etc. when using `--agent` flag
  - Cost display: Session cost shown in green (<1¢, 5¢, $1.23 format)
  - Model info tracking (modelId, modelDisplayName)
- **Idle prompt indicator**: Yellow pulsing indicator when Claude is waiting for user input (vs red for permission prompts)
- Native `context_window.used_percentage` support (falls back to transcript parsing for older versions)

### Changed
- Hook script now uses `jq` for JSON construction (safer escaping, prevents broken payloads from special characters in tool outputs)

## [1.8] - 2025-01-13

### Added
- **Ralph Loop Detection**: Monitor autonomous AI development loops running in the background
  - OpenCode Ralph loops shown with purple indicator and iteration progress (e.g., `🔄 10/200`)
  - Claude Code Ralph loops shown with orange indicator and loop count (e.g., `🔄 5`)
  - Displays "Ralphing" status verb when loops are active
  - Auto-pins projects when loops are detected
  - Auto-dismisses when loops complete (90-second staleness detection)
- **Show Ralph Loops** setting in menu (enabled by default)

### Architecture
- New `RalphLoopManager.swift` for centralized Ralph detection
- Supports both OpenCode Ralph (`.opencode/ralph-loop.state.json`) and Claude Code Ralph (`status.json`)

## [1.7] - 2025-01-12

### Performance
- Optimized animation frame rates for reduced CPU usage and improved battery efficiency
- Fine-tuned timer frequencies across UI components for better resource management
- Reduced mouse tracking polling rate from 60fps to 10fps and skip tracking entirely when windows are hidden
- Adjusted status update intervals for optimal balance between responsiveness and efficiency

## [1.6] - 2025-01-10

### Added
- **Update checker**: Menu shows version status and checks GitHub releases with one-click updates (runs homebrew command)
- Falls back to GitHub releases page if Homebrew not installed

### Fixed
- **Stale sessions**: Old/orphaned sessions are automatically removed after 30 minutes of inactivity
- **Duplicate pills**: Sessions in the same directory now show as a single pill (most active one wins)
- **Lost state after alert**: Approving a permission request now transitions smoothly (no brief "Idle" flicker)
- **Stuck "Thinking" on interrupt**: Interrupting Claude mid-thought now correctly goes to Idle after timeout

## [1.5] - 2025-01-09

### Added
- **Alert mode**: Pill pulses red and shows "Waiting" when Claude needs user permission/input
- **Alert sounds**: Custom notification sound plays when waiting for input, with escalating reminders at 10s, 30s, and 60s
- Alert sounds toggle in menu bar (enabled by default)
- Graceful delay before entering alert mode (inherent to hook event timing)

> Fun fact: The alert sound was designed and crafted by hand by the author (@ojowwalker77).

## [1.4] - 2025-01-09

### Changed
- Auto-pin: sessions automatically appear in notch on start
- `/send-to-notch` is now fallback for re-pinning after removal

### Fixed
- App icon now on bundle (lol)

## [1.3] - 2025-01-08

### Added
- Hover-to-fade: pills become nearly transparent (5% opacity) when mouse hovers over them
- Click-through: mouse events pass through to windows below
- Per-screen hover: each monitor's pills fade independently

### Changed
- Simplified hover detection (replaced proximity-based fade with direct hit testing)
- Tighter hover area: only triggers on actual pill region, not full window

## [1.2] - 2025-01-08

### Added
- Monitor picker: select which display to show the notch on
- Open at Login option with first-launch prompt

### Changed
- Replaced "Show on All Monitors" toggle with Display submenu
- Performance improvements for smoother animations

## [1.1] - 2025-01-08

### Changed
- Hooks now auto-install on first launch (no setup click required)
- Onboarding window only appears if installation fails
- Manual setup still available via menu bar → "Setup..."

### Added
- Documentation for hooks configuration (`docs/hooks.md`)
- Documentation for slash commands (`docs/skills.md`)

## [1.0] - 2025-01-08

### Added
- Initial public release
- Real-time Claude Code activity display
- Tool tracking with semantic colors
- Context window percentage indicator
- Multi-session support via `/send-to-notch`
- Homebrew distribution
