# WinPin

WinPin is a native macOS AppKit menu bar app for best-effort per-window pinning.

The app tracks a specific Accessibility window, repeatedly raises that window with `kAXRaiseAction`, and draws a WinPin-owned yellow border overlay around it. macOS does not provide a public API to make another app's existing window truly always-on-top, so this behavior is intentionally best effort.

## Current MVP

Implemented:

- Menu bar app with a configurable Dock icon
- Accessibility permission check and menu diagnostics
- Pin/unpin current focused window from the menu
- Unpin pinned windows from the menu list
- Fixed global shortcut: `Control + Option + Command + T`
- Timer-based `kAXRaiseAction` maintenance loop
- Yellow non-interactive `NSPanel` border overlay
- Pinned window list with app icon, app name, and window title
- Stale window cleanup
- Multiple pinned windows use later-pin-wins raise order
- Settings window for toggling the Dock icon
- Unit tests for pin overlay creation, transient stale handling, stale removal, and later-pin-wins raise order

Not implemented yet:

- Shortcut recorder UI
- User-configurable shortcut persistence

## Project Layout

```text
WinPin.xcodeproj/              Xcode project
WinPin/
  main.swift                   AppKit entry point
  AppDelegate.swift            App lifecycle and manager wiring
  MenuBarController.swift      Status item and menu
  AccessibilityPermissionManager.swift
  AXWindowProvider.swift       Focused window lookup and AX raise
  PinManager.swift             Pin state and raise loop
  BorderOverlayManager.swift   Yellow overlay panels
  HotKeyManager.swift          Fixed Carbon global hotkey
  Models.swift                 Shared window models
  Info.plist                   Standard AppKit app metadata
plan.md                        Implementation brief and progress
```

## Build

From the repository root:

```sh
xcodebuild -project WinPin.xcodeproj -scheme WinPin -configuration Debug -derivedDataPath build/DerivedData build
```

The explicit `-derivedDataPath build/DerivedData` keeps generated Xcode output inside the repo-local ignored `build/` directory.

## Test

```sh
xcodebuild -project WinPin.xcodeproj -scheme WinPin -configuration Debug -derivedDataPath build/DerivedData -destination platform=macOS test
```

The test suite covers the core pin state logic without touching real Accessibility windows.

## Run Manually

After building, launch:

```sh
open build/DerivedData/Build/Products/Debug/WinPin.app
```

WinPin is a menu bar app and does not show a Dock icon by default. The app hides the Dock icon at runtime with `.accessory` activation policy, rather than using `LSUIElement`, so the Dock icon can be toggled later from Settings. Look for the `WinPin` text status item in the menu bar.

For recovery, launch with a temporary Dock icon:

```sh
scripts/restart.sh --show-dock
```

You can also hold Option while launching the app. In recovery mode, WinPin appears as a regular app so the Dock menu can expose `Show Menu Bar Item` and `Quit WinPin`.

## Settings

Open Settings with `Command + ,`, the Dock menu, or the WinPin menu bar item.

Settings currently includes:

- `Show Dock icon`: persists whether WinPin should launch as a regular Dock/Cmd+Tab app or as a menu bar accessory app.

## Accessibility Permission

WinPin needs Accessibility permission to read and raise other apps' windows.

If permission is missing, the menu disables pinning and exposes actions to request permission or open Accessibility settings. After granting permission in System Settings, relaunching the app is the most reliable way to confirm the new trust state during development.

To reset the development Accessibility grant for the WinPin bundle ID:

```sh
scripts/reset-accessibility.sh
```

To build and then reset the grant in one step:

```sh
scripts/build-debug-reset-accessibility.sh
```

## Development Notes

- Do not use app-level activation as the primary pinning mechanism. Raising should stay focused on the target `AXUIElement` window.
- Pinning is not a true always-on-top flag. When the user opens or activates another window, macOS may keep that active window above the raised Accessibility window.
- Keep the overlay level centralized in `BorderOverlayManager` so it can be lowered if `.screenSaver` proves too aggressive.
- Treat Spaces and fullscreen behavior as best effort.
- Shortcut conflict detection for the fixed shortcut is based on whether Carbon hotkey registration succeeds.
- The fixed shortcut installs both Carbon hotkey registration and an `NSEvent` key monitor fallback because menu bar apps can be sensitive to Carbon hotkey delivery differences. Hotkey delivery is throttled to avoid double toggles when both paths fire.
- If the fixed shortcut cannot be registered, the menu reports that another app or macOS may already be using it. WinPin must not claim to know the owning app unless there is reliable evidence.
- Future configurable shortcuts should validate candidates using the same registration path and keep the previous working shortcut on failure.
- Known conflict family: Hammerspoon ShiftIt defaults use `Control + Option + Command` with arrows, `1`, `2`, `3`, `4`, `M`, `F`, `Z`, `C`, `N`, `P`, `=`, and `-`. Avoid these occupied combinations for WinPin defaults.
