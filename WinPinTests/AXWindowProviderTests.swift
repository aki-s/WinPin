import ApplicationServices
@testable import WinPin
import XCTest

final class AXWindowProviderTests: XCTestCase {
    func testRaiseReturnsAXRaiseFailureWithoutRetryingFallback() {
        let window = makeTestWindow(title: "Pinned")
        let actionPerformer = MockAXWindowActionPerformer(results: [.failure])
        let provider = AXWindowProvider(actionPerformer: actionPerformer)

        let error = provider.raise(window)

        XCTAssertEqual(error, .failure)
        XCTAssertEqual(actionPerformer.raiseCallCount, 1)
        XCTAssertEqual(actionPerformer.raisedElements.count, 1)
        XCTAssertTrue(CFEqual(actionPerformer.raisedElements[0], window.axElement))
    }
}
