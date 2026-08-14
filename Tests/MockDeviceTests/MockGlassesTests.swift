import XCTest
import MWDATCore
import MWDATMockDevice

/// Smallest deterministic coverage of the mock-glasses lifecycle:
/// pairing (with simulated permission grants), camera feed / captured-photo
/// configuration, and cleanup. No network, no physical hardware, no sleeps.
@MainActor
final class MockGlassesTests: MockDeviceKitTestCase {

    /// Pairing a mock Ray-Ban Meta must succeed while the mock stack is
    /// enabled. Mock Device Kit simulates the whole SDK stack, including
    /// registration and permission grants, so a successful pair means the
    /// device is usable by app code without any real Meta AI app flow.
    func testPairGlassesProvidesUsableRayBanMeta() throws {
        let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        XCTAssertNotNil(device.services.camera,
                        "Paired mock glasses must expose the camera service")
    }

    /// The camera service must accept a deterministic captured photo from the
    /// test bundle. This is what makes photo-capture flows testable: any
    /// subsequent capture returns exactly this image.
    func testCapturedPhotoCanBeConfiguredFromBundleResource() async throws {
        let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        let camera = device.services.camera

        let imageURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "mock_photo", withExtension: "png"),
            "mock_photo.png must be bundled with the test target")

        await camera.setCapturedImage(fileURL: imageURL)
    }

    /// Disabling the mock stack (our tearDown) must fully reset state:
    /// re-enabling afterwards allows pairing fresh glasses. This guards the
    /// cleanup contract that keeps tests independent of execution order.
    func testDisableResetsStateSoFreshPairingWorks() throws {
        _ = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)

        MockDeviceKit.shared.disable()
        MockDeviceKit.shared.enable()

        let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        XCTAssertNotNil(device.services.camera,
                        "After a disable/enable cycle, pairing must work again")
    }
}
