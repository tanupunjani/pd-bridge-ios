import Foundation

enum FictionalWatchEventError: Error { case invalidPayload }

enum FictionalWatchReceiptState: String, Codable, CaseIterable {
    case received
    case stored
    case retry
    case diaryNotStarted
    case rejectedStale

    var isTerminal: Bool { self == .stored || self == .rejectedStale }
}

/// App-level response messages contain only the event UUID and a fixed state.
/// `stored` is sent only after the phone's vault write succeeds (or deduplication
/// confirms the same event was already durably stored).
struct FictionalWatchReceipt: Equatable {
    static let version = 1
    let eventID: UUID
    let state: FictionalWatchReceiptState

    var message: [String: Any] {
        ["version": Self.version, "eventID": eventID.uuidString, "state": state.rawValue]
    }

    static func parse(_ message: [String: Any]) throws -> FictionalWatchReceipt {
        guard Set(message.keys) == ["version", "eventID", "state"],
              let version = message["version"] as? Int, version == Self.version,
              let eventIDText = message["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDText),
              let stateText = message["state"] as? String,
              let state = FictionalWatchReceiptState(rawValue: stateText)
        else { throw FictionalWatchEventError.invalidPayload }
        return FictionalWatchReceipt(eventID: eventID, state: state)
    }
}

// This protocol carries IDs and a fixed fictional kind only. It has no field
// for a patient name, free text, sensor reading, or actual fall alert.
struct FictionalWatchEvent: Equatable {
    static let version = 1
    static let fixedText = "Fictional test event sent from Apple Watch."

    let id: UUID
    let occurredAt: Date

    var message: [String: Any] {
        return ["version": Self.version,
                "fictional": true,
                "kind": "fall",
                "eventID": id.uuidString,
                "occurredAt": Self.formatter.string(from: occurredAt)]
    }

    static func parse(_ message: [String: Any], receivedAt: Date) throws -> FictionalWatchEvent {
        let required: Set<String> = ["version", "fictional", "kind", "eventID", "occurredAt"]
        guard Set(message.keys) == required,
              let version = message["version"] as? Int, version == Self.version,
              let fictional = message["fictional"] as? Bool, fictional,
              let kind = message["kind"] as? String, kind == "fall",
              let idText = message["eventID"] as? String,
              let id = UUID(uuidString: idText),
              let timeText = message["occurredAt"] as? String,
              let time = formatter.date(from: timeText),
              time <= receivedAt.addingTimeInterval(600),
              time >= receivedAt.addingTimeInterval(-30 * 24 * 3600)
        else { throw FictionalWatchEventError.invalidPayload }
        return FictionalWatchEvent(id: id, occurredAt: time)
    }

    private static var formatter: ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }
}
