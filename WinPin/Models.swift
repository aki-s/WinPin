import AppKit
import ApplicationServices

struct AXWindowSnapshot: Hashable {
    let id: UUID
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let windowTitle: String
    let frame: CGRect
}

final class PinnedWindow {
    let id: UUID
    let axElement: AXUIElement
    var snapshot: AXWindowSnapshot
    var appIcon: NSImage?
    var isStale: Bool
    var maintenanceFailureCount: Int

    init(
        id: UUID = UUID(),
        axElement: AXUIElement,
        snapshot: AXWindowSnapshot,
        appIcon: NSImage?,
        isStale: Bool = false,
        maintenanceFailureCount: Int = 0
    ) {
        self.id = id
        self.axElement = axElement
        self.snapshot = snapshot
        self.appIcon = appIcon
        self.isStale = isStale
        self.maintenanceFailureCount = maintenanceFailureCount
    }
}
