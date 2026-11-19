import Foundation

/// The production implementation is compiled only in a separately reviewed
/// build that explicitly opts in after Apple grants the managed entitlement.
/// Current project configurations never define this condition.
#if os(watchOS) && PD_BRIDGE_FALL_DETECTION_ENTITLEMENT_GRANTED
import CoreMotion

final class EntitlementGatedFallAdapter: NSObject, CMFallDetectionDelegate {
    private let manager: CMFallDetectionManager
    private let didReceiveCandidate: (Date, String) -> Void
    private let didChangeAuthorization: (CMAuthorizationStatus) -> Void

    init?(didReceiveCandidate: @escaping (Date, String) -> Void,
          didChangeAuthorization: @escaping (CMAuthorizationStatus) -> Void) {
        guard CMFallDetectionManager.isAvailable else { return nil }
        self.manager = CMFallDetectionManager()
        self.didReceiveCandidate = didReceiveCandidate
        self.didChangeAuthorization = didChangeAuthorization
        super.init()
        manager.delegate = self
    }

    /// Call only after a separate, explicit user action in a release approved
    /// for real fall data. No application code currently calls this method.
    func requestAuthorizationAfterUserAction() {
        manager.requestAuthorization { [weak self] status in
            self?.didChangeAuthorization(status)
        }
    }

    func fallDetectionManager(_ fallDetectionManager: CMFallDetectionManager,
                              didDetect event: CMFallDetectionEvent,
                              completionHandler handler: @escaping @Sendable () -> Void) {
        // Complete promptly; retain only date and Apple's resolution label.
        // Product UI/storage must still make the event pending and user-reviewed.
        let date = event.date
        let resolution = String(describing: event.resolution)
        didReceiveCandidate(date, resolution)
        handler()
    }

    func fallDetectionManagerDidChangeAuthorization(_ fallDetectionManager: CMFallDetectionManager) {
        didChangeAuthorization(fallDetectionManager.authorizationStatus)
    }
}
#else
/// Default build behavior: no Core Motion object is created and no permission
/// request can occur. The active app continues to send only fictional events.
struct EntitlementGatedFallAdapter {
    static let isAvailableInThisBuild = false
}
#endif
