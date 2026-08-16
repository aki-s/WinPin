This doc is for `WinPin` version 0.0.1 (stable version)

# About

WinPin is a native macOS AppKit menu bar app for best-effort per-window pinning.

Useful when;

- You are annoyed by the default MacOS switcher, which brings all windows in front.
  This behavior hides the previous window you were working but you have been interested in yet.
  - You want to focus solely on the active windows you're using across multiple apps.
- You join a video meeting while keeping the window on top of other screens.
  (e.g. Zoom.app supports this feature, but only when minimized).

## Features

### Shortcut

`ctrl+alt+Command+t` to Pin the currently focused window.

### Menu bar

![menu](./docs/menu.20260816.png)

You can define which window should be stacked on the other Pinned windows manually.

![win-stacks](./docs/Pinwin.win-stacks.png)

## Development

```sh
./scripts/build-debug-reset-accessibility.sh
./scripts/restart.sh
```
