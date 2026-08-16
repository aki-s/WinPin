import AppKit
import ApplicationServices

enum AXWindowProviderError: LocalizedError {
    case focusedApplicationUnavailable(AXError)
    case focusedWindowUnavailable(AXError)
    case pidUnavailable(AXError)
    case frameUnavailable(AXError)

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
    func frontmostExternalApplicationProcessIdentifier() -> pid_t?
    func representsSameWindow(_ lhs: PinnedWindow, _ rhs: PinnedWindow) -> Bool
}

protocol AXWindowActionPerforming {
    func performRaiseAction(on element: AXUIElement) -> AXError
}

struct SystemAXWindowActionPerformer: AXWindowActionPerforming {
    func performRaiseAction(on element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}

final class AXWindowProvider: WindowProviding {
    private let logger: AppLogging
    private let actionPerformer: AXWindowActionPerforming
    private var activationObserver: Any?
    private var lastExternalFrontmostApplication: NSRunningApplication?

    init(
        logger: AppLogging = AppLogger.shared,
        actionPerformer: AXWindowActionPerforming = SystemAXWindowActionPerformer()
    ) {
        self.logger = logger
        self.actionPerformer = actionPerformer
        lastExternalFrontmostApplication = Self.externalFrontmostApplication()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  !Self.isWinPin(app)
            else {
                return
            }
            self?.lastExternalFrontmostApplication = app
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func focusedWindow() throws -> PinnedWindow {
        let systemWide = AXUIElementCreateSystemWide()
        let focusedApp: AXUIElement
        do {
            focusedApp = try copyAttribute(kAXFocusedApplicationAttribute, from: systemWide)
            logger.log("focused_app_detected source=system_wide \(describeApplication(focusedApp))")
        } catch let AXWindowProviderError.focusedApplicationUnavailable(error) {
            focusedApp = try fallbackFocusedApplication(after: error)
        }

        let focusedWindow = try focusedWindowElement(from: focusedApp)

        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(focusedWindow, &pid)
        guard pidError == .success, pid > 0 else {
            logger.log("focused_window_failed stage=pid ax_error=\(describe(pidError))")
            throw AXWindowProviderError.pidUnavailable(pidError)
        }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let title = stringAttribute(kAXTitleAttribute, from: focusedWindow) ?? "Untitled Window"
        let frame = try windowFrame(for: focusedWindow)
        let appName = runningApp?.localizedName ?? "Unknown App"
        let bundleIdentifier = runningApp?.bundleIdentifier
        let role = stringAttribute(kAXRoleAttribute, from: focusedWindow)
        let actions = actionNames(for: focusedWindow)
        let actionDesc = actions.isEmpty ? "none" : actions.joined(separator: ",")
        let titleDesc = title.isEmpty ? "Untitled Window" : title
        let bundleDesc = bundleIdentifier ?? "unknown"
        let roleDesc = role ?? "unknown"
        logger.log(
            "focused_window_detected pid=\(pid) bundle_id=\"\(bundleDesc)\" "
                + "app=\"\(appName)\" title=\"\(titleDesc)\" role=\"\(roleDesc)\" "
                + "actions=\"\(actionDesc)\" frame=\"\(frame)\""
        )

        let snapshot = AXWindowSnapshot(
            id: UUID(),
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: title.isEmpty ? "Untitled Window" : title,
            frame: frame,
            axRole: role,
            supportedActions: actions
        )

        return PinnedWindow(axElement: focusedWindow, snapshot: snapshot, appIcon: runningApp?.icon)
    }

    func raise(_ pinnedWindow: PinnedWindow) -> AXError {
        // This is best effort. macOS does not expose a public always-on-top flag
        // for another app's existing window, so WinPin repeatedly raises the
        // specific AX window. Do not activate the app or set AX focus here;
        // that prevents typing into another window from the same application.
        actionPerformer.performRaiseAction(on: pinnedWindow.axElement)
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
            frame: frame,
            axRole: old.axRole,
            supportedActions: old.supportedActions
        )
        return .success
    }

