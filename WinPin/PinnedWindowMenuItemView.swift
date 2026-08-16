import AppKit

extension NSPasteboard.PasteboardType {
    static let winPinPinnedWindowID = NSPasteboard.PasteboardType("com.akis.WinPin.pinned-window-id")
}

final class PinnedWindowMenuItemView: NSView {
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

    fileprivate var dropPlacement: PinManager.MovePlacement? {
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

        unpinButton = NSButton(image: Self.symbolImage("pin.slash") ?? NSImage(), target: nil, action: nil)
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
    required init?(coder _: NSCoder) {
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
        var currentX = Layout.horizontalPadding

        unpinButton.frame = NSRect(
            x: currentX,
            y: actionY,
            width: Layout.actionSize,
            height: Layout.actionSize
        )
        currentX += Layout.actionSize + Layout.gap

        dragIconView.frame = NSRect(x: currentX, y: dragIconY, width: Layout.dragIconSize, height: Layout.dragIconSize)
        currentX += Layout.dragIconSize + Layout.gap

        appIconView.frame = NSRect(x: currentX, y: iconY, width: Layout.iconSize, height: Layout.iconSize)
        currentX += Layout.iconSize + Layout.gap

        let fieldHeight = titleField.intrinsicContentSize.height
        let titleY = (bounds.height - fieldHeight) / 2
        titleField.frame = NSRect(
            x: currentX,
            y: titleY,
            width: max(0, bounds.maxX - Layout.horizontalPadding - currentX),
            height: fieldHeight
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

    override func mouseExited(with _: NSEvent) {
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
        let indicatorY: CGFloat = dropPlacement == .before ? 0 : bounds.height - Layout.dropIndicatorHeight
        NSRect(x: 0, y: indicatorY, width: bounds.width, height: Layout.dropIndicatorHeight).fill()
    }

    @objc private func unpin() {
        onUnpin(windowID)
    }
}

// MARK: - NSDraggingSource & Drag Operations

extension PinnedWindowMenuItemView: NSDraggingSource {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropPlacement(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropPlacement(sender)
    }

    override func draggingExited(_: NSDraggingInfo?) {
        dropPlacement = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropPlacement = nil
        }

        guard let draggedID = draggedWindowID(from: sender),
              draggedID != windowID
        else {
            return false
        }

        let placement = placement(for: sender)
        onMove(draggedID, windowID, placement)
        return true
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
        true
    }

    private func updateDropPlacement(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let draggedID = draggedWindowID(from: sender),
              draggedID != windowID
        else {
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
        symbolImage("hand.pinch")
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
