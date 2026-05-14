# WinPin — Codex Implementation Brief

## 0. Project Summary

Build a macOS menu bar resident app named **WinPin**.

WinPin lets the user pin **a specific window of a specific app**, not the whole app, so that the selected window is repeatedly raised above other windows until the user unpins it. The key problem to solve is macOS's default behavior where focusing one window of an app can bring other windows from the same app forward as well. WinPin should avoid app-level activation where possible and operate at the individual Accessibility window level.

The app must be implemented as a native macOS app using Swift + AppKit.

## 1. Primary User Story

As a macOS user with multiple apps and multiple windows open on one screen, I want to keep one chosen window visible above other windows while I interact with other apps, so that I can compare information without repeatedly switching windows or accidentally bringing the whole source app forward.

Example:

- User has multiple browser windows, an editor, a terminal, and a document open.
- User pins only one browser window.
- User switches to the editor.
- The pinned browser window remains visually above other windows as much as macOS allows.
- Other browser windows should not be raised just because the pinned browser window is pinned.

## 2. App Name

The app name is:

```text
WinPin
```

Bundle/product naming should use `WinPin` unless a technical identifier requires a reverse-DNS bundle ID.

Recommended bundle ID placeholder:

```text
com.akis.WinPin
```

## 3. Platform and Technology Requirements

- Platform: macOS.
- Language: Swift.
- UI framework: AppKit preferred.
- App type: menu bar resident app.
- No Dock icon by default.
- Use Accessibility APIs for reading and manipulating other apps' windows.
- Use AppKit `NSStatusItem` for the menu bar item.
- Use a border-only `NSPanel` overlay to show pinned window state.
- Tier 1 uses a fixed default global keyboard shortcut. User-configurable shortcut recording is deferred to Tier 3.
- The app icon and menu bar glyph should use the pin symbol `📌`.

## 4. Hard Constraints and Realistic macOS Limitations

### 4.1 Accessibility Permission

WinPin requires Accessibility permission.

On first launch or before first pin operation, detect whether the app is trusted for Accessibility. If not trusted:

- Show a clear explanation.
- Provide a button/action to open System Settings > Privacy & Security > Accessibility where possible.
- Disable pin actions until permission is granted.

### 4.2 Per-Window Pinning, Not App Activation

Do **not** use app-level activation as the main mechanism.

Avoid this as the primary operation:

```swift
NSRunningApplication.activate(...)
```

Reason: activating the app tends to bring the app context forward and can defeat the goal of pinning only one specific window.

Preferred action:

```swift
AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
```

### 4.3 Window-Level Pinning Is Best-Effort

macOS does not provide a stable public API to mark another app's existing window as truly “always on top”. Therefore WinPin must use a best-effort strategy:

- Keep a reference to the selected `AXUIElement` window.
- Periodically and/or reactively call `kAXRaiseAction` on that window.
- Track the window frame and update a visual overlay.
- If the target app/window disappears, treat the pin as stale and remove it automatically.

### 4.4 Space / Fullscreen Support

Space support is “best effort”.

- The yellow overlay window created by WinPin may use `collectionBehavior` such as `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
- WinPin must not promise that a third-party app's pinned window can be moved across Spaces or shown over all full-screen apps.
- If Space/fullscreen behavior fails due to OS restrictions, fail gracefully.

### 4.5 Shortcut Conflict Detection Limitation

Tier 3 settings UI must let the user assign a shortcut by pressing keys. Tier 1 keeps the fixed default shortcut `Control + Option + Command + P`.

Required behavior:

- Attempt to register the selected shortcut globally.
- If registration fails because the shortcut is already reserved or unavailable, reject it.
- Show a message like:

```text
This shortcut is already used by macOS or another app, so WinPin cannot use it.
```

Important limitation:

- macOS does not provide a comprehensive public API to enumerate every shortcut used by every app.
- Therefore, implement conflict detection by actually attempting global registration.
- If registration fails, treat it as unavailable.
- If registration succeeds, treat it as available.
- Do not claim to identify the exact app using the shortcut unless the implementation has reliable evidence. The UI may say “macOS or another app”, not a specific app name.

## 5. Required Features

### 5.1 Menu Bar Resident App

WinPin must run as a menu bar app.

Menu bar item behavior:

- Clicking the menu bar item opens a menu or popover.
- The menu/popup shows pinned windows.
- The app should not appear in the Dock by default.
- `Command + ,` opens the settings window when WinPin is active.
- Launching with `./scripts/restart.sh --show-dock` shows a temporary Dock icon.
- In that Dock menu, list `設定画面を開く` and `menubarへの表示非表示切り替え`; the latter toggles the `NSStatusItem` visibility.

Suggested menu items:

```text
WinPin
────────────────────────
Pin Current Window / Unpin Current Window

