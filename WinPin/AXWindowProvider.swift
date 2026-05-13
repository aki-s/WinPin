import AppKit
import ApplicationServices

enum AXWindowProviderError: LocalizedError {
    case focusedApplicationUnavailable
    case focusedWindowUnavailable
    case pidUnavailable
    case frameUnavailable

    var errorDescription: String? {
        switch self {
        case .focusedApplicationUnavailable:
            return "WinPin could not read the focused application."
        case .focusedWindowUnavailable:
            return "WinPin could not read the focused window."
        case .pidUnavailable:
            return "WinPin could not identify the focused window's process."
        case .frameUnavailable:
            return "WinPin could not read the focused window frame."
        }
    }
}

protocol WindowProviding {
    func focusedWindow() throws -> PinnedWindow
    func raise(_ pinnedWindow: PinnedWindow) -> AXError
    func refreshSnapshot(for pinnedWindow: PinnedWindow) -> AXError
    func representsSameWindow(_ lhs: PinnedWindow, _ rhs: PinnedWindow) -> Bool
}

final class AXWindowProvider: WindowProviding {
    func focusedWindow() throws -> PinnedWindow {
        let systemWide = AXUIElementCreateSystemWide()
        let focusedApp: AXUIElement = try copyAttribute(kAXFocusedApplicationAttribute, from: systemWide)
        let focusedWindow: AXUIElement = try copyAttribute(kAXFocusedWindowAttribute, from: focusedApp)

        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedWindow, &pid) == .success, pid > 0 else {
            throw AXWindowProviderError.pidUnavailable
        }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let title = stringAttribute(kAXTitleAttribute, from: focusedWindow) ?? "Untitled Window"
        let frame = try windowFrame(for: focusedWindow)
        let appName = runningApp?.localizedName ?? "Unknown App"
        let bundleIdentifier = runningApp?.bundleIdentifier

        let snapshot = AXWindowSnapshot(
            id: UUID(),
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: title.isEmpty ? "Untitled Window" : title,
            frame: frame
        )

        return PinnedWindow(axElement: focusedWindow, snapshot: snapshot, appIcon: runningApp?.icon)
    }

    func raise(_ pinnedWindow: PinnedWindow) -> AXError {
        // This is best effort. macOS does not expose a public always-on-top flag
        // for another app's existing window, so WinPin repeatedly raises the
        // specific AX window instead of activating its whole application.
        AXUIElementPerformAction(pinnedWindow.axElement, kAXRaiseAction as CFString)
    }

    func refreshSnapshot(for pinnedWindow: PinnedWindow) -> AXError {
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(pinnedWindow.axElement, &pid)
        guard pidError == .success, pid == pinnedWindow.snapshot.pid else {
            return pidError == .success ? .failure : pidError
        }

        guard let frame = try? windowFrame(for: pinnedWindow.axElement) else {
            return .failure
        }

        let title = stringAttribute(kAXTitleAttribute, from: pinnedWindow.axElement)
        let old = pinnedWindow.snapshot
        pinnedWindow.snapshot = AXWindowSnapshot(
            id: old.id,
            pid: old.pid,
            bundleIdentifier: old.bundleIdentifier,
            appName: old.appName,
            windowTitle: title?.isEmpty == false ? title! : old.windowTitle,
            frame: frame
        )
        return .success
    }

    func representsSameWindow(_ lhs: PinnedWindow, _ rhs: PinnedWindow) -> Bool {
        guard lhs.snapshot.pid == rhs.snapshot.pid else {
            return false
        }

        if CFEqual(lhs.axElement, rhs.axElement) {
            return true
        }

        let left = lhs.snapshot
        let right = rhs.snapshot
        return left.bundleIdentifier == right.bundleIdentifier
            && left.windowTitle == right.windowTitle
            && left.frame.equalTo(right.frame)
    }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement) throws -> T {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let typedValue = value as? T else {
            if attribute == kAXFocusedApplicationAttribute {
                throw AXWindowProviderError.focusedApplicationUnavailable
            }
            if attribute == kAXFocusedWindowAttribute {
                throw AXWindowProviderError.focusedWindowUnavailable
            }
            throw AXWindowProviderError.focusedWindowUnavailable
        }
        return typedValue
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func windowFrame(for element: AXUIElement) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAXValue = positionValue,
              let sizeAXValue = sizeValue else {
            throw AXWindowProviderError.frameUnavailable
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue as! AXValue, .cgSize, &size) else {
            throw AXWindowProviderError.frameUnavailable
        }

        return CGRect(origin: position, size: size)
    }
}
