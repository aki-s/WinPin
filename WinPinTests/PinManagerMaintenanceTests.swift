import ApplicationServices
@testable import WinPin
import XCTest

final class PinManagerMaintenanceTests: XCTestCase {
    func testTransientMaintenanceFailuresDoNotImmediatelyRemovePinnedWindow() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure, .failure, .success]
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.removedIDs, [])

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(window.maintenanceFailureCount, 0)
    }

    func testMaintenanceRecoveryIsLoggedAfterTransientFailure() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.success, .success]
        provider.raiseResults = [.success, .failure, .success]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_succeeded reason=maintenance_recovered")
                && message.contains("title=\"Pinned\"")
        })
    }

    func testConsecutiveMaintenanceFailuresRemovePinnedWindow() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure, .failure, .failure]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [])
        XCTAssertEqual(overlay.removedIDs, [window.id])
        XCTAssertEqual(logger.messages.filter { $0.contains("pin_maintenance_failed operation=refresh") }.count, 3)
        XCTAssertTrue(logger.messages.contains { $0.contains("pin_removed reason=stale_window") })
    }

    func testConsecutiveRaiseFailuresDoNotRemoveAvailablePinnedWindow() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.success, .success, .success, .success]
        provider.raiseResults = [.success, .failure, .failure, .failure, .failure]
        let overlay = MockOverlayManager()
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.removedIDs, [])
        XCTAssertEqual(logger.messages.filter { $0.contains("pin_maintenance_failed operation=raise") }.count, 3)
        XCTAssertTrue(logger.messages.allSatisfy { !$0.contains("pin_removed reason=stale_window") })
        XCTAssertTrue(logger.messages.contains { $0.contains("stale_candidate=false") })
    }

    func testMaintenanceRaisesPinnedWindowsFromBottomToTop() {
        let first = makeTestWindow(title: "First")
        let second = makeTestWindow(title: "Second")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [first.id, second.id])
    }

    func testMaintenanceSkipsPinnedWindowsFromFrontmostApplicationPID() {
        let first = makeTestWindow(title: "First", pid: 100)
        let second = makeTestWindow(title: "Second", pid: 100)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 100
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [second.id, first.id])
        XCTAssertEqual(overlay.updatedIDs, [second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [])
    }

    func testMaintenanceStillRaisesNonFrontmostApplicationsFromBottomToTop() {
        let first = makeTestWindow(title: "First", pid: 100)
        let second = makeTestWindow(title: "Second", pid: 200)
        let third = makeTestWindow(title: "Third", pid: 300)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second, third])
        provider.frontmostProcessIdentifier = 200
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [third.id, second.id, first.id])
        XCTAssertEqual(provider.raisedIDs, [first.id, third.id])
    }
}

// MARK: - Backoff Tests

extension PinManagerMaintenanceTests {
    func testMaintenanceBacksOffAfterThreeIdenticalSuccessfulRaiseSequences() {
        let first = makeTestWindow(title: "First", pid: 100)
        let second = makeTestWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_started")
                && $0.contains("consecutive_successes=3")
                && $0.contains("frontmost_external_pid=999")
        })
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_attempted") })
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_succeeded operation=maintenance") })
    }

    func testMaintenanceDoesNotBackOffSinglePinnedWindow() {
        let window = makeTestWindow(title: "Pinned", pid: 100)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()

        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [window.id, window.id, window.id, window.id])
        XCTAssertFalse(logger.messages.contains { $0.contains("pin_raise_backoff_started") })
    }

    func testMaintenanceBackoffResumesWhenFrontmostApplicationChanges() {
        let first = makeTestWindow(title: "First", pid: 100)
        let second = makeTestWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        provider.frontmostProcessIdentifier = 998
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_resumed reason=frontmost_application_changed")
        })
    }

    func testMaintenanceBackoffResumesWhenWindowSnapshotChanges() {
        let first = makeTestWindow(title: "First", pid: 100)
        let second = makeTestWindow(title: "Second", pid: 200)
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second])
        provider.frontmostProcessIdentifier = 999
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )
        var shouldMoveFirstWindow = false
        provider.refreshHandler = { window in
            guard shouldMoveFirstWindow, window.id == first.id else {
                return
            }
            let old = window.snapshot
            window.snapshot = AXWindowSnapshot(
                id: old.id,
                pid: old.pid,
                bundleIdentifier: old.bundleIdentifier,
                appName: old.appName,
                windowTitle: old.windowTitle,
                frame: CGRect(x: 30, y: 40, width: 300, height: 200),
                axRole: old.axRole,
                supportedActions: old.supportedActions
            )
        }

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        provider.raisedIDs.removeAll()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()
        manager.maintenanceTick()

        shouldMoveFirstWindow = true
        manager.maintenanceTick()

        XCTAssertEqual(provider.raisedIDs, [
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
            first.id, second.id,
        ])
        XCTAssertTrue(logger.messages.contains {
            $0.contains("pin_raise_backoff_resumed reason=window_snapshot_changed")
        })
    }
}
