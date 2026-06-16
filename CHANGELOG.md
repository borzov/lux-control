# Changelog

All notable changes to LuxControl are documented here.

## 0.1.2 - 2026-06-16

### Added

- Global hotkeys are now active: ⌘⌥= brighten, ⌘⌥- dim, ⌘⌥Space toggle Boost on the selected display.
- Per-display Boost is now persisted and re-applied on launch for displays that had it enabled.
- Real localized display names in the picker, so multiple external monitors are distinguishable.
- Automatic display-list refresh when a display is connected, disconnected, or reconfigured.
- Live brightness updates while dragging the slider (previously applied only on release).

### Fixed

- Display gamma is now restored if the app exits or crashes while Boost is active, preventing a distorted screen until logout. Force Quit (SIGKILL) cannot be intercepted and is out of scope.

## 0.1.1 - 2026-05-10

### Added

- App icon for the macOS bundle.
- GitHub Actions compatibility checks for macOS 26 Tahoe, macOS 15 Sequoia, and macOS 14 Sonoma.
- README compatibility and quarantine-removal installation guidance.

### Changed

- Repository URL changed to `https://github.com/borzov/lux-control`.
- Diagnostics settings are now hidden from release-compatible builds and only compile in when `DEVELOPMENT_DIAGNOSTICS` is enabled.

## 0.1.0 - 2026-05-10

Initial release candidate.

### Added

- Menu bar app for controlling supported Mac display brightness.
- Boost mode for compatible EDR/XDR displays.
- Real brightness read and write support through macOS display services.
- Per-display state handling.
- Display discovery and support-level reporting.
- Settings window with launch-at-login controls.
- Optional Boost on launch when LuxControl opens at login.
- Diagnostics view for display and app state.
- Global hotkey service foundation.
- Hardware test checklist.
- Marketing README and release graphics.
