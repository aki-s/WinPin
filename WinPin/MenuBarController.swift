import AppKit

final class MenuBarController: NSObject {
    private enum StatusItemConfiguration {
        static let length: CGFloat = NSStatusItem.variableLength
    }

    private enum MenuSymbol {
        static let pin = "pin"
        static let trash = "trash"
        static let settings = "gearshape"
        static let quit = "power"
    }

    enum MenuTitle {
        static let appName = "WinPin"
        static let pinnedWindows = "Pinned Windows"
        static let noPinnedWindows = "No pinned windows"
        static let unpinAll = "Unpin All"
    }

    private let permissionManager: AccessibilityPermissionManaging
    private let pinManager: PinManager
    private let hotKeyManager: HotKeyManager
    private let onOpenSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var isMenuBarItemVisible = true
    private var suppressMenuRefresh = false

    init(
        permissionManager: AccessibilityPermissionManaging,
        pinManager: PinManager,
        hotKeyManager: HotKeyManager,
        onOpenSettings: @escaping () -> Void
    ) {
        self.permissionManager = permissionManager
        self.pinManager = pinManager
        self.hotKeyManager = hotKeyManager
        self.onOpenSettings = onOpenSettings
        super.init()
        self.pinManager.onChange = { [weak self] in
            guard let self, !self.suppressMenuRefresh else {
                return
            }
            self.refresh()
        }
    }

    func start() {
        setMenuBarItemVisible(AppPreferences.showMenuBarItem)
    }

    func setMenuBarItemVisible(_ isVisible: Bool) {
        AppPreferences.showMenuBarItem = isVisible
        isMenuBarItemVisible = isVisible

        guard isVisible else {
            removeStatusItem()
            AppLogger.shared.log("MenuBarController hid status item")
            return
        }

        if statusItem == nil {
            AppLogger.shared.log("MenuBarController creating status item")
            statusItem = NSStatusBar.system.statusItem(withLength: StatusItemConfiguration.length)
            statusItem?.autosaveName = "WinPin"
        }

        guard let statusItem else {
            AppLogger.shared.log("MenuBarController failed to create status item")
            return
        }

        statusItem.length = StatusItemConfiguration.length
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.title = AppIconFactory.symbol
            button.image = nil
            button.toolTip = "WinPin"
        } else {
            AppLogger.shared.log("MenuBarController status item has no button")
        }
        refresh()
    }

    func toggleMenuBarItemVisibility() {
        setMenuBarItemVisible(!isMenuBarItemVisible)
    }

    var menuBarItemIsVisible: Bool {
        isMenuBarItemVisible
    }

    var statusItemIsInstalledForTesting: Bool {
        statusItem != nil
    }

    func menuItemsForTesting() -> [NSMenuItem] {
        buildMenu().items
    }

    func recreateStatusItem() {
        AppLogger.shared.log("MenuBarController recreating status item")
        removeStatusItem()
        start()
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func refresh() {
        statusItem?.menu = buildMenu()
        let hasItem = statusItem != nil
        let hasButton = statusItem?.button != nil
        let isVisible = statusItem?.isVisible ?? false
        AppLogger.shared.log(
            "MenuBarController refreshed menu hasStatusItem=\(hasItem) hasButton=\(hasButton) isVisible=\(isVisible)"
        )
    }
}

// MARK: - Menu Construction & Actions

extension MenuBarController {
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: MenuTitle.appName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let limitation = NSMenuItem(
            title: "Best effort: pinned windows are repeatedly raised, not truly always on top.",
            action: nil,
            keyEquivalent: ""
        )
        limitation.isEnabled = false
        menu.addItem(limitation)
        menu.addItem(.separator())

        addPermissionItems(to: menu)

        if permissionManager.isTrusted {
            let toggleItem = NSMenuItem(
                title: "Pin / Unpin Current Window",
                action: #selector(toggleCurrentWindow),
                keyEquivalent: ""
            )
            toggleItem.target = self
            toggleItem.image = Self.symbolImage(MenuSymbol.pin)
            toggleItem.toolTip = "Pin or unpin the focused window"
            menu.addItem(toggleItem)
        }

        menu.addItem(.separator())
        addPinnedWindowItems(to: menu)

        menu.addItem(.separator())
        addStatusItems(to: menu)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: AppMenuTitle.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.symbolImage(MenuSymbol.settings)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: AppMenuTitle.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = Self.symbolImage(MenuSymbol.quit)
        menu.addItem(quitItem)

