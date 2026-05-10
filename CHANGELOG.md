# Changelog

All notable changes to LuxControl are documented here.

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
