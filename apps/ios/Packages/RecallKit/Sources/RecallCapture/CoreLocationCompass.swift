import CoreLocation
import Foundation
import RecallDomain

/// The CompassSensor port on Core Location's heading updates: magnetic north only, so no location is read and
/// `trueHeading` is never used. TODO(verify): Apple's docs don't say whether heading updates need location
/// authorisation; on the iPhone they arrive without asking. Test on device before relying on it.
@MainActor
public final class CoreLocationCompass: NSObject, CompassSensor, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let latest = Latest()
    private var users = 0

    public override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1  // degrees
    }

    public var reading: HeadingReading? { latest.value }

    /// Reads the latest heading from any thread (the scan reads it on its capture queue).
    public nonisolated var sampler: @Sendable () -> HeadingReading? { { [latest] in latest.value } }

    /// Counted, so a scan and a guide can share one compass.
    public func start() {
        users += 1
        guard users == 1, CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    public func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopUpdatingHeading()
        latest.value = nil
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latest.value = HeadingReading(magneticDeg: newHeading.magneticHeading, accuracyDeg: newHeading.headingAccuracy)
    }

    /// The calibration overlay is a picture; Recall says when the compass is unreliable instead.
    public nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

    private final class Latest: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: HeadingReading?
        var value: HeadingReading? {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}
