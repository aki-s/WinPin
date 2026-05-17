import ApplicationServices
import XCTest
@testable import WinPin

final class PinManagerTests: XCTestCase {
    func testPinShowsOverlayWithoutImmediateRefresh() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure]
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.shownIDs, [window.id])
        XCTAssertEqual(overlay.removedIDs, [])
        XCTAssertEqual(provider.refreshCallCount, 0)
    }

    func testInitialRaiseSuccessIsLogged() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()

        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_succeeded reason=initial_raise_succeeded")
                && message.contains("title=\"Pinned\"")
        })
    }

    func testInitialRaiseFailureStillPinsAndShowsOverlay() {
        let window = makeWindow(title: "Pinned", axRole: kAXWindowRole, supportedActions: [kAXRaiseAction])
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.raiseResults = [.failure]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.shownIDs, [window.id])
        XCTAssertEqual(provider.raisedIDs, [window.id])
        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_failed reason=initial_raise_failed")
                && message.contains("rawValue=")
                && message.contains("title=\"Pinned\"")
                && message.contains("ax_role=\"AXWindow\"")
                && message.contains("ax_supported_actions=\"AXRaise\"")
        })
    }

    func testTransientMaintenanceFailuresDoNotImmediatelyRemovePinnedWindow() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure, .failure, .success]
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.removedIDs, [])

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(window.maintenanceFailureCount, 0)
    }

    func testMaintenanceRecoveryIsLoggedAfterTransientFailure() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.success, .success]
        provider.raiseResults = [.success, .failure, .success]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_succeeded reason=maintenance_recovered")
                && message.contains("title=\"Pinned\"")
        })
    }

    func testConsecutiveMaintenanceFailuresRemovePinnedWindow() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure, .failure, .failure]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [])
        XCTAssertEqual(overlay.removedIDs, [window.id])
        XCTAssertEqual(logger.messages.filter { $0.contains("pin_maintenance_failed operation=refresh") }.count, 3)
        XCTAssertTrue(logger.messages.contains { $0.contains("pin_removed reason=stale_window") })
    }

    func testConsecutiveRaiseFailuresDoNotRemoveAvailablePinnedWindow() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.success, .success, .success, .success]
        provider.raiseResults = [.success, .failure, .failure, .failure, .failure]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.removedIDs, [])
        XCTAssertEqual(logger.messages.filter { $0.contains("pin_maintenance_failed operation=raise") }.count, 3)
        XCTAssertTrue(logger.messages.allSatisfy { !$0.contains("pin_removed reason=stale_window") })
        XCTAssertTrue(logger.messages.contains { $0.contains("stale_candidate=false") })
    }

    func testPinFailureWithoutAccessibilityIsLogged() {
        let permission = MockPermissionManager(isTrusted: false)
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: MockWindowProvider(focusedWindows: []),
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow(source: .hotKey)

        XCTAssertEqual(logger.messages, [
            "pin_requested source=hotkey",
            "pin_failed reason=accessibility_permission_missing source=hotkey"
        ])
    }

    func testMaintenanceOnlyRaisesLatestPinnedWindowToAvoidFlicker() {
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [first.id, second.id])
        XCTAssertEqual(provider.raisedIDs, [second.id])
    }

    private func makeWindow(
        title: String,
        pid: pid_t = 100,
        axRole: String? = nil,
        supportedActions: [String] = []
    ) -> PinnedWindow {
        let id = UUID()
        let snapshot = AXWindowSnapshot(
            id: id,
            pid: pid,
            bundleIdentifier: "com.example.\(title)",
            appName: "App \(title)",
            windowTitle: title,
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            axRole: axRole,
            supportedActions: supportedActions
        )
        return PinnedWindow(
            id: id,
            axElement: AXUIElementCreateSystemWide(),
            snapshot: snapshot,
            appIcon: nil
        )
    }
}

final class WinPinRuntimeSpecTests: XCTestCase {
    private let showMenuBarItemKey = "showMenuBarItem"

    func testAppIconAndMenuBarGlyphUsePinSymbol() {
        XCTAssertEqual(AppIconFactory.symbol, "📌")
    }

