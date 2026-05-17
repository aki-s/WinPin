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
        let overlayFrame = AXFrameConverter.appKitFrame(for: pinnedWindow.snapshot.frame)
        let panel = BorderPanel(contentRect: overlayFrame)
        panel.contentView = BorderView(frame: NSRect(origin: .zero, size: overlayFrame.size))
        overlays[pinnedWindow.id] = panel
        updateOverlay(for: pinnedWindow)
        panel.orderFrontRegardless()
    }

    func updateOverlay(for pinnedWindow: PinnedWindow) {
        guard let panel = overlays[pinnedWindow.id] else {
            return
        }
        panel.setFrame(AXFrameConverter.appKitFrame(for: pinnedWindow.snapshot.frame), display: true)
        panel.orderFrontRegardless()
    }

    func removeOverlay(for id: UUID) {
        guard let panel = overlays.removeValue(forKey: id) else {
            return
        }
        panel.orderOut(nil)
    }
}

enum AXFrameConverter {
    static func appKitFrame(for axFrame: CGRect, screens: [CGRect] = NSScreen.screens.map(\.frame)) -> CGRect {
        guard let screen = screen(containingAccessibilityFrame: axFrame, screens: screens) else {
            return axFrame
        }

        return appKitFrame(for: axFrame, in: screen)
    }

    static func appKitFrame(for axFrame: CGRect, in screen: CGRect) -> CGRect {
        CGRect(
            x: axFrame.minX,
            y: screen.maxY - axFrame.maxY + screen.minY,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    private static func screen(containingAccessibilityFrame axFrame: CGRect, screens: [CGRect]) -> CGRect? {
        let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
        return screens.first { $0.contains(center) }
            ?? screens.first { $0.intersects(axFrame) }
            ?? screens.first
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