Pinned Windows
  [App Icon] App Name — Window Title     ✓ Pinned
  [App Icon] App Name — Window Title     ✓ Pinned

Settings…
Quit WinPin
```

### 5.2 Pin Current Focused Window

The user must be able to pin the currently focused/frontmost window.

Implementation outline:

1. Get the system-wide accessibility element:

```swift
let systemWide = AXUIElementCreateSystemWide()
```

2. Get the focused application/window through Accessibility attributes.
3. Extract:
   - PID
   - app name
   - app icon
   - window title
   - window frame
   - AX window element
4. Store it as a pinned window.
5. Start raise maintenance.
6. Show yellow border overlay around the pinned window.

### 5.3 Unpin Current Window

The same command should unpin the currently focused window if it is already pinned.

Matching should use a robust identity strategy:

- Prefer PID + AX element identity where possible.
- Also keep fallback metadata:
  - app bundle identifier
  - window title
  - last known frame

### 5.4 Pinned Window List

When the user clicks the WinPin menu bar item, show the list of windows currently being raised/pinned.

Each list item must show:

- App icon.
- App name.
- Window title.
- Pin status.
- Action to unpin that item.

If a pinned window becomes unavailable:

- Treat it as stale and remove it automatically.
- Remove its overlay immediately.
- Do not crash.

When multiple windows are pinned:

- Later pins win.
- Raise pinned windows in pin order so the most recently pinned window is raised last.
- Overlay stacking/order polish is Tier 2; for MVP, keep overlays correct and non-interactive without over-optimizing visual z-order.

### 5.5 Global Keyboard Shortcut Toggle

WinPin must support a global keyboard shortcut that toggles pin/unpin for the current focused window.

Behavior:

- If focused window is not pinned: pin it.
- If focused window is already pinned: unpin it.
- If Accessibility permission is missing: show permission prompt instead.

### 5.6 User-Assignable Shortcut in Settings

Tier: **Tier 3**. Do not block the Tier 1 MVP on this feature. Tier 1 uses the fixed default shortcut `Control + Option + Command + P`.

Add a settings screen where the user can assign the global shortcut by pressing the desired key combination.

Requirements:

- Provide a shortcut recorder UI.
- Record modifier keys and main key.
- Require at least one meaningful modifier unless there is a strong reason not to. `Command` is meaningful; `Shift` alone is not meaningful and must not be accepted by itself.
- Validate by attempting global hotkey registration.
- If the shortcut is unavailable, reject the assignment and show an error.
- If available, save it to UserDefaults and use it immediately.

Suggested default shortcut:

```text
Control + Option + Command + P
```

The implementation may use Carbon `RegisterEventHotKey` for global hotkey registration, or another reliable native equivalent. The validation path and actual registration path should be the same or equivalent so that settings validation reflects runtime behavior.

### 5.7 Yellow Border Overlay

Pinned windows must be visually marked with a yellow border.

Implementation requirements:

- Use WinPin-owned transparent border-only `NSPanel` or equivalent overlay.
- Overlay must not intercept mouse events.
- Overlay must not become key/main window.
- Overlay must track the target window frame.
- Overlay should be visible while the window is pinned.
- Overlay should be removed immediately when unpinned.

Suggested panel behavior:

```swift
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .screenSaver // or a lower level if screenSaver is too aggressive
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```

The border view should draw a yellow stroke. Suggested width: 3–5 px.

## 6. Internal Architecture

Implement the app with separated components.

### 6.1 `AppDelegate` / App Entry

Responsibilities:

- Initialize menu bar UI.
- Initialize managers.
- Check Accessibility permission.
- Register the fixed Tier 1 global shortcut.
- Tier 3: load a saved user-configured shortcut when shortcut recording exists.

### 6.2 `MenuBarController`

Responsibilities:

- Create `NSStatusItem`.
- Build and refresh menu/popover.
- Display pinned window list with icons and titles.
- Provide menu actions:
  - Pin/Unpin Current Window.
  - Settings.
  - Quit.

### 6.3 `AccessibilityPermissionManager`

Responsibilities:

- Check Accessibility trust.
- Trigger system prompt/open settings.
- Expose current trust status.

### 6.4 `AXWindowProvider`

Responsibilities:

- Get current focused window.
- List windows for a target app if needed.
- Read window title, frame, PID, app name.
- Perform `kAXRaiseAction`.
- Detect when AX element is no longer valid.

Suggested model:

```swift
struct AXWindowSnapshot: Hashable {
    let id: UUID
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let windowTitle: String
    let frame: CGRect
}

