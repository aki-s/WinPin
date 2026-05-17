import AppKit

final class MenuBarController: NSObject {
    private enum StatusItemConfiguration {
        static let length: CGFloat = NSStatusItem.variableLength
    }

    enum MenuTitle {
        static let appName = "WinPin"
        static let pinnedWindows = "Pinned Windows"
        static let noPinnedWindows = "No pinned windows"
    }

    private let permissionManager: AccessibilityPermissionManager
    private let pinManager: PinManager
    private let hotKeyManager: HotKeyManager
    private let onOpenSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var isMenuBarItemVisible = true

    init(
        permissionManager: AccessibilityPermissionManager,
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
            self?.refresh()
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
        AppLogger.shared.log("MenuBarController refreshed menu hasStatusItem=\(statusItem != nil) hasButton=\(statusItem?.button != nil) isVisible=\(statusItem?.isVisible ?? false)")
    }

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

        let toggleTitle = permissionManager.isTrusted ? "Pin / Unpin Current Window" : "Pinning Disabled Until Accessibility Is Allowed"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleCurrentWindow), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = permissionManager.isTrusted
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        addPinnedWindowItems(to: menu)

        menu.addItem(.separator())
        addStatusItems(to: menu)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: AppMenuTitle.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: AppMenuTitle.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addPermissionItems(to menu: NSMenu) {
        if permissionManager.isTrusted {
            let item = NSMenuItem(title: "Accessibility: Allowed", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let status = NSMenuItem(title: "Accessibility: Required", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let prompt = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        prompt.target = self
        menu.addItem(prompt)

        let settings = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
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

        for window in pinManager.pinnedWindows {
            let item = NSMenuItem(
                title: "\(window.snapshot.appName) - \(window.snapshot.windowTitle)    Pinned",
                action: #selector(unpinWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = window.id
            item.image = window.appIcon
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

    @objc private func unpinWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else {
            return
        }
        pinManager.unpin(id: id)
    }

    @objc private func requestAccessibilityPermission() {
        permissionManager.requestPermissionPrompt()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
