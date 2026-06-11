import AppKit
import ApplicationServices

final class PinManager {
    enum TriggerSource: String {
        case hotKey = "hotkey"
        case menu = "menu"
        case unknown = "unknown"
    }

    enum MovePlacement {
        case before
        case after
    }

    private enum Constants {
        static let raiseInterval: TimeInterval = 0.10
        static let maxConsecutiveMaintenanceFailures = 3
        static let maxConsecutiveSuccessfulRaiseSequences = 3
    }

    private struct RaiseSequenceSignature: Equatable {
        let frontmostApplicationPID: pid_t?
        let raisedWindowIDs: [UUID]
        let snapshots: [AXWindowSnapshot]
    }

    private struct RaiseBackoffState {
        var signature: RaiseSequenceSignature?
        var consecutiveSuccessCount = 0
        var isBackedOff = false
    }

    private let permissionManager: AccessibilityPermissionManaging
    private let windowProvider: WindowProviding
    private let overlayManager: OverlayManaging
    private let logger: AppLogging
    private let automaticallyStartTimer: Bool
    private var timer: Timer?
    private var raiseBackoffState = RaiseBackoffState()

    private(set) var pinnedWindows: [PinnedWindow] = []

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
            notifyChanged()
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
            notifyChanged()
        }
    }

    func unpin(id: UUID) {
        var didRemoveWindow = false
        pinnedWindows.removeAll { window in
            if window.id == id {
                overlayManager.removeOverlay(for: window.id)
                didRemoveWindow = true
                return true
            }
            return false
        }
        if didRemoveWindow {
            resetRaiseBackoff(reason: "pin_removed")
        }
        lastMessage = pinnedWindows.isEmpty ? "No pinned windows." : nil
        raisePinnedWindowsBestEffort()
        updateTimerState()
        notifyChanged()
    }

    func unpinAll() {
        if !pinnedWindows.isEmpty {
            resetRaiseBackoff(reason: "all_pins_removed")
        }
        for window in pinnedWindows {
            overlayManager.removeOverlay(for: window.id)
        }
        pinnedWindows.removeAll()
        lastMessage = "No pinned windows."
        updateTimerState()
        notifyChanged()
    }

    func movePinnedWindow(id: UUID, relativeTo targetID: UUID, placement: MovePlacement) {
        guard id != targetID,
              let currentIndex = pinnedWindows.firstIndex(where: { $0.id == id }),
              let targetIndex = pinnedWindows.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let originalOrder = pinnedWindows.map(\.id)
        let window = pinnedWindows.remove(at: currentIndex)
        var destinationIndex = targetIndex
        if currentIndex < targetIndex {
            destinationIndex -= 1
        }
        if placement == .after {
            destinationIndex += 1
        }
        destinationIndex = min(max(destinationIndex, 0), pinnedWindows.count)
        pinnedWindows.insert(window, at: destinationIndex)

        guard pinnedWindows.map(\.id) != originalOrder else {
            return
        }

        resetRaiseBackoff(reason: "pin_order_changed")
        raisePinnedWindowsBestEffort()
        notifyChanged()
    }

    private func pin(_ window: PinnedWindow) {
        let error = windowProvider.raise(window)
        pinnedWindows.insert(window, at: 0)
        resetRaiseBackoff(reason: "pin_added")
        overlayManager.showOverlay(for: window)
        if error == .success {
            lastMessage = "Pinned \(window.snapshot.appName) - \(window.snapshot.windowTitle)."
            logger.log("pin_succeeded reason=initial_raise_succeeded \(describe(window))")
        } else {
            lastMessage = "Pinned \(window.snapshot.appName) - \(window.snapshot.windowTitle), but the initial raise failed. WinPin will keep retrying."
            logger.log("pin_failed reason=initial_raise_failed ax_error=\(describe(error)) \(describe(window))")
        }
        updateTimerState()
        notifyChanged()
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
            notifyChanged()
        }
    }

    private func raisePinnedWindowsBestEffort() {
        for window in pinnedWindows.reversed() {
            _ = windowProvider.raise(window)
        }
    }

    private func maintainPinnedWindows(staleIDs: inout Set<UUID>) {
        var availableWindows: [PinnedWindow] = []
        let frontmostApplicationPID = windowProvider.frontmostExternalApplicationProcessIdentifier()

        for window in pinnedWindows {
            let refreshError = windowProvider.refreshSnapshot(for: window)
            guard refreshError == .success else {
                resetRaiseBackoff(reason: "refresh_failed")
                markMaintenanceFailure(for: window, error: refreshError, operation: "refresh", staleIDs: &staleIDs)
                continue
            }

            overlayManager.updateOverlay(for: window)
            availableWindows.append(window)
        }

        let raiseCandidates = availableWindows.reversed().filter { window in
            guard let frontmostApplicationPID else {
                return true
            }
            return window.snapshot.pid != frontmostApplicationPID
        }

        guard !raiseCandidates.isEmpty else {
            resetRaiseBackoff(reason: "no_raise_candidates")
            return
        }

        let signature = RaiseSequenceSignature(
            frontmostApplicationPID: frontmostApplicationPID,
            raisedWindowIDs: raiseCandidates.map(\.id),
            snapshots: availableWindows.map(\.snapshot)
        )

        if raiseBackoffState.isBackedOff {
            if raiseBackoffState.signature == signature {
                return
            }
            resetRaiseBackoff(reason: resumeReason(previous: raiseBackoffState.signature, current: signature))
        }

        var allRaisesSucceeded = true
        for window in raiseCandidates {
            let raiseError = windowProvider.raise(window)
            if raiseError != .success {
                allRaisesSucceeded = false
                resetRaiseBackoff(reason: "raise_failed")
                markRaiseFailure(for: window, error: raiseError)
            } else {
                if window.maintenanceFailureCount > 0 || window.raiseFailureCount > 0 || window.isStale {
                    logger.log("pin_succeeded reason=maintenance_recovered \(describe(window))")
                }
                window.maintenanceFailureCount = 0
                window.raiseFailureCount = 0
                window.isStale = false
            }
        }

        if allRaisesSucceeded {
            recordSuccessfulRaiseSequence(signature)
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

    private func describe(_ processIdentifier: pid_t?) -> String {
        guard let processIdentifier else {
            return "none"
        }
        return "\(processIdentifier)"
    }

    private func resetRaiseBackoff(reason: String) {
        let wasBackedOff = raiseBackoffState.isBackedOff
        raiseBackoffState = RaiseBackoffState()
        if wasBackedOff {
            logger.log("pin_raise_backoff_resumed reason=\(reason)")
        }
    }

    private func recordSuccessfulRaiseSequence(_ signature: RaiseSequenceSignature) {
        guard signature.raisedWindowIDs.count > 1 else {
            raiseBackoffState = RaiseBackoffState()
            return
        }

        if raiseBackoffState.signature == signature {
            raiseBackoffState.consecutiveSuccessCount += 1
        } else {
            raiseBackoffState.signature = signature
            raiseBackoffState.consecutiveSuccessCount = 1
            raiseBackoffState.isBackedOff = false
        }

        guard !raiseBackoffState.isBackedOff,
              raiseBackoffState.consecutiveSuccessCount >= Constants.maxConsecutiveSuccessfulRaiseSequences else {
            return
        }

        raiseBackoffState.isBackedOff = true
        logger.log("pin_raise_backoff_started consecutive_successes=\(raiseBackoffState.consecutiveSuccessCount) frontmost_external_pid=\(describe(signature.frontmostApplicationPID)) raised_window_ids=\(describe(signature.raisedWindowIDs))")
    }

    private func resumeReason(previous: RaiseSequenceSignature?, current: RaiseSequenceSignature) -> String {
        guard let previous else {
            return "raise_sequence_changed"
        }
        if previous.frontmostApplicationPID != current.frontmostApplicationPID {
            return "frontmost_application_changed"
        }
        if previous.raisedWindowIDs != current.raisedWindowIDs {
            return "raise_sequence_changed"
        }
        if previous.snapshots != current.snapshots {
            return "window_snapshot_changed"
        }
        return "raise_sequence_changed"
    }

    private func describe(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    private func describe(_ window: PinnedWindow) -> String {
        let snapshot = window.snapshot
        let bundleIdentifier = snapshot.bundleIdentifier ?? "unknown"
        let role = snapshot.axRole ?? "unknown"
        let supportedActions = snapshot.supportedActions.isEmpty ? "none" : snapshot.supportedActions.joined(separator: ",")
        return "window_id=\(window.id.uuidString) pid=\(snapshot.pid) bundle_id=\"\(bundleIdentifier)\" app=\"\(snapshot.appName)\" title=\"\(snapshot.windowTitle)\" frame=\"\(snapshot.frame)\" ax_role=\"\(role)\" ax_supported_actions=\"\(supportedActions)\""
    }

    private func notifyChanged() {
        onChange?()
    }
}
