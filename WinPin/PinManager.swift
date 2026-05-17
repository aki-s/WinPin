import AppKit
import ApplicationServices

final class PinManager {
    enum TriggerSource: String {
        case hotKey = "hotkey"
        case menu = "menu"
        case unknown = "unknown"
    }

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

    func toggleCurrentWindow(source: TriggerSource = .unknown) {
        logger.log("pin_requested source=\(source.rawValue)")
        guard permissionManager.isTrusted else {
            lastMessage = "Accessibility permission is required before WinPin can pin windows."
            logger.log("pin_failed reason=accessibility_permission_missing source=\(source.rawValue)")
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
            logger.log("pin_failed reason=focused_window_unavailable source=\(source.rawValue) error=\"\(error.localizedDescription)\"")
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
        raiseLatestPinnedWindowBestEffort()
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

    private func raiseLatestPinnedWindowBestEffort() {
        // Repeatedly raising every pinned window can make overlapping pins flicker.
        // The newest pin is the effective frontmost pin.
        guard let window = pinnedWindows.last else {
            return
        }
        _ = windowProvider.raise(window)
    }

    private func maintainPinnedWindows(staleIDs: inout Set<UUID>) {
        var newestAvailableWindow: PinnedWindow?

        for window in pinnedWindows {
            let refreshError = windowProvider.refreshSnapshot(for: window)
            guard refreshError == .success else {
                markMaintenanceFailure(for: window, error: refreshError, operation: "refresh", staleIDs: &staleIDs)
                continue
            }

            overlayManager.updateOverlay(for: window)
            newestAvailableWindow = window
        }

        guard let newestAvailableWindow else {
            return
        }

        let raiseError = windowProvider.raise(newestAvailableWindow)
        if raiseError != .success {
            markRaiseFailure(for: newestAvailableWindow, error: raiseError)
        } else {
            if newestAvailableWindow.maintenanceFailureCount > 0 || newestAvailableWindow.raiseFailureCount > 0 || newestAvailableWindow.isStale {
                logger.log("pin_succeeded reason=maintenance_recovered \(describe(newestAvailableWindow))")
            }
            newestAvailableWindow.maintenanceFailureCount = 0
            newestAvailableWindow.raiseFailureCount = 0
            newestAvailableWindow.isStale = false
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

    private func markRaiseFailure(for window: PinnedWindow, error: AXError) {
        window.raiseFailureCount += 1

        // Persistent AXRaise failures do not prove the AX window is gone.
        // Keep the pin while refresh succeeds, and throttle logs to avoid 0.10s spam.
        if window.raiseFailureCount <= Constants.maxConsecutiveMaintenanceFailures || window.raiseFailureCount.isMultiple(of: 50) {
            logger.log("pin_maintenance_failed operation=raise ax_error=\(describe(error)) consecutive_failures=\(window.raiseFailureCount) stale_candidate=false \(describe(window))")
        }
    }

    private func describe(_ error: AXError) -> String {
        "\(error)(rawValue=\(error.rawValue))"
    }

    private func describe(_ window: PinnedWindow) -> String {
        let snapshot = window.snapshot
        let bundleIdentifier = snapshot.bundleIdentifier ?? "unknown"
        let role = snapshot.axRole ?? "unknown"
        let supportedActions = snapshot.supportedActions.isEmpty ? "none" : snapshot.supportedActions.joined(separator: ",")
        return "window_id=\(window.id.uuidString) pid=\(snapshot.pid) bundle_id=\"\(bundleIdentifier)\" app=\"\(snapshot.appName)\" title=\"\(snapshot.windowTitle)\" frame=\"\(snapshot.frame)\" ax_role=\"\(role)\" ax_supported_actions=\"\(supportedActions)\""
    }
}
