import SwiftUI
import MWDATCore
#if DEBUG
import MWDATMockDevice
#endif

@main
struct RayBanTripApp: App {
    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }

        #if DEBUG
        // MockDevice test server: lets XCUITest processes drive mock glasses over
        // HTTP (pair, don, set camera feed...). Only active when launched with
        // the --ui-testing argument. See Meta's "Testing with Mock Device Kit (iOS)".
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: false))
            let portFilePath = ProcessInfo.processInfo.environment["MWDAT_TEST_SERVER_PORT_FILE"]
            Task {
                try await MockDeviceKit.shared.startTestServer(portFilePath: portFilePath)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--mock-glasses") {
            // Manual development without physical glasses: enable the mock stack
            // (simulated registration/permissions) and pair mock Ray-Ban Meta
            // right away so "Conectar e transmitir" finds a device.
            MockDeviceKit.shared.enable()
            _ = try? MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
