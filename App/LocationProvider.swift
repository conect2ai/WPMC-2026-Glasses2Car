import Foundation
import CoreLocation

/// Continuous location updates while the app is active, so each API request
/// can be stamped with the driver's position at send and receive time.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var current: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Field lesson (trips of 2026-08-12): with the phone locked in the car
        // the app runs in background and When-In-Use updates STOP — every
        // request logged the same frozen coordinate. Keep the GPS alive
        // (requires the "location" background mode; shows the blue indicator).
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.current = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LOCATION error:", error.localizedDescription)
    }
}
