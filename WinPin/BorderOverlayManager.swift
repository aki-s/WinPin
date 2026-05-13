import AppKit

private enum OverlayConfiguration {
    static let borderWidth: CGFloat = 4
    static let overlayLevel = NSWindow.Level.screenSaver
}

protocol OverlayManaging {
    func showOverlay(for pinnedWindow: PinnedWindow)
    func updateOverlay(for pinnedWindow: PinnedWindow)
    func removeOverlay(for id: UUID)
}

final class BorderOverlayManager: OverlayManaging {
    private var overlays: [UUID: NSPanel] = [:]

    func showOverlay(for pinnedWindow: PinnedWindow) {
        let panel = BorderPanel(contentRect: pinnedWindow.snapshot.frame)
        panel.contentView = BorderView(frame: NSRect(origin: .zero, size: pinnedWindow.snapshot.frame.size))
        overlays[pinnedWindow.id] = panel
        updateOverlay(for: pinnedWindow)
        panel.orderFrontRegardless()
    }

    func updateOverlay(for pinnedWindow: PinnedWindow) {
        guard let panel = overlays[pinnedWindow.id] else {
            return
        }
        panel.setFrame(pinnedWindow.snapshot.frame, display: true)
        panel.orderFrontRegardless()
    }

    func removeOverlay(for id: UUID) {
        guard let panel = overlays.removeValue(forKey: id) else {
            return
        }
        panel.orderOut(nil)
    }
}

private final class BorderPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = OverlayConfiguration.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BorderView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemYellow.setStroke()
        let rect = bounds.insetBy(dx: OverlayConfiguration.borderWidth / 2, dy: OverlayConfiguration.borderWidth / 2)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = OverlayConfiguration.borderWidth
        path.stroke()
    }
}
