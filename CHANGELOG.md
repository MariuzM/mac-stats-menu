# Changelog

All notable changes to this project are documented here.

## [0.7.0] - 2026-07-26

### Added
- Claude Code and Codex rate-limit rows in the stats panel, each toggleable in Settings.

### Changed
- Bundle identifier is now `com.mariuzm.statsmenu` — settings reset to defaults and "Launch at login" must be re-enabled once.

## [0.6.0] - 2026-07-12

### Added
- Optional high-contrast menu bar mode for improved visibility against light and translucent backgrounds.

## [0.5.0] - 2026-07-11

### Added
- Persistent refresh timing controls for menu bar, panel, process flyouts, GPU, and disk sampling.
- Restore-defaults action for sampling settings.

### Changed
- Adaptive GPU and disk polling reduces work while the stats panel is closed.
- Process flyout sampling is throttled and top-process selection avoids sorting the full process list.
- Temporary sampling allocations are released sooner to reduce memory pressure.

## [0.4.0] - 2026-07-11

- Disk row with read/write graph and top-apps flyout, solid dark UI, ~9× lower idle CPU.

## [0.3.0] - 2026-07-06

### Added
- GPU flyout showing top GPU processes.

## [0.2.0] - 2026-07-03

### Added
- Settings window opened from a gear icon in the popover header.
- "Launch at login" toggle in Settings, backed by `SMAppService` (macOS 13+).

## [0.1.0] - 2026-07-03

### Added
- First release. Native macOS menu bar system monitor — CPU / Memory / GPU / Network with per-process flyouts.
