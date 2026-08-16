import AppKit
@testable import WinPin
import XCTest

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
        let window = makeTestWindow(title: "Pinned")
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
        let window = makeTestWindow(title: "Pinned")
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
}