    func frontmostExternalApplicationProcessIdentifier() -> pid_t? {
        if let frontmost = Self.externalFrontmostApplication() {
            return frontmost.processIdentifier
        }
        if let lastExternalFrontmostApplication, !lastExternalFrontmostApplication.isTerminated {
            return lastExternalFrontmostApplication.processIdentifier
        }
        return nil
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
            logger.log("ax_attribute_failed attribute=\"\(attribute)\" ax_error=\(describe(error))")
            if attribute == kAXFocusedApplicationAttribute {
                throw AXWindowProviderError.focusedApplicationUnavailable(error)
            }
            if attribute == kAXFocusedWindowAttribute {
                throw AXWindowProviderError.focusedWindowUnavailable(error)
            }
            throw AXWindowProviderError.focusedWindowUnavailable(error)
        }
        return typedValue
    }

    private func focusedWindowElement(from appElement: AXUIElement) throws -> AXUIElement {
        do {
            return try copyAttribute(kAXFocusedWindowAttribute, from: appElement)
        } catch let AXWindowProviderError.focusedWindowUnavailable(focusedWindowError) {
            if let mainWindow: AXUIElement = try? copyAttribute(kAXMainWindowAttribute, from: appElement) {
                logger.log("focused_window_fallback source=main_window")
                return mainWindow
            }
            let windows: [AXUIElement]? = try? copyAttribute(kAXWindowsAttribute, from: appElement)
            if let firstWindow = windows?.first {
                logger.log("focused_window_fallback source=first_window count=\(windows?.count ?? 0)")
                return firstWindow
            }
            throw AXWindowProviderError.focusedWindowUnavailable(focusedWindowError)
        }
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
        let positionError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard positionError == .success,
              sizeError == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            logger.log(
                "focused_window_failed stage=frame "
                    + "position_error=\(describe(positionError)) size_error=\(describe(sizeError))"
            )
            throw AXWindowProviderError.frameUnavailable(positionError == .success ? sizeError : positionError)
        }

        let positionAXValue: AXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue: AXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            logger.log("focused_window_failed stage=frame_value_decode")
            throw AXWindowProviderError.frameUnavailable(.failure)
        }

        return CGRect(origin: position, size: size)
    }

    private func actionNames(for element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let actionNames = value as? [String]
        else {
            return []
        }
        return actionNames.sorted()
    }

    private func describeApplication(_ element: AXUIElement) -> String {
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(element, &pid)
        guard pidError == .success, pid > 0 else {
            return "pid=unknown bundle_id=\"unknown\" app=\"unknown\" pid_error=\(describe(pidError))"
        }
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let bundleID = runningApp?.bundleIdentifier ?? "unknown"
        let appName = runningApp?.localizedName ?? "Unknown App"
        return "pid=\(pid) bundle_id=\"\(bundleID)\" app=\"\(appName)\""
    }

    private func describe(_ error: AXError) -> String {
        "\(error)(rawValue=\(error.rawValue))"
    }

    private func fallbackFocusedApplication(after error: AXError) throws -> AXUIElement {
        logger.log("focused_app_fallback_requested previous_error=\(describe(error))")
        if let frontmost = Self.externalFrontmostApplication() {
            let bundleID = frontmost.bundleIdentifier ?? "unknown"
            let appName = frontmost.localizedName ?? "Unknown App"
            logger.log(
                "focused_app_fallback source=frontmost pid=\(frontmost.processIdentifier) "
                    + "bundle_id=\"\(bundleID)\" app=\"\(appName)\""
            )
            return AXUIElementCreateApplication(frontmost.processIdentifier)
        }
        if let lastExternalFrontmostApplication {
            let bundleID = lastExternalFrontmostApplication.bundleIdentifier ?? "unknown"
            let appName = lastExternalFrontmostApplication.localizedName ?? "Unknown App"
            logger.log(
                "focused_app_fallback source=last_external pid=\(lastExternalFrontmostApplication.processIdentifier) "
                    + "bundle_id=\"\(bundleID)\" app=\"\(appName)\""
            )
            return AXUIElementCreateApplication(lastExternalFrontmostApplication.processIdentifier)
        }
        throw AXWindowProviderError.focusedApplicationUnavailable(error)
    }

    private static func externalFrontmostApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, !isWinPin(app) else {
            return nil
        }
        return app
    }

    private static func isWinPin(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return false
        }
        return bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
