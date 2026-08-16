import AppKit

enum AppMenuTitle {
    static let settings = "Settings..."
    static let closeWindow = "Close Window"
    static let dockSettings = "設定画面を開く"
    static let dockMenuBarVisibilityToggle = "menubarへの表示非表示切り替え"
    static let quit = "Quit WinPin"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager = AccessibilityPermissionManager()
    private let windowProvider = AXWindowProvider()
    private let overlayManager = BorderOverlayManager()
    private lazy var settingsWindowController = SettingsWindowController()
    private lazy var pinManager = PinManager(
        permissionManager: permissionManager,
        windowProvider: windowProvider,
        overlayManager: overlayManager
    )
    private lazy var hotKeyManager = HotKeyManager()
    private lazy var menuBarController = MenuBarController(
        permissionManager: permissionManager,
        pinManager: pinManager,
        hotKeyManager: hotKeyManager,
        onOpenSettings: { [weak self] in
            self?.showSettings()
        }
    )

    func applicationWillFinishLaunching(_: Notification) {
        NSApp.applicationIconImage = Self.bundleAppIcon() ?? AppIconFactory.makeApplicationIcon()
        let policy: NSApplication.ActivationPolicy = LaunchMode.shouldShowDock ? .regular : .accessory
        AppLogger.shared.log("applicationWillFinishLaunching activationPolicy=\(policy.rawValue)")
        NSApp.setActivationPolicy(policy)
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppLogger.shared.log(
            "applicationDidFinishLaunching args=\(CommandLine.arguments) "
                + "showDockPreference=\(AppPreferences.showDockIcon)"
        )
        installMainMenu()
        configureSettingsWindow()
        menuBarController.start()

        hotKeyManager.onHotKey = { [weak self] in
            self?.pinManager.toggleCurrentWindow(source: .hotKey)
        }
        hotKeyManager.registerDefaultHotKey()
        AppLogger.shared.log(
            "applicationDidFinishLaunching completed activationPolicy=\(NSApp.activationPolicy().rawValue)"
        )
    }

    func applicationWillTerminate(_: Notification) {
        AppLogger.shared.log("applicationWillTerminate")
        hotKeyManager.unregister()
        pinManager.unpinAll()
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        // WinPin does not persist custom restorable state, so explicitly opt in to AppKit's secure restoration path.
        true
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        AppLogger.shared.log("applicationDockMenu requested")
        let menu = NSMenu()

        let settings = NSMenuItem(
            title: AppMenuTitle.dockSettings,
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        let toggleStatusItem = NSMenuItem(
            title: AppMenuTitle.dockMenuBarVisibilityToggle,
            action: #selector(toggleMenuBarItemVisibility),
            keyEquivalent: ""
        )
        toggleStatusItem.target = self
        toggleStatusItem.state = menuBarController.menuBarItemIsVisible ? .on : .off
        menu.addItem(toggleStatusItem)

        let quit = NSMenuItem(title: AppMenuTitle.quit, action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func installMainMenu() {
        AppLogger.shared.log("installMainMenu")
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let settings = NSMenuItem(
            title: AppMenuTitle.settings,
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settings)

        let closeWindow = NSMenuItem(
            title: AppMenuTitle.closeWindow,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeWindow.target = nil
        closeWindow.keyEquivalentModifierMask = [.command]
        appMenu.addItem(closeWindow)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: AppMenuTitle.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureSettingsWindow() {
        settingsWindowController.onDockPreferenceChanged = { [weak self] showDockIcon in
            self?.applyDockPreference(showDockIcon: showDockIcon)
        }
    }

    @objc private func showSettings() {
        AppLogger.shared.log("showSettings")
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyDockPreference(showDockIcon: Bool) {
        AppLogger.shared.log("applyDockPreference showDockIcon=\(showDockIcon)")
        AppPreferences.showDockIcon = showDockIcon
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        DispatchQueue.main.async { [weak self] in
            self?.menuBarController.recreateStatusItem()
        }
    }

    @objc private func toggleMenuBarItemVisibility() {
        AppLogger.shared.log("toggleMenuBarItemVisibility from Dock menu")
        DispatchQueue.main.async { [weak self] in
            self?.menuBarController.toggleMenuBarItemVisibility()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static func bundleAppIcon() -> NSImage? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}