        return menu
    }

    private func addPermissionItems(to menu: NSMenu) {
        if permissionManager.isTrusted {
            let item = NSMenuItem(title: "Accessibility: Allowed", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.symbolImage("checkmark.seal")
            menu.addItem(item)
            return
        }

        let status = NSMenuItem(title: "Accessibility: Required", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.image = Self.symbolImage("xmark.seal")
        menu.addItem(status)

        let prompt = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        prompt.target = self
        prompt.image = Self.symbolImage("accessibility")
        menu.addItem(prompt)
    }

    private func addPinnedWindowItems(to menu: NSMenu) {
        let header = NSMenuItem(title: MenuTitle.pinnedWindows, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        guard !pinManager.pinnedWindows.isEmpty else {
            let empty = NSMenuItem(title: MenuTitle.noPinnedWindows, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let unpinAllItem = NSMenuItem(title: MenuTitle.unpinAll, action: #selector(unpinAll), keyEquivalent: "")
        unpinAllItem.target = self
        unpinAllItem.image = Self.symbolImage(MenuSymbol.trash)
        unpinAllItem.toolTip = "Unpin all pinned windows"
        menu.addItem(unpinAllItem)

        for window in pinManager.pinnedWindows {
            let item = NSMenuItem()
            item.representedObject = window.id
            item.view = PinnedWindowMenuItemView(
                window: window,
                onUnpin: { [weak self, weak menu] id in
                    self?.pinManager.unpin(id: id)
                    menu?.cancelTracking()
                },
                onMove: { [weak self, weak menu] draggedID, targetID, placement in
                    self?.movePinnedWindow(draggedID, relativeTo: targetID, placement: placement, in: menu)
                }
            )
            menu.addItem(item)
        }
    }

    private func addStatusItems(to menu: NSMenu) {
        let shortcutStatus = hotKeyManager.registrationError ?? "Shortcut: \(HotKeyManager.defaultShortcutDisplayName)"
        let shortcutItem = NSMenuItem(title: shortcutStatus, action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        if let message = pinManager.lastMessage {
            let messageItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            messageItem.isEnabled = false
            menu.addItem(messageItem)
        }
    }

    @objc private func toggleCurrentWindow() {
        pinManager.toggleCurrentWindow(source: .menu)
    }

    @objc private func unpinAll() {
        pinManager.unpinAll()
    }

    @objc private func requestAccessibilityPermission() {
        permissionManager.requestPermissionPrompt()
        refresh()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func movePinnedWindow(
        _ draggedID: UUID,
        relativeTo targetID: UUID,
        placement: PinManager.MovePlacement,
        in menu: NSMenu?
    ) {
        suppressMenuRefresh = true
        pinManager.movePinnedWindow(id: draggedID, relativeTo: targetID, placement: placement)
        suppressMenuRefresh = false

        guard let menu else {
            refresh()
            return
        }
        reorderPinnedWindowItems(in: menu)
    }

    private func reorderPinnedWindowItems(in menu: NSMenu) {
        guard let headerIndex = menu.items.firstIndex(where: { $0.title == MenuTitle.pinnedWindows }) else {
            return
        }

        var insertionIndex = headerIndex + 1
        let isUnpinAll = menu.items.indices.contains(insertionIndex)
            && menu.items[insertionIndex].title == MenuTitle.unpinAll
        if isUnpinAll {
            insertionIndex += 1
        }

        let sectionEndIndex = menu.items[insertionIndex...].firstIndex(where: \.isSeparatorItem) ?? menu.items.count
        guard insertionIndex < sectionEndIndex else {
            return
        }

        var pinnedItemsByID: [UUID: NSMenuItem] = [:]
        for item in menu.items[insertionIndex ..< sectionEndIndex] {
            guard let id = item.representedObject as? UUID else {
                continue
            }
            pinnedItemsByID[id] = item
        }

        for index in stride(from: sectionEndIndex - 1, through: insertionIndex, by: -1) {
            menu.removeItem(at: index)
        }

        for (offset, window) in pinManager.pinnedWindows.enumerated() {
            guard let item = pinnedItemsByID[window.id] else {
                continue
            }
            menu.insertItem(item, at: insertionIndex + offset)
        }
        menu.update()
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