    func testMenuBarItemPreferenceDefaultsToVisible() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: showMenuBarItemKey)
        defaults.removeObject(forKey: showMenuBarItemKey)
        defer {
            restore(original, forKey: showMenuBarItemKey)
        }

        XCTAssertTrue(AppPreferences.showMenuBarItem)
    }

    func testMenuBarControllerCanToggleStatusItemVisibility() {
        let original = UserDefaults.standard.object(forKey: showMenuBarItemKey)
        defer {
            restore(original, forKey: showMenuBarItemKey)
        }

        let manager = makeMenuBarController()

        manager.setMenuBarItemVisible(true)
        XCTAssertTrue(manager.menuBarItemIsVisible)
        XCTAssertTrue(manager.statusItemIsInstalledForTesting)
        XCTAssertTrue(AppPreferences.showMenuBarItem)

        manager.toggleMenuBarItemVisibility()
        XCTAssertFalse(manager.menuBarItemIsVisible)
        XCTAssertFalse(manager.statusItemIsInstalledForTesting)
        XCTAssertFalse(AppPreferences.showMenuBarItem)

        manager.toggleMenuBarItemVisibility()
        XCTAssertTrue(manager.menuBarItemIsVisible)
        XCTAssertTrue(manager.statusItemIsInstalledForTesting)
        XCTAssertTrue(AppPreferences.showMenuBarItem)

        manager.setMenuBarItemVisible(false)
    }

    func testDockMenuListsRequiredRecoveryActions() {
        let appDelegate = AppDelegate()
        let menu = appDelegate.applicationDockMenu(NSApp)

        XCTAssertEqual(menu?.items.map(\.title), [
            AppMenuTitle.dockSettings,
            AppMenuTitle.dockMenuBarVisibilityToggle,
            AppMenuTitle.quit
        ])
    }

    func testCommandCommaMainMenuOpensSettings() {
        let appDelegate = AppDelegate()

        appDelegate.installMainMenu()

        let appMenu = NSApp.mainMenu?.items.first?.submenu
        let settingsItem = appMenu?.items.first { $0.title == AppMenuTitle.settings }
        XCTAssertEqual(settingsItem?.keyEquivalent, ",")
        XCTAssertEqual(settingsItem?.keyEquivalentModifierMask, [.command])
    }

    func testCommandWMainMenuClosesKeyWindowThroughResponderChain() {
        let appDelegate = AppDelegate()

        appDelegate.installMainMenu()

        let appMenu = NSApp.mainMenu?.items.first?.submenu
        let closeItem = appMenu?.items.first { $0.title == AppMenuTitle.closeWindow }
        XCTAssertEqual(closeItem?.action, #selector(NSWindow.performClose(_:)))
        XCTAssertNil(closeItem?.target)
        XCTAssertEqual(closeItem?.keyEquivalent, "w")
        XCTAssertEqual(closeItem?.keyEquivalentModifierMask, [.command])
    }

    private func makeMenuBarController() -> MenuBarController {
        let pinManager = PinManager(
            permissionManager: MockPermissionManager(isTrusted: true),
            windowProvider: MockWindowProvider(focusedWindows: []),
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        return MenuBarController(
            permissionManager: AccessibilityPermissionManager(),
            pinManager: pinManager,
            hotKeyManager: HotKeyManager(),
            onOpenSettings: {}
        )
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

final class HotKeyManagerTests: XCTestCase {
    func testSingleShortcutPressOnlyTogglesOnceUntilRelease() {
        let manager = HotKeyManager()
        var triggerCount = 0
        manager.onHotKey = {
            triggerCount += 1
        }

        manager.simulateHotKeyPressForTesting()
        manager.simulateHotKeyPressForTesting()
        manager.simulateHotKeyPressForTesting()

        XCTAssertEqual(triggerCount, 1)

        manager.simulateHotKeyReleaseForTesting()
        manager.simulateHotKeyPressForTesting()

        XCTAssertEqual(triggerCount, 2)
    }
}

private final class MockPermissionManager: AccessibilityPermissionManaging {
    var isTrusted: Bool
    private(set) var promptCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestPermissionPrompt() {
        promptCount += 1
    }
}

private final class MockWindowProvider: WindowProviding {
    var focusedWindows: [PinnedWindow]
    var refreshResults: [AXError] = []
    var raiseResults: [AXError] = []
    private(set) var refreshCallCount = 0
    var raisedIDs: [UUID] = []

    init(focusedWindows: [PinnedWindow]) {
        self.focusedWindows = focusedWindows
    }

    func focusedWindow() throws -> PinnedWindow {
        focusedWindows.removeFirst()
    }

    func raise(_ pinnedWindow: PinnedWindow) -> AXError {
        raisedIDs.append(pinnedWindow.id)
        if raiseResults.isEmpty {
            return .success
        }
        return raiseResults.removeFirst()
    }

    func refreshSnapshot(for pinnedWindow: PinnedWindow) -> AXError {
        refreshCallCount += 1
        if refreshResults.isEmpty {
            return .success
        }
        return refreshResults.removeFirst()
    }

    func representsSameWindow(_ lhs: PinnedWindow, _ rhs: PinnedWindow) -> Bool {
        lhs.id == rhs.id
    }
}

private final class MockOverlayManager: OverlayManaging {
    private(set) var shownIDs: [UUID] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var removedIDs: [UUID] = []

    func showOverlay(for pinnedWindow: PinnedWindow) {
        shownIDs.append(pinnedWindow.id)
    }

    func updateOverlay(for pinnedWindow: PinnedWindow) {
        updatedIDs.append(pinnedWindow.id)
    }

    func removeOverlay(for id: UUID) {
        removedIDs.append(id)
    }
}

private final class MockAppLogger: AppLogging {
    private(set) var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}
