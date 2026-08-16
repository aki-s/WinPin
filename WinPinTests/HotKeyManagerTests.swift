@testable import WinPin
import XCTest

final class HotKeyManagerTests: XCTestCase {
    func testSingleShortcutPressOnlyTogglesOnceUntilRelease() {
        let manager = HotKeyManager()
        var triggerCount = 0
        manager.onHotKey = {
            triggerCount += 1
        }

        manager.simulateHotKeyPressForTesting()
        manager.simulateHotKeyPressForTesting()
        manager.simulateHotKeyPressForTesting()

        XCTAssertEqual(triggerCount, 1)

        manager.simulateHotKeyReleaseForTesting()
        manager.simulateHotKeyPressForTesting()

        XCTAssertEqual(triggerCount, 2)
    }
}
