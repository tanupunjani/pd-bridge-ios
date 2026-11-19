import Foundation
import WatchConnectivity

final class WatchInbox: NSObject, WCSessionDelegate {
    private let service: ObservationService
    private let onChange: () -> Void
    private let onFailure: (String) -> Void

    init(service: ObservationService, onChange: @escaping () -> Void,
         onFailure: @escaping (String) -> Void) {
        self.service = service
        self.onChange = onChange
        self.onFailure = onFailure
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        var event: FictionalWatchEvent
        do {
            event = try FictionalWatchEvent.parse(userInfo, receivedAt: Date())
        } catch FictionalWatchEventError.invalidPayload {
            // Reject unexpected data without copying or logging its contents.
            return
        } catch {
            return
        }

        // This is a transport update, not a storage acknowledgment. Keep the
        // Watch outbox entry until a later `.stored` or terminal stale result.
        send(.received, for: event.id, through: session)
        do {
            let receipt = try service.receiveWatch(userInfo)
            if case .inserted = receipt { onChange() }
            send(.stored, for: event.id, through: session)
        } catch ObservationServiceError.deletionInProgress {
            onFailure("A fictional watch event arrived during deletion and was not saved. It was not acknowledged; retry after deletion finishes.")
            send(.retry, for: event.id, through: session)
        } catch ObservationServiceError.watchPausedAfterDeletion {
            onFailure("The fictional watch event was not saved. Save a new local entry before sending watch events after clearing the diary.")
            send(.diaryNotStarted, for: event.id, through: session)
        } catch ObservationServiceError.staleWatchEvent {
            onFailure("This queued fictional watch event predates deletion. It was not saved. The iPhone sent a rejection response so the watch can stop retrying it.")
            send(.rejectedStale, for: event.id, through: session)
        } catch {
            onFailure("The fictional watch event was not saved. Unlock this iPhone and retry from the watch.")
            send(.retry, for: event.id, through: session)
        }
    }

    private func send(_ state: FictionalWatchReceiptState, for eventID: UUID, through session: WCSession) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(FictionalWatchReceipt(eventID: eventID, state: state).message)
    }
}