final class PinnedWindow {
    let id: UUID
    let axElement: AXUIElement
    var snapshot: AXWindowSnapshot
    var isStale: Bool
}
```

### 6.5 `PinManager`

Responsibilities:

- Maintain pinned windows.
- Pin current window.
- Unpin current window.
- Unpin by ID.
- Run raise maintenance loop.
- Notify UI updates.

Raise strategy:

- Use a conservative timer initially, e.g. every 250–500 ms while at least one window is pinned.
- Optionally add `AXObserver` later for focus/window-change events.
- Avoid excessive CPU usage.
- Avoid raising stale/missing windows.

### 6.6 `BorderOverlayManager`

Responsibilities:

- Create one overlay per pinned window.
- Update overlay frame based on target window frame.
- Remove overlay when unpinned/stale.
- Keep overlays non-interactive.

### 6.7 `HotKeyManager`

Responsibilities:

- Register global shortcut.
- Unregister previous shortcut.
- Invoke PinManager toggle action when triggered.
- Tier 1: register the fixed default shortcut `Control + Option + Command + P`.
- Tier 3: validate shortcut availability by attempting registration.
- Tier 3: persist accepted shortcut.

Suggested model:

```swift
struct HotKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayString: String
}
```

Validation behavior:

Tier: **Tier 3**.

```text
Input candidate shortcut
→ temporarily attempt to register it
→ if success: unregister temp registration, save, then register active shortcut
→ if failure: show conflict/unavailable error and do not save
```

### 6.8 `SettingsWindowController`

Tier: **Tier 3**.

Responsibilities:

- Display current shortcut.
- Let user record a new shortcut.
- Show validation errors.
- Save accepted shortcut.

Settings UI copy for shortcut conflict:

```text
This shortcut is already used by macOS or another app, so WinPin cannot use it. Choose another shortcut.
```

Settings UI copy for successful assignment:

```text
Shortcut updated.
```

## 7. Persistence

Use `UserDefaults` for simple preferences.

Persist:

- Tier 3: assigned global shortcut.
- Optional: launch at login preference.

Do not persist pinned windows across app relaunch in MVP unless explicitly implemented later. AX window references are not stable across sessions.

## 8. Error Handling

### 8.1 Missing Accessibility Permission

When pinning is requested without permission:

- Do not attempt to pin.
- Show clear prompt.
- Provide path to settings.

### 8.2 Window Does Not Support Raise

If `AXUIElementPerformAction(..., kAXRaiseAction...)` fails:

- Show non-fatal error.
- Do not crash.
- Mark the window as unsupported or stale.

### 8.3 Target Window Closed

If the target window is closed:

- Treat it as stale.
- Remove its overlay.
- Remove it from the pinned list automatically.
- Continue managing other pinned windows.

### 8.4 Shortcut Registration Failure

If the selected shortcut cannot be registered:

- Reject the shortcut.
- Keep the previous shortcut active.
- Show the conflict message.

## 9. Non-Goals for MVP

Do not implement these in the first version unless the core MVP is complete:

- Moving other apps' windows across Spaces.
- True OS-level always-on-top flag for third-party windows.
- Identifying the exact other app that owns a conflicting shortcut.
- Persisting pinned windows across reboot/relaunch.
- App Store sandbox compliance.
- Complex window picker UI.
- User-configurable shortcut recorder and shortcut conflict UI; this is Tier 3, not Tier 1 MVP.

## 10. Acceptance Criteria

### 10.1 Menu Bar

- WinPin launches as a menu bar app.
- WinPin appears in the menu bar.
- WinPin does not appear in the Dock by default.
- Clicking the menu bar icon shows menu/pinned windows/settings/quit.
- The WinPin app icon is `📌`.
- `./scripts/restart.sh --show-dock` launches WinPin with a Dock icon whose Dock menu exposes `設定画面を開く` and `menubarへの表示非表示切り替え`.

### 10.2 Accessibility

- If Accessibility permission is missing, pin actions are blocked with clear guidance.
- If Accessibility permission is granted, current focused window can be read.

### 10.3 Pinning

- User can pin the currently focused window.
- Pinning uses window-level Accessibility action, not app-level activation as the primary mechanism.
- Pinned window is repeatedly raised while pinned.
- Other windows from the same app should not intentionally be raised by WinPin.
- If multiple windows are pinned, the most recently pinned window wins the raise order.

### 10.4 Unpinning

- User can unpin a pinned window from the shortcut.
- User can unpin a pinned window from the menu list.
- Yellow border disappears immediately after unpin.

### 10.5 Pinned List

- Menu shows pinned windows.
- Each pinned item shows app icon, app name, and window title.
- Closed/stale windows are automatically removed and handled safely.

### 10.6 Shortcut Settings

Tier: **Tier 3**. These are not required for Tier 1 MVP.

- User can open settings.
- User can press a key combination to assign shortcut.
- If registration succeeds, shortcut is saved and activated.
- If registration fails, shortcut is rejected and the UI states it is already used by macOS or another app.
- Previous valid shortcut remains active after failed assignment.

### 10.7 Yellow Border

- Pinned window has a yellow border.
- Border follows the pinned window position and size.
- Border does not intercept mouse clicks.
- Border does not steal focus.

## 11. Suggested Implementation Order

### 11.1 Priority Tiers

Tier 1 MVP scope:

- [x] Menu bar app with runtime Dock visibility control.
- [x] `📌` runtime app icon and menu bar glyph.
- [x] `Cmd+,` settings menu item and recovery Dock menu items for settings and menu bar visibility.
- [x] Accessibility permission check and Settings access.
- [x] Focused window detection through Accessibility.
- [x] Pin/unpin current focused window using `kAXRaiseAction`.
- [x] Timer-based raise maintenance.
- [x] Yellow border overlay.
- [x] Pinned window list.
- [x] Fixed default global shortcut: `Control + Option + Command + P`.
- [x] Automatic stale-window removal when a pinned window is closed/unavailable.
- [x] Basic tests for core pin state behavior where practical.

Tier 2 scope:

- [ ] Multiple-pinned-window visual polish, including overlay stacking/order behavior.
- [ ] Additional refinement beyond correct pin order and non-interactive overlays.

Tier 3 scope:

- [ ] Configurable Settings shortcut recorder.
- [ ] Shortcut conflict validation UI by attempting registration.
- [ ] Shortcut persistence beyond the fixed Tier 1 default.

### 11.2 First Slice Progress

- [x] Create native Xcode macOS AppKit project named `WinPin`.
- [x] Configure menu bar app with `NSStatusItem` and runtime Dock visibility control.
- [x] Add `📌` runtime app icon and menu bar glyph.
- [x] Add `Cmd+,` settings menu item and recovery Dock menu items for settings and menu bar visibility.
- [x] Add Accessibility permission check and menu diagnostics.
- [x] Implement focused AX window detection.
- [x] Implement pin/unpin via menu using `kAXRaiseAction`.
- [x] Add timer-based raise loop.
- [x] Add yellow border overlay panel.
- [x] Add pinned window list with app icon/name/window title.
- [x] Add fixed default global shortcut.
- [ ] Add configurable Settings shortcut recorder. **Tier 3; not required for Tier 1 MVP.**
- [x] Add stale window cleanup.
- [x] Add basic tests for core pin state behavior.

### 11.3 Full Suggested Order

- [x] Create macOS AppKit project named `WinPin`.
- [x] Configure as menu bar app with `NSStatusItem`.
- [x] Add Accessibility permission check.
- [x] Implement focused AX window detection.
- [x] Implement one-window pin/unpin with `kAXRaiseAction`.
- [x] Add timer-based raise loop.
- [x] Add yellow border overlay panel.
- [x] Add pinned window list in menu.
- [x] Add global shortcut with fixed default shortcut.
- [x] Add stale window cleanup.
- [x] Add basic tests where practical.
- [ ] Tier 2: refine multi-window overlay ordering/stacking.
- [ ] Tier 3: add settings window with shortcut recorder.
- [ ] Tier 3: add shortcut conflict validation by attempting registration.

## 12. Reference APIs

Use these APIs/concepts:

- `NSStatusBar` / `NSStatusItem` for menu bar app.
- `AXUIElement` for Accessibility elements.
- `AXUIElementCreateSystemWide()`.
- `AXUIElementCopyAttributeValue()`.
- `AXUIElementPerformAction()`.
- `kAXRaiseAction`.
- `kAXFocusedWindowAttribute`.
- `kAXTitleAttribute`.
- `kAXPositionAttribute`.
- `kAXSizeAttribute`.
- `NSPanel` for overlay border.
- `NSWindow.ignoresMouseEvents`.
- `NSWindow.Level`.
- `NSWindow.CollectionBehavior.canJoinAllSpaces`.
- `RegisterEventHotKey` or equivalent reliable global shortcut mechanism.

## 13. Important Implementation Notes for Codex

- Prefer simple, working MVP over clever abstractions.
- Keep the code modular enough to replace the raise loop with `AXObserver` later.
- The app should never intentionally activate the target app as the primary pinning method.
- Do not claim perfect Space/fullscreen behavior.
- Do not claim exact shortcut-owner detection.
- Treat all cross-app window control as best-effort and permission-dependent.
- Add comments around macOS limitations so future maintainers do not “fix” them incorrectly.
