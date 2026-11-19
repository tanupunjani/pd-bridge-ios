import Foundation

struct PendingFictionalEvent: Codable, Equatable {
    let id: UUID
    let occurredAt: Date
}

/// Versioned queue for fixed fictional event identifiers and timestamps only.
/// It intentionally has no free-text or health-data fields.
struct FictionalWatchOutbox: Codable, Equatable {
    static let currentVersion = 1
    static let maximumPendingEvents = 100
    private(set) var events: [PendingFictionalEvent] = []
    private(set) var lastResult: FictionalWatchReceiptState?
    private(set) var lastResultEventID: UUID?
    let version: Int

    init(events: [PendingFictionalEvent] = [], lastResult: FictionalWatchReceiptState? = nil,
         lastResultEventID: UUID? = nil) {
        self.version = Self.currentVersion
        self.events = events
        self.lastResult = lastResult
        self.lastResultEventID = lastResultEventID
    }

    private enum CodingKeys: String, CodingKey { case version, events, lastResult, lastResultEventID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported fictional outbox version")
        }
        let decodedEvents = try container.decode([PendingFictionalEvent].self, forKey: .events)
        let decodedResult = try container.decodeIfPresent(FictionalWatchReceiptState.self, forKey: .lastResult)
        let decodedResultID = try container.decodeIfPresent(UUID.self, forKey: .lastResultEventID)
        guard decodedEvents.count <= Self.maximumPendingEvents,
              Set(decodedEvents.map(\.id)).count == decodedEvents.count,
              (decodedResult == nil) == (decodedResultID == nil),
              decodedResult == nil || decodedResult?.isTerminal == true else {
            throw DecodingError.dataCorruptedError(forKey: .events, in: container,
                                                   debugDescription: "Invalid or duplicate fictional event identifiers")
        }
        self.version = decodedVersion
        self.events = decodedEvents
        self.lastResult = decodedResult
        self.lastResultEventID = decodedResultID
    }

    @discardableResult
    mutating func enqueue(_ event: PendingFictionalEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }),
              events.count < Self.maximumPendingEvents else { return false }
        events.append(event)
        lastResult = nil
        lastResultEventID = nil
        return true
    }

    @discardableResult
    mutating func acknowledge(_ id: UUID) -> Bool {
        complete(id, with: .stored)
    }

    @discardableResult
    mutating func complete(_ id: UUID, with result: FictionalWatchReceiptState) -> Bool {
        guard result.isTerminal, events.contains(where: { $0.id == id }) else { return false }
        events.removeAll(where: { $0.id == id })
        lastResult = result
        lastResultEventID = id
        return true
    }
}

enum FictionalWatchOutboxStoreError: Error {
    case invalidOutbox
}

/// Atomically persists only synthetic event IDs and occurrence timestamps.
/// No user-entered text or health information belongs in this queue.
final class FictionalWatchOutboxStore {
    private let manager = FileManager.default
    private let directoryOverride: URL?
    private let fileName = "fictional-outbox-v1.json"
    private let maximumFileSize = 64 * 1024

    init(directoryURL: URL? = nil) {
        self.directoryOverride = directoryURL
    }

    private var directory: URL {
        if let directoryOverride { return directoryOverride }
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PD Bridge Watch Queue", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() throws -> FictionalWatchOutbox {
        guard manager.fileExists(atPath: fileURL.path) else { return FictionalWatchOutbox() }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= maximumFileSize else {
            throw FictionalWatchOutboxStoreError.invalidOutbox
        }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(FictionalWatchOutbox.self, from: data)
        } catch {
            throw FictionalWatchOutboxStoreError.invalidOutbox
        }
    }

    func save(_ outbox: FictionalWatchOutbox) throws {
        guard outbox.events.count <= FictionalWatchOutbox.maximumPendingEvents,
              Set(outbox.events.map(\.id)).count == outbox.events.count else {
            throw FictionalWatchOutboxStoreError.invalidOutbox
        }
        let data = try JSONEncoder().encode(outbox)
        guard data.count <= maximumFileSize else { throw FictionalWatchOutboxStoreError.invalidOutbox }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
#if os(iOS) || os(watchOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
        try data.write(to: fileURL, options: [.atomic])
#endif
    }
}
