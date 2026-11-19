import Foundation
import HealthKit

enum HealthImportError: Error { case disabled, permissionNotReviewed }

// Inactive adapter for historical Apple Health fall-count samples only.
// No requestAuthorization or query is invoked by this repository.
final class HealthKitFallSource: ExternalEventSource {
    let sourceID = Observation.Origin.appleHealth.rawValue
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    static var readType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .numberOfTimesFallen)!
    }

    func historicalCandidates() throws -> [ExternalEventCandidate] {
        throw HealthImportError.disabled
    }

    // This mapper is available for future permissioned query code. A sample's
    // count may exceed one; do not silently convert it to one fall event.
    func candidate(from sample: HKQuantitySample) -> ExternalEventCandidate? {
        guard sample.quantityType == Self.readType else { return nil }
        let count = Int(sample.quantity.doubleValue(for: HKUnit.count()))
        guard count > 0 else { return nil }
        return ExternalEventCandidate(
            source: sourceID,
            sourceRecordID: sample.uuid.uuidString,
            occurredAt: sample.startDate,
            count: count,
            sourceLabel: "Apple Health historical fall record"
        )
    }
}
