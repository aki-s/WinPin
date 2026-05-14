# Hammerspoon / ShiftIt Shortcut Collision Investigation

Date: 2026-05-14

## Trigger

WinPin's original Tier 1 default shortcut was `Control + Option + Command + P`. The shortcut appeared unreliable, but the actual cause was a collision with the user's Hammerspoon ShiftIt setup.

## Findings

- Hammerspoon is a macOS automation app with Lua plugins called Spoons.
- `peterklijn/hammerspoon-shiftit` is a ShiftIt-like Hammerspoon Spoon.
- ShiftIt's default binding map uses `Control + Option + Command + P` for `previousScreen`.
- ShiftIt also occupies the broader `Control + Option + Command` family for arrows, `1`, `2`, `3`, `4`, `M`, `F`, `Z`, `C`, `N`, `P`, `=`, and `-`.
- This conflict family overlaps strongly with WinPin's target users: people who already use window-management tools.
- `Control + Option + Command + T` is not in ShiftIt's documented default list, so it is a safer immediate default than `P`, while still requiring future user configurability.

## Decision

- Change WinPin's fixed Tier 1 default shortcut to `Control + Option + Command + T`.
- Keep WinPin as a native macOS app. Do not replace it with a Hammerspoon Spoon.
- Consider a Hammerspoon companion Spoon/plugin only as Tier 3 integration for users who already manage shortcuts from Hammerspoon.
- Promote shortcut recorder and conflict UI from Tier 3 to Tier 1.5 because a fixed shortcut is now a known MVP risk.
- Do not claim to identify the exact shortcut owner. macOS does not provide a comprehensive public API for all app-owned shortcuts.

## Shortcut Conflict Handling

Required behavior:

- Validate shortcut availability by attempting global registration.
- If registration fails, reject the shortcut and keep the previous valid shortcut.
- Show an owner-agnostic diagnostic:

```text
WinPin shortcut could not be registered. Another app or macOS may already be using it.
```

Avoid saying "Hammerspoon is using this shortcut" unless WinPin has reliable evidence.

## Shortcut Recorder Dependency Options

Candidate: `sindresorhus/KeyboardShortcuts`

- License: MIT.
- Swift Package Manager support.
- Provides SwiftUI and Cocoa recorder controls.
- Handles UserDefaults storage.
- Documents warnings for shortcuts already used by the system or the app main menu.
- Works with menu bar apps while `NSMenu` is open.
- Best fit if WinPin accepts a dependency for Tier 1.5.

Candidate: `soffes/HotKey`

- License: MIT.
- Swift Package Manager support.
- Small Swift wrapper around Carbon global hotkey APIs.
- Good for registration lifecycle, but does not provide a recorder UI.
- Less useful for the requested Settings shortcut recorder by itself.

Candidate: `Kentzo/ShortcutRecorder`

- Mature recorder control with AppKit/Objective-C history.
- Supports local/global shortcut monitors and Accessibility-backed monitoring.
- Larger and older surface than WinPin needs for the first shortcut recorder pass.
- License needs direct review before adoption because the GitHub page reports "View license" rather than a short SPDX label.

Recommendation: start Tier 1.5 with `KeyboardShortcuts` if adding a dependency is acceptable. It is MIT licensed, SPM-friendly, has a Cocoa recorder for the current AppKit settings window, and directly targets user-customizable global shortcuts. If dependency avoidance remains more important, implement a minimal first-party recorder using the existing Carbon registration path, but expect more UI and edge-case work.

## Sources

- https://github.com/peterklijn/hammerspoon-shiftit
- https://github.com/Hammerspoon/hammerspoon
- https://www.hammerspoon.org/docs/hs.hotkey.html
- https://www.hammerspoon.org/docs/hs.window.html
- https://github.com/sindresorhus/KeyboardShortcuts
- https://github.com/soffes/HotKey
- https://github.com/Kentzo/ShortcutRecorder
