import AppKit
import ApplicationServices

struct AXWindowSnapshot: Hashable {
    let id: UUID
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let windowTitle: String
    let frame: CGRect
    let axRole: String?
    let supportedActions: [String]

    init(
        id: UUID,
        pid: pid_t,
        bundleIdentifier: String?,
        appName: String,
        windowTitle: String,
        frame: CGRect,
        axRole: String? = nil,
        supportedActions: [String] = []
    ) {
        self.id = id
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.axRole = axRole
        self.supportedActions = supportedActions
    }
}

final class PinnedWindow {
    let id: UUID
    let axElement: AXUIElement
    var snapshot: AXWindowSnapshot
    var appIcon: NSImage?
    var isStale: Bool
    var maintenanceFailureCount: Int
    var raiseFailureCount: Int

    init(
        id: UUID = UUID(),
        axElement: AXUIElement,
        snapshot: AXWindowSnapshot,
        appIcon: NSImage?,
        isStale: Bool = false,
        maintenanceFailureCount: Int = 0,
        raiseFailureCount: Int = 0
    ) {
        self.id = id
        self.axElement = axElement
        self.snapshot = snapshot
        self.appIcon = appIcon
        self.isStale = isStale
        self.maintenanceFailureCount = maintenanceFailureCount
        self.raiseFailureCount = raiseFailureCount
    }
}
