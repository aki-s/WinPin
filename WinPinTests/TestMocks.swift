import AppKit
import ApplicationServices
@testable import WinPin

final class MockPermissionManager: AccessibilityPermissionManaging {
    var isTrusted: Bool
    private(set) var promptCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestPermissionPrompt() {
        promptCount += 1
    }
}

final class MockWindowProvider: WindowProviding {
    var focusedWindows: [PinnedWindow]
    var refreshResults: [AXError] = []
    var raiseResults: [AXError] = []
    var frontmostProcessIdentifier: pid_t?
    var refreshHandler: ((PinnedWindow) -> Void)?
    private(set) var refreshCallCount = 0
    var raisedIDs: [UUID] = []

    init(focusedWindows: [PinnedWindow]) {
        self.focusedWindows = focusedWindows
    }

    func focusedWindow() throws -> PinnedWindow {
        focusedWindows.removeFirst()
    }

    func raise(_ pinnedWindow: PinnedWindow) -> AXError {
        raisedIDs.append(pinnedWindow.id)
        if raiseResults.isEmpty {
            return .success
        }
        return raiseResults.removeFirst()
    }

    func refreshSnapshot(for pinnedWindow: PinnedWindow) -> AXError {
        refreshCallCount += 1
        let result: AXError
        if refreshResults.isEmpty {
            result = .success
        } else {
            result = refreshResults.removeFirst()
        }
        if result == .success {
            refreshHandler?(pinnedWindow)
        }
        return result
    }

    func frontmostExternalApplicationProcessIdentifier() -> pid_t? {
        frontmostProcessIdentifier
    }

    func representsSameWindow(_ lhs: PinnedWindow, _ rhs: PinnedWindow) -> Bool {
        lhs.id == rhs.id
    }
}

final class MockOverlayManager: OverlayManaging {
    private(set) var shownIDs: [UUID] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var removedIDs: [UUID] = []

    func showOverlay(for pinnedWindow: PinnedWindow) {
        shownIDs.append(pinnedWindow.id)
    }

    func updateOverlay(for pinnedWindow: PinnedWindow) {
        updatedIDs.append(pinnedWindow.id)
    }

    func removeOverlay(for id: UUID) {
        removedIDs.append(id)
    }
}

final class MockAppLogger: AppLogging {
    private(set) var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

final class MockAXWindowActionPerformer: AXWindowActionPerforming {
    private var results: [AXError]
    private(set) var raiseCallCount = 0
    private(set) var raisedElements: [AXUIElement] = []

    init(results: [AXError]) {
        self.results = results
    }

    func performRaiseAction(on element: AXUIElement) -> AXError {
        raiseCallCount += 1
        raisedElements.append(element)
        guard !results.isEmpty else {
            return .success
        }
        return results.removeFirst()
    }
}

func makeTestWindow(
    title: String,
    pid: pid_t = 100,
    axRole: String? = nil,
    supportedActions: [String] = []
) -> PinnedWindow {
    let id = UUID()
    let snapshot = AXWindowSnapshot(
        id: id,
        pid: pid,
        bundleIdentifier: "com.example.\(title)",
        appName: "App \(title)",
        windowTitle: title,
        frame: CGRect(x: 10, y: 20, width: 300, height: 200),
        axRole: axRole,
        supportedActions: supportedActions
    )
    return PinnedWindow(
        id: id,
        axElement: AXUIElementCreateSystemWide(),
        snapshot: snapshot,
        appIcon: nil
    )
}
