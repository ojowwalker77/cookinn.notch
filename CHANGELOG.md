# Changelog

All notable changes to cookinn.notch will be documented in this file.

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
