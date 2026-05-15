import AppKit
import ApplicationServices

final class PinManager {
    private enum Constants {
        static let raiseInterval: TimeInterval = 0.10
        static let maxConsecutiveMaintenanceFailures = 3
    }

    private let permissionManager: AccessibilityPermissionManaging
    private let windowProvider: WindowProviding
    private let overlayManager: OverlayManaging
    private let logger: AppLogging
    private let automaticallyStartTimer: Bool
    private var timer: Timer?

    private(set) var pinnedWindows: [PinnedWindow] = [] {
        didSet {
            onChange?()
        }
    }

    var lastMessage: String?
    var onChange: (() -> Void)?

    init(
        permissionManager: AccessibilityPermissionManaging,
        windowProvider: WindowProviding,
        overlayManager: OverlayManaging,
        logger: AppLogging = AppLogger.shared,
        automaticallyStartTimer: Bool = true
    ) {
        self.permissionManager = permissionManager
        self.windowProvider = windowProvider
        self.overlayManager = overlayManager
        self.logger = logger
        self.automaticallyStartTimer = automaticallyStartTimer
    }

    func toggleCurrentWindow() {
        guard permissionManager.isTrusted else {
            lastMessage = "Accessibility permission is required before WinPin can pin windows."
            logger.log("pin_failed reason=accessibility_permission_missing")
            permissionManager.requestPermissionPrompt()
            onChange?()
            return
        }

        do {
            let current = try windowProvider.focusedWindow()
            if let existing = pinnedWindows.first(where: { windowProvider.representsSameWindow($0, current) }) {
                unpin(id: existing.id)
            } else {
                pin(current)
            }
        } catch {
            lastMessage = error.localizedDescription
            logger.log("pin_failed reason=focused_window_unavailable error=\"\(error.localizedDescription)\"")
            onChange?()
        }
    }

    func unpin(id: UUID) {
        pinnedWindows.removeAll { window in
            if window.id == id {
                overlayManager.removeOverlay(for: window.id)
                return true
            }
            return false
        }
        lastMessage = pinnedWindows.isEmpty ? "No pinned windows." : nil
        raisePinnedWindowsBestEffort()
        updateTimerState()
    }

    func unpinAll() {
        for window in pinnedWindows {
            overlayManager.removeOverlay(for: window.id)
        }
        pinnedWindows.removeAll()
        updateTimerState()
    }

    private func pin(_ window: PinnedWindow) {
        let error = windowProvider.raise(window)
        pinnedWindows.append(window)
        overlayManager.showOverlay(for: window)
        if error == .success {
            lastMessage = "Pinned \(window.snapshot.appName) - \(window.snapshot.windowTitle)."
            logger.log("pin_succeeded reason=initial_raise_succeeded \(describe(window))")
        } else {
            lastMessage = "Pinned \(window.snapshot.appName) - \(window.snapshot.windowTitle), but the initial raise failed. WinPin will keep retrying."
            logger.log("pin_failed reason=initial_raise_failed ax_error=\(describe(error)) \(describe(window))")
        }
        updateTimerState()
    }

    private func updateTimerState() {
        guard automaticallyStartTimer else {
            return
        }

        if pinnedWindows.isEmpty {
            timer?.invalidate()
            timer = nil
            return
        }

        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: Constants.raiseInterval, repeats: true) { [weak self] _ in
            self?.maintenanceTick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func maintenanceTick() {
        guard !pinnedWindows.isEmpty else {
            updateTimerState()
            return
        }

        var staleIDs: Set<UUID> = []

        maintainPinnedWindows(staleIDs: &staleIDs)

        if !staleIDs.isEmpty {
            for id in staleIDs {
                overlayManager.removeOverlay(for: id)
            }
            pinnedWindows.removeAll { staleIDs.contains($0.id) }
            lastMessage = "Removed a pinned window that is no longer available."
            let staleWindowIDs = staleIDs.map(\.uuidString).sorted().joined(separator: ",")
            logger.log("pin_removed reason=stale_window ids=\(staleWindowIDs)")
            updateTimerState()
        }
    }

    private func raisePinnedWindowsBestEffort() {
        // Later pins win: raising in array order means the newest pinned window
        // is raised last and should be frontmost when macOS permits it.
        for window in pinnedWindows {
            _ = windowProvider.raise(window)
        }
    }

    private func maintainPinnedWindows(staleIDs: inout Set<UUID>) {
        // Later pins win: refreshing and raising in array order means the newest
        // pinned window is raised last when macOS permits it.
        for window in pinnedWindows {
            let refreshError = windowProvider.refreshSnapshot(for: window)
            guard refreshError == .success else {
                markMaintenanceFailure(for: window, error: refreshError, operation: "refresh", staleIDs: &staleIDs)
                continue
            }

            overlayManager.updateOverlay(for: window)
            let raiseError = windowProvider.raise(window)
            if raiseError != .success {
                markMaintenanceFailure(for: window, error: raiseError, operation: "raise", staleIDs: &staleIDs)
            } else {
                if window.maintenanceFailureCount > 0 || window.isStale {
                    logger.log("pin_succeeded reason=maintenance_recovered \(describe(window))")
                }
                window.maintenanceFailureCount = 0
                window.isStale = false
            }
        }
    }

    private func markMaintenanceFailure(for window: PinnedWindow, error: AXError, operation: String, staleIDs: inout Set<UUID>) {
        window.maintenanceFailureCount += 1
        logger.log("pin_maintenance_failed operation=\(operation) ax_error=\(describe(error)) consecutive_failures=\(window.maintenanceFailureCount) \(describe(window))")
        if window.maintenanceFailureCount >= Constants.maxConsecutiveMaintenanceFailures {
            window.isStale = true
            staleIDs.insert(window.id)
        }
    }

    private func describe(_ error: AXError) -> String {
        "\(error)(rawValue=\(error.rawValue))"
    }

    private func describe(_ window: PinnedWindow) -> String {
        let snapshot = window.snapshot
        let bundleIdentifier = snapshot.bundleIdentifier ?? "unknown"
        return "window_id=\(window.id.uuidString) pid=\(snapshot.pid) bundle_id=\"\(bundleIdentifier)\" app=\"\(snapshot.appName)\" title=\"\(snapshot.windowTitle)\" frame=\"\(snapshot.frame)\""
    }
}
