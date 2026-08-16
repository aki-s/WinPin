import ApplicationServices
@testable import WinPin
import XCTest

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

    func testChangeNotificationHappensAfterUnpinMessageIsUpdated() {
        let window = makeWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        var observedMessages: [String?] = []
        manager.onChange = {
            observedMessages.append(manager.lastMessage)
        }

        manager.toggleCurrentWindow()
        manager.unpin(id: window.id)

        XCTAssertEqual(observedMessages, [
            "Pinned App Pinned - Pinned.",
            "No pinned windows.",
        ])
    }

    func testUnpinAllRemovesAllPinnedWindowsAndUpdatesMessage() {
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
        var observedMessages: [String?] = []
        manager.onChange = {
            observedMessages.append(manager.lastMessage)
        }

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        manager.unpinAll()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [])
        XCTAssertEqual(overlay.removedIDs, [second.id, first.id])
        XCTAssertEqual(observedMessages.last, "No pinned windows.")
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
            "pin_failed reason=accessibility_permission_missing source=hotkey",
        ])
    }

    func testMaintenanceRaisesPinnedWindowsFromBottomToTop() {
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

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [first.id, second.id])
    }

    func testMaintenanceSkipsPinnedWindowsFromFrontmostApplicationPID() {
        let first = makeWindow(title: "First", pid: 100)
        let second = makeWindow(title: "Second", pid: 100)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 100
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

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [second.id, first.id])
        XCTAssertEqual(overlay.updatedIDs, [second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [])
    }

    func testMaintenanceStillRaisesNonFrontmostApplicationsFromBottomToTop() {
        let first = makeWindow(title: "First", pid: 100)
        let second = makeWindow(title: "Second", pid: 200)
        let third = makeWindow(title: "Third", pid: 300)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second, third])
        provider.frontmostProcessIdentifier = 200
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [third.id, second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [first.id, third.id])
    }

    func testMaintenanceBacksOffAfterThreeIdenticalSuccessfulRaiseSequences() {
        let first = makeWindow(title: "First", pid: 100)
        let second = makeWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_started")
                && $0.contains("consecutive_successes=3")
                && $0.contains("frontmost_external_pid=999")
        })
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_attempted") })
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_succeeded operation=maintenance") })
    }

    func testMaintenanceDoesNotBackOffSinglePinnedWindow() {
        let window = makeWindow(title: "Pinned", pid: 100)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [window.id, window.id, window.id, window.id])
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_backoff_started") })
    }

    func testMaintenanceBackoffResumesWhenFrontmostApplicationChanges() {
        let first = makeWindow(title: "First", pid: 100)
        let second = makeWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        provider.frontmostProcessIdentifier = 998
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_resumed reason=frontmost_application_changed")
        })
    }

    func testMaintenanceBackoffResumesWhenWindowSnapshotChanges() {
        let first = makeWindow(title: "First", pid: 100)
        let second = makeWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )
        var shouldMoveFirstWindow = false
        provider.refreshHandler = { window in
            guard shouldMoveFirstWindow, window.id == first.id else {
                return
            }
            let old = window.snapshot
            window.snapshot = AXWindowSnapshot(
                id: old.id,
                pid: old.pid,
                bundleIdentifier: old.bundleIdentifier,
                appName: old.appName,
                windowTitle: old.windowTitle,
                frame: CGRect(x: 30, y: 40, width: 300, height: 200),
                axRole: old.axRole,
                supportedActions: old.supportedActions
            )
        }

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        shouldMoveFirstWindow = true
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_resumed reason=window_snapshot_changed")
        })
    }

    func testMovePinnedWindowChangesRaiseOrder() {
        let first = makeWindow(title: "First")
        let second = makeWindow(title: "Second")
        let third = makeWindow(title: "Third")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second, third])
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.movePinnedWindow(id: first.id, relativeTo: third.id, placement: .before)

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(provider.raisedIDs, [second.id, third.id, first.id])
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

final class AXWindowProviderTests: XCTestCase {
    func testRaiseReturnsAXRaiseFailureWithoutRetryingFallback() {
        let window = makeWindow(title: "Pinned")
        let actionPerformer = MockAXWindowActionPerformer(results: [.failure])
        let provider = AXWindowProvider(actionPerformer: actionPerformer)

        let error = provider.raise(window)

        XCTAssertEqual(error, .failure)
        XCTAssertEqual(actionPerformer.raiseCallCount, 1)
        XCTAssertEqual(actionPerformer.raisedElements.count, 1)
        XCTAssertTrue(CFEqual(actionPerformer.raisedElements[0], window.axElement))
    }

    private func makeWindow(title: String) -> PinnedWindow {
        let id = UUID()
        let snapshot = AXWindowSnapshot(
            id: id,
            pid: 100,
            bundleIdentifier: "com.example.\(title)",
            appName: "App \(title)",
            windowTitle: title,
            frame: CGRect(x: 10, y: 20, width: 300, height: 200)
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

    func testAccessibilityFrameIsConvertedToAppKitFrameForBottomHalfWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1106)
        let accessibilityFrame = CGRect(x: 0, y: 570, width: 1710, height: 536)

        let appKitFrame = AXFrameConverter.appKitFrame(for: accessibilityFrame, screens: [screen])

        XCTAssertEqual(appKitFrame, CGRect(x: 0, y: 0, width: 1710, height: 536))
    }

