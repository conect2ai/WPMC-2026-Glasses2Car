import XCTest
import MWDATCore
import MWDATMockDevice

/// Base class for tests that exercise the SDK against Mock Device Kit,
/// following Meta's "Testing with Mock Device Kit (iOS)" guide.
///
/// `setUp` configures the SDK and enables the mock stack (which simulates
/// registration and auto-grants permissions); `tearDown` disables it so each
/// test starts from a clean state — no mock devices leak between tests.
@MainActor
class MockDeviceKitTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try? Wearables.configure()
        MockDeviceKit.shared.enable()
    }

    override func tearDown() async throws {
        MockDeviceKit.shared.disable()
        try await super.tearDown()
    }
}
