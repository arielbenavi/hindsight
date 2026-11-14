import CoreLocation
import Observation

/// "Where am I?" for the Map. When-In-Use only; asked after our own explanation card.
@Observable
@MainActor
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus
    private(set) var location: Coordinate?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if isAuthorized { manager.startUpdatingLocation() }
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }
    var notAskedYet: Bool { status == .notDetermined }

    func request() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            if self.isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(last.coordinate)
        Task { @MainActor in self.location = coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// "6 min walk" up to ~1.5 km, then "1.2 km" / "12 km".
enum DistanceText {
    static func format(_ meters: Double) -> String {
        if meters < 1_500 { return "\(max(1, Int((meters / 80).rounded()))) min walk" }
        if meters < 10_000 { return String(format: "%.1f km", meters / 1_000) }
        return "\(Int(meters / 1_000)) km"
    }
}