    func testAccessibilityFrameIsConvertedToAppKitFrameForTopHalfWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1106)
        let accessibilityFrame = CGRect(x: 0, y: 0, width: 1710, height: 536)

        let appKitFrame = AXFrameConverter.appKitFrame(for: accessibilityFrame, screens: [screen])

        XCTAssertEqual(appKitFrame, CGRect(x: 0, y: 570, width: 1710, height: 536))
    }

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

    func testMenuBarMenuShowsOneAccessibilityActionWhenPermissionIsMissing() {
        let manager = makeMenuBarController(permissionIsTrusted: false)
        let items = manager.menuItemsForTesting()

        XCTAssertNotNil(items.first { $0.title == "Accessibility: Required" })
        XCTAssertEqual(items.filter { $0.title == "Request Accessibility Permission" }.count, 1)
        XCTAssertNil(items.first { $0.title == "Open Accessibility Settings" })
        XCTAssertNil(items.first { $0.title == "Pinning Disabled Until Accessibility Is Allowed" })
        XCTAssertNil(items.first { $0.title == "Pin / Unpin Current Window" })
    }

    func testMenuBarMenuShowsUnpinAllWhenWindowsArePinned() {
        let window = makeWindow(title: "Pinned")
        let permissionManager = MockPermissionManager(isTrusted: true)
        let pinManager = PinManager(
            permissionManager: permissionManager,
            windowProvider: MockWindowProvider(focusedWindows: [window]),
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        pinManager.toggleCurrentWindow()
        let manager = MenuBarController(
            permissionManager: permissionManager,
            pinManager: pinManager,
            hotKeyManager: HotKeyManager(),
            onOpenSettings: {}
        )

        let items = manager.menuItemsForTesting()

        XCTAssertNotNil(items.first { $0.title == MenuBarController.MenuTitle.unpinAll })
    }

    func testMenuBarPinnedWindowRowsUseCustomDragViews() throws {
        let window = makeWindow(title: "Pinned")
        let permissionManager = MockPermissionManager(isTrusted: true)
        let pinManager = PinManager(
            permissionManager: permissionManager,
            windowProvider: MockWindowProvider(focusedWindows: [window]),
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        pinManager.toggleCurrentWindow()
        let manager = MenuBarController(
            permissionManager: permissionManager,
            pinManager: pinManager,
            hotKeyManager: HotKeyManager(),
            onOpenSettings: {}
        )

        let items = manager.menuItemsForTesting()
        let row = items.first { $0.representedObject as? UUID == window.id }
        let unpinAll = items.first { $0.title == MenuBarController.MenuTitle.unpinAll }
        let rowView = try XCTUnwrap(row?.view)
        rowView.layout()
        let trashButton = try XCTUnwrap(rowView.subviews.first {
            $0.identifier?.rawValue == "PinnedWindowMenuItemTrashButton"
        })
        let dragIcon = try XCTUnwrap(rowView.subviews.first {
            $0.identifier?.rawValue == "PinnedWindowMenuItemDragIcon"
        } as? NSImageView)
        let appIcon = try XCTUnwrap(rowView.subviews.first {
            $0.identifier?.rawValue == "PinnedWindowMenuItemAppIcon"
        })

        XCTAssertEqual(rowView.identifier?.rawValue, "PinnedWindowMenuItemView")
        XCTAssertTrue(rowView.toolTip?.contains("Drag to reorder") == true)
        XCTAssertLessThan(trashButton.frame.minX, dragIcon.frame.minX)
        XCTAssertLessThan(dragIcon.frame.minX, appIcon.frame.minX)
        XCTAssertNotNil(dragIcon.image)
        XCTAssertNotNil(unpinAll?.image)
    }

    func testMenuBarMenuHidesUnpinAllWhenNoWindowsArePinned() {
        let manager = makeMenuBarController()
        let items = manager.menuItemsForTesting()

        XCTAssertNil(items.first { $0.title == MenuBarController.MenuTitle.unpinAll })
    }

    func testDockMenuListsRequiredRecoveryActions() {
        let appDelegate = AppDelegate()
        let menu = appDelegate.applicationDockMenu(NSApp)

        XCTAssertEqual(menu?.items.map(\.title), [
            AppMenuTitle.dockSettings,
            AppMenuTitle.dockMenuBarVisibilityToggle,
            AppMenuTitle.quit,
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

    private func makeMenuBarController(permissionIsTrusted: Bool = true) -> MenuBarController {
        let permissionManager = MockPermissionManager(isTrusted: permissionIsTrusted)
        let pinManager = PinManager(
            permissionManager: permissionManager,
            windowProvider: MockWindowProvider(focusedWindows: []),
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        return MenuBarController(
            permissionManager: permissionManager,
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

    private func makeWindow(title: String) -> PinnedWindow {
        let id = UUID()
        let snapshot = AXWindowSnapshot(
            id: id,
            pid: 100,
            bundleIdentifier: "com.example.\(title)",
            appName: "App \(title)",
            windowTitle: title,
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            axRole: nil,
            supportedActions: []
        )
        return PinnedWindow(
            id: id,
            axElement: AXUIElementCreateSystemWide(),
            snapshot: snapshot,
            appIcon: nil
        )
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
    var frontmostProcessIdentifier: pid_t?
    var refreshHandler: ((PinnedWindow) -> Void)?
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
        let result: AXError
        if refreshResults.isEmpty {
            result = .success
        } else {
            result = refreshResults.removeFirst()
        }
        if result == .success {
            refreshHandler?(pinnedWindow)
        }
        return result
    }

    func frontmostExternalApplicationProcessIdentifier() -> pid_t? {
        frontmostProcessIdentifier
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

private final class MockAXWindowActionPerformer: AXWindowActionPerforming {
    private var results: [AXError]
    private(set) var raiseCallCount = 0
    private(set) var raisedElements: [AXUIElement] = []

    init(results: [AXError]) {
        self.results = results
    }

    func performRaiseAction(on element: AXUIElement) -> AXError {
        raiseCallCount += 1
        raisedElements.append(element)
        guard !results.isEmpty else {
            return .success
        }
        return results.removeFirst()
    }
}
