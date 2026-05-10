# Hardware Test Matrix

## Scope

This checklist verifies public-API-first display behavior for LuxControl. It must be run without copying Vivid assets, strings, private code, or license behavior.

## Devices

| Device | Required | Result | Notes |
| --- | --- | --- | --- |
| Built-in MacBook Pro XDR display | Yes | Not run | |
| Apple Studio Display | Yes | Not run | |
| Pro Display XDR | Yes | Not run | |
| Ordinary external monitor | Yes | Not run | Should be limited or unsupported |

## Checks

1. App launches and shows a menu bar item.
2. Display list includes the connected display.
3. Diagnostics report includes stable key, support level, OS version, and current state.
4. Brightness slider changes internal state without flicker.
5. Unsupported displays show limited or unsupported status.
6. Boost toggle is disabled unless support level is full.
7. Relaunch restores saved per-display state for currently connected displays.
8. Disconnecting a display does not crash the app.
9. Reconnecting a display restores its saved state.
10. Hotkey commands route to the selected display.

## Public API Research Notes

- Record which public APIs can read brightness.
- Record which public APIs can write brightness.
- Record whether extended brightness is controllable without private APIs.
- Record permission prompts observed on the tested macOS version.
