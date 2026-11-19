import WatchConnectivity
import SwiftUI

final class WatchTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Preparing connection"
    @Published private(set) var pendingCount = 0

    private let outboxStore: FictionalWatchOutboxStore
    private var outbox = FictionalWatchOutbox()
    private var outboxIsCorrupt = false

    override init() {
        self.outboxStore = FictionalWatchOutboxStore()
        super.init()
        do {
            outbox = try outboxStore.load()
        } catch {
            // Never replace unreadable queued identifiers with an empty
            // value. Fail closed and keep the stored bytes intact.
            outboxIsCorrupt = true
            status = "The saved fictional watch queue could not be read. It has not been changed."
        }
        pendingCount = outbox.events.count
        if let result = outbox.lastResult {
            status = Self.message(for: result)
        } else if pendingCount > 0 {
            status = "Fictional event is queued on this watch. Waiting for iPhone."
        }
    }

    func start() {
        guard WCSession.isSupported() else {
            status = "Watch connection unavailable"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendFictionalEvent() {
        guard !outboxIsCorrupt else {
            status = "The saved fictional watch queue could not be read. No new event was queued."
            return
        }
        let item = PendingFictionalEvent(id: UUID(), occurredAt: Date())
        let priorQueue = outbox
        guard outbox.enqueue(item) else {
            status = "The fictional watch queue is full. Retry after pending events are stored."
            return
        }
        guard persistOutbox() else {
            outbox = priorQueue
            pendingCount = outbox.events.count
            status = "Could not save the fictional test event on this watch"
            return
        }
        status = "Fictional event is queued on this watch."
        flush()
    }

    func retryPending() {
        guard !outboxIsCorrupt else {
            status = "The saved fictional watch queue could not be read. It has not been changed."
            return
        }
        status = "Retrying fictional event delivery. It remains queued until the iPhone saves it."
        flush()
    }

    private func persistOutbox() -> Bool {
        guard (try? outboxStore.save(outbox)) != nil else { return false }
        pendingCount = outbox.events.count
        return true
    }

    private func flush() {
        guard !outboxIsCorrupt else {
            status = "The saved fictional watch queue could not be read. It has not been changed."
            return
        }
        guard WCSession.isSupported() else {
            status = "Watch connection unavailable. Event remains queued."
            return
        }
        guard !outbox.events.isEmpty else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else {
            status = "Queued until the iPhone app is installed and connected"
            return
        }
        let outstanding = Set(session.outstandingUserInfoTransfers.compactMap {
            $0.userInfo["eventID"] as? String
        })
        for item in outbox.events where !outstanding.contains(item.id.uuidString) {
            let event = FictionalWatchEvent(id: item.id, occurredAt: item.occurredAt)
            session.transferUserInfo(event.message)
        }
        status = "Waiting for iPhone. The event remains queued until storage is confirmed."
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            if error == nil && activationState == .activated { self.flush() }
            else { self.status = "Connection unavailable. Event remains queued." }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async { self.flush() }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let receipt = try? FictionalWatchReceipt.parse(userInfo) else { return }
        DispatchQueue.main.async {
            guard self.outbox.events.contains(where: { $0.id == receipt.eventID }) else { return }
            switch receipt.state {
            case .received:
                self.status = "The iPhone received the event. It has not been saved yet."
            case .retry:
                self.status = "The iPhone could not save the event. It remains queued; tap Retry after unlocking the iPhone."
            case .diaryNotStarted:
                self.status = "The iPhone diary was cleared. Create a local entry there, then retry; this event remains queued."
            case .stored, .rejectedStale:
                self.finish(receipt)
            }
        }
    }

    private func finish(_ receipt: FictionalWatchReceipt) {
        let previousQueue = outbox
        guard outbox.complete(receipt.eventID, with: receipt.state) else { return }
        if persistOutbox() {
            status = Self.message(for: receipt.state)
        } else {
            outbox = previousQueue
            pendingCount = outbox.events.count
            status = receipt.state == .stored
                ? "The iPhone saved the event, but this watch could not update its queue. It remains queued; retry is safe."
                : "The iPhone rejected this old event, but this watch could not update its queue. Retry to receive the rejection again."
        }
    }

    private static func message(for state: FictionalWatchReceiptState) -> String {
        switch state {
        case .received: return "The iPhone received the event. It has not been saved yet."
        case .stored: return "Saved on iPhone and acknowledged. Review the fictional event in History."
        case .retry: return "The iPhone could not save the event. It remains queued for retry."
        case .diaryNotStarted: return "The iPhone diary was cleared. Create a local entry, then retry."
        case .rejectedStale: return "Rejected: this event predates diary deletion. It was not saved."
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                 error: Error?) {
        guard error != nil,
              let eventIDText = userInfoTransfer.userInfo["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDText) else { return }
        DispatchQueue.main.async {
            guard self.outbox.events.contains(where: { $0.id == eventID }) else { return }
            self.status = "Transfer failed or was delayed. The event remains queued; tap Retry later."
        }
    }
}
