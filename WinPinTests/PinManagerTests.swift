import ApplicationServices
@testable import WinPin
import XCTest

final class PinManagerTests: XCTestCase {
    func testPinShowsOverlayWithoutImmediateRefresh() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.refreshResults = [.failure]
        let overlay = MockOverlayManager()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: overlay,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.shownIDs, [window.id])
        XCTAssertEqual(overlay.removedIDs, [])
        XCTAssertEqual(provider.refreshCallCount, 0)
    }

    func testInitialRaiseSuccessIsLogged() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
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

        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_succeeded reason=initial_raise_succeeded")
                && message.contains("title=\"Pinned\"")
        })
    }

    func testInitialRaiseFailureStillPinsAndShowsOverlay() {
        let window = makeTestWindow(title: "Pinned", axRole: kAXWindowRole, supportedActions: [kAXRaiseAction])
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        provider.raiseResults = [.failure]
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

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [window.id])
        XCTAssertEqual(overlay.shownIDs, [window.id])
        XCTAssertEqual(provider.raisedIDs, [window.id])
        XCTAssertTrue(logger.messages.contains { message in
            message.contains("pin_failed reason=initial_raise_failed")
                && message.contains("rawValue=")
                && message.contains("title=\"Pinned\"")
                && message.contains("ax_role=\"AXWindow\"")
                && message.contains("ax_supported_actions=\"AXRaise\"")
        })
    }

    func testChangeNotificationHappensAfterUnpinMessageIsUpdated() {
        let window = makeTestWindow(title: "Pinned")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [window])
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: provider,
            overlayManager: MockOverlayManager(),
            automaticallyStartTimer: false
        )
        var observedMessages: [String?] = []
        manager.onChange = {
            observedMessages.append(manager.lastMessage)
        }

        manager.toggleCurrentWindow()
        manager.unpin(id: window.id)

        XCTAssertEqual(observedMessages, [
            "Pinned App Pinned - Pinned.",
            "No pinned windows.",
        ])
    }

    func testUnpinAllRemovesAllPinnedWindowsAndUpdatesMessage() {
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
        var observedMessages: [String?] = []
        manager.onChange = {
            observedMessages.append(manager.lastMessage)
        }

        manager.toggleCurrentWindow()
        manager.toggleCurrentWindow()
        manager.unpinAll()

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [])
        XCTAssertEqual(overlay.removedIDs, [second.id, first.id])
        XCTAssertEqual(observedMessages.last, "No pinned windows.")
    }

    func testPinFailureWithoutAccessibilityIsLogged() {
        let permission = MockPermissionManager(isTrusted: false)
        let logger = MockAppLogger()
        let manager = PinManager(
            permissionManager: permission,
            windowProvider: MockWindowProvider(focusedWindows: []),
            overlayManager: MockOverlayManager(),
            logger: logger,
            automaticallyStartTimer: false
        )

        manager.toggleCurrentWindow(source: .hotKey)

        XCTAssertEqual(logger.messages, [
            "pin_requested source=hotkey",
            "pin_failed reason=accessibility_permission_missing source=hotkey",
        ])
    }

    func testMovePinnedWindowChangesRaiseOrder() {
        let first = makeTestWindow(title: "First")
        let second = makeTestWindow(title: "Second")
        let third = makeTestWindow(title: "Third")
        let permission = MockPermissionManager(isTrusted: true)
        let provider = MockWindowProvider(focusedWindows: [first, second, third])
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

        manager.movePinnedWindow(id: first.id, relativeTo: third.id, placement: .before)

        XCTAssertEqual(manager.pinnedWindows.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(provider.raisedIDs, [second.id, third.id, first.id])
    }
}
