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

        if permissionManager.isTrusted {
            let toggleItem = NSMenuItem(title: "Pin / Unpin Current Window", action: #selector(toggleCurrentWindow), keyEquivalent: "")
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
            menu.addItem(item)
            return
        }

        let status = NSMenuItem(title: "Accessibility: Required", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let prompt = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        prompt.target = self
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
        if menu.items.indices.contains(insertionIndex),
           menu.items[insertionIndex].title == MenuTitle.unpinAll {
            insertionIndex += 1
        }

        let sectionEndIndex = menu.items[insertionIndex...].firstIndex(where: \.isSeparatorItem) ?? menu.items.count
        guard insertionIndex < sectionEndIndex else {
            return
        }

        var pinnedItemsByID: [UUID: NSMenuItem] = [:]
        for item in menu.items[insertionIndex..<sectionEndIndex] {
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

private extension NSPasteboard.PasteboardType {
    static let winPinPinnedWindowID = NSPasteboard.PasteboardType("com.akis.WinPin.pinned-window-id")
}

private final class PinnedWindowMenuItemView: NSView, NSDraggingSource {
    private enum Layout {
        static let rowSize = NSSize(width: 520, height: 34)
        static let horizontalPadding: CGFloat = 8
        static let dragIconSize: CGFloat = 18
        static let iconSize: CGFloat = 22
        static let actionSize: CGFloat = 24
        static let gap: CGFloat = 8
        static let dropIndicatorHeight: CGFloat = 2
    }

    private let windowID: UUID
    private let titleField: NSTextField
    private let appIconView: NSImageView
    private let dragIconView: NSImageView
    private let unpinButton: NSButton
    private let onUnpin: (UUID) -> Void
    private let onMove: (UUID, UUID, PinManager.MovePlacement) -> Void
    private var mouseDownPoint: NSPoint?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }
    private var dropPlacement: PinManager.MovePlacement? {
        didSet {
            needsDisplay = true
        }
    }

    init(
        window: PinnedWindow,
        onUnpin: @escaping (UUID) -> Void,
        onMove: @escaping (UUID, UUID, PinManager.MovePlacement) -> Void
    ) {
        windowID = window.id
        self.onUnpin = onUnpin
        self.onMove = onMove

        dragIconView = NSImageView(image: Self.dragIcon())
        dragIconView.identifier = NSUserInterfaceItemIdentifier("PinnedWindowMenuItemDragIcon")
        dragIconView.imageScaling = .scaleProportionallyDown
        dragIconView.toolTip = "Drag to reorder"
        dragIconView.setAccessibilityLabel("Drag to reorder")

        appIconView = NSImageView(image: window.appIcon ?? Self.symbolImage("macwindow") ?? NSImage())
        appIconView.identifier = NSUserInterfaceItemIdentifier("PinnedWindowMenuItemAppIcon")
        appIconView.imageScaling = .scaleProportionallyDown

        let title = "\(window.snapshot.appName) - \(window.snapshot.windowTitle)"
        titleField = NSTextField(labelWithString: title)
        titleField.font = .menuFont(ofSize: 0)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.toolTip = title

        unpinButton = NSButton(image: Self.symbolImage("trash") ?? NSImage(), target: nil, action: nil)
        unpinButton.identifier = NSUserInterfaceItemIdentifier("PinnedWindowMenuItemTrashButton")
        unpinButton.bezelStyle = .regularSquare
        unpinButton.isBordered = false
        unpinButton.imagePosition = .imageOnly
        unpinButton.toolTip = "Unpin"
        unpinButton.setAccessibilityLabel("Unpin")

        super.init(frame: NSRect(origin: .zero, size: Layout.rowSize))

        identifier = NSUserInterfaceItemIdentifier("PinnedWindowMenuItemView")
        toolTip = "Drag to reorder. Higher rows are raised above lower rows."
        registerForDraggedTypes([.winPinPinnedWindowID])

        unpinButton.target = self
        unpinButton.action = #selector(unpin)

        addSubview(unpinButton)
        addSubview(dragIconView)
        addSubview(appIconView)
        addSubview(titleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()

        let iconY = (bounds.height - Layout.iconSize) / 2
        let dragIconY = (bounds.height - Layout.dragIconSize) / 2
        let actionY = (bounds.height - Layout.actionSize) / 2
        var x = Layout.horizontalPadding

        unpinButton.frame = NSRect(
            x: x,
            y: actionY,
            width: Layout.actionSize,
            height: Layout.actionSize
        )
        x += Layout.actionSize + Layout.gap

        dragIconView.frame = NSRect(x: x, y: dragIconY, width: Layout.dragIconSize, height: Layout.dragIconSize)
        x += Layout.dragIconSize + Layout.gap

        appIconView.frame = NSRect(x: x, y: iconY, width: Layout.iconSize, height: Layout.iconSize)
        x += Layout.iconSize + Layout.gap

        titleField.frame = NSRect(
            x: x,
            y: 0,
            width: max(0, bounds.maxX - Layout.horizontalPadding - x),
            height: bounds.height
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(dragSourceRect, cursor: .openHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(for: event).set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        cursor(for: event).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: event).set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if unpinButton.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }
        NSCursor.closedHand.set()
        mouseDownPoint = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) >= 3 else {
            return
        }

        self.mouseDownPoint = nil
        beginDraggingSession(with: [draggingItem()], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        cursor(for: event).set()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropPlacement(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropPlacement(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropPlacement = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropPlacement = nil
        }

        guard let draggedID = draggedWindowID(from: sender),
              draggedID != windowID else {
            return false
        }

        let placement = placement(for: sender)
        onMove(draggedID, windowID, placement)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
            bounds.fill()
        }

        guard let dropPlacement else {
            return
        }

        NSColor.controlAccentColor.setFill()
        let y: CGFloat = dropPlacement == .before ? 0 : bounds.height - Layout.dropIndicatorHeight
        NSRect(x: 0, y: y, width: bounds.width, height: Layout.dropIndicatorHeight).fill()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    @objc private func unpin() {
        onUnpin(windowID)
    }

    private func updateDropPlacement(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let draggedID = draggedWindowID(from: sender),
              draggedID != windowID else {
            dropPlacement = nil
            return []
        }

        dropPlacement = placement(for: sender)
        return .move
    }

    private func placement(for sender: NSDraggingInfo) -> PinManager.MovePlacement {
        let point = convert(sender.draggingLocation, from: nil)
        return point.y < bounds.midY ? .before : .after
    }

    private func draggedWindowID(from sender: NSDraggingInfo) -> UUID? {
        guard let value = sender.draggingPasteboard.string(forType: .winPinPinnedWindowID) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private func draggingItem() -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(windowID.uuidString, forType: .winPinPinnedWindowID)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(bounds, contents: dragPreviewImage())
        return item
    }

    private func dragPreviewImage() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private static func dragIcon() -> NSImage {
        symbolImage("hand.draw")
            ?? symbolImage("hand.point.up.left")
            ?? symbolImage("line.3.horizontal")
            ?? NSImage()
    }

    private var dragSourceRect: NSRect {
        bounds.divided(atDistance: unpinButton.frame.maxX + Layout.gap, from: .minXEdge).remainder
    }

    private func cursor(for event: NSEvent) -> NSCursor {
        let point = convert(event.locationInWindow, from: nil)
        return unpinButton.frame.contains(point) ? .arrow : .openHand
    }
}
