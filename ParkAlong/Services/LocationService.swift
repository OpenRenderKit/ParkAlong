@preconcurrency import CoreLocation
import Foundation

enum LocationRequestResult: Equatable, Sendable {
    case success(Coordinate)
    case denied
    case restricted
    case timedOut
    case unavailable
    case cancelled
}

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestCoordinate() async -> LocationRequestResult
}

@MainActor
final class LocationService: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let requestTimeout: Duration
    private var continuation: (id: Int, value: CheckedContinuation<LocationRequestResult, Never>)?
    private var timeoutTask: Task<Void, Never>?
    private var activeRequestID: Int?
    private var nextRequestID = 0

    init(requestTimeout: Duration = .seconds(8)) {
        self.requestTimeout = requestTimeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestCoordinate() async -> LocationRequestResult {
        switch manager.authorizationStatus {
        case .denied: return .denied
        case .restricted: return .restricted
        default: break
        }

        // A second request supersedes the first; that is not evidence that
        // location itself is unavailable.
        if let activeRequestID {
            finish(.cancelled, requestID: activeRequestID)
        }
        let requestID = nextRequestID
        nextRequestID += 1
        activeRequestID = requestID
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard activeRequestID == requestID else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                self.continuation = (requestID, continuation)
                guard !Task.isCancelled else {
                    finish(.cancelled, requestID: requestID)
                    return
                }
                timeoutTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await Task.sleep(for: self.requestTimeout)
                    } catch {
                        return
                    }
                    self.finish(.timedOut, requestID: requestID)
                }
                switch manager.authorizationStatus {
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .authorizedAlways, .authorizedWhenInUse:
                    manager.requestLocation()
                case .denied:
                    finish(.denied, requestID: requestID)
                case .restricted:
                    finish(.restricted, requestID: requestID)
                @unknown default:
                    finish(.unavailable, requestID: requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.cancelled, requestID: requestID)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finish(.denied)
        case .restricted:
            finish(.restricted)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date.now
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 5_000
                && abs($0.timestamp.timeIntervalSince(now)) <= 120
                && CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            finish(.unavailable)
            return
        }
        finish(.success(.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        switch manager.authorizationStatus {
        case .denied: finish(.denied)
        case .restricted: finish(.restricted)
        default: finish(.unavailable)
        }
    }

    private func finish(_ result: LocationRequestResult, requestID: Int? = nil) {
        guard let continuation else { return }
        if let requestID, continuation.id != requestID { return }
        self.continuation = nil
        activeRequestID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.value.resume(returning: result)
    }
}

@MainActor
final class FixtureLocationService: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus
    private let result: LocationRequestResult

    init(denied: Bool) {
        result = denied ? .denied : .success(.melbourneCBD)
        authorizationStatus = denied ? .denied : .authorizedWhenInUse
    }

    init(result: LocationRequestResult) {
        self.result = result
        switch result {
        case .success, .timedOut, .unavailable, .cancelled: authorizationStatus = .authorizedWhenInUse
        case .denied: authorizationStatus = .denied
        case .restricted: authorizationStatus = .restricted
        }
    }

    func requestCoordinate() async -> LocationRequestResult { result }
}
