import Foundation

enum ObservationServiceError: Error {
    case missing, pending, emptyText, deletionInProgress, watchPausedAfterDeletion, staleWatchEvent
    case protectedDataUnavailable
    case invalidVoiceNote
}

enum WatchReceipt: Equatable { case inserted(UUID), duplicate }

// Serializes all read-modify-write operations. In-memory state changes only
// after an encrypted vault write succeeds.
final class ObservationService {
    private let vault: ObservationVault
    private let lock = NSRecursiveLock()
    private let deletionGate = NSLock()
    private var archive: ObservationArchive
    private var deletionPending = false
    private var protectedDataAvailable = true
    private var deletionRequested = false
    private var mutationGeneration: UInt64 = 0

    init(vault: ObservationVault) throws {
        self.vault = vault
        do {
            self.archive = try vault.loadArchive()
        } catch VaultError.deletionPending {
            self.archive = ObservationArchive(observations: [], processedSourceKeys: [])
            self.deletionPending = true
        }
    }

    var isDeletionPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return deletionPending
    }

    /// Called before iOS makes complete-protection files and the WhenUnlocked
    /// Keychain key unavailable. Drop decrypted records and block all writes.
    func protectedDataWillBecomeUnavailable() {
        lock.lock(); defer { lock.unlock() }
        archive = ObservationArchive(observations: [], processedSourceKeys: [])
        protectedDataAvailable = false
    }

    /// Reload only after iOS reports protected data available. A pending
    /// deletion is resumed by the vault before any record can be restored.
    func protectedDataDidBecomeAvailable() throws {
        lock.lock(); defer { lock.unlock() }
        protectedDataAvailable = true
        do {
            let restored = try vault.loadArchive()
            archive = restored
            deletionPending = false
        } catch VaultError.deletionPending {
            archive = ObservationArchive(observations: [], processedSourceKeys: [])
            deletionPending = true
            throw VaultError.deletionPending
        } catch {
            archive = ObservationArchive(observations: [], processedSourceKeys: [])
            throw error
        }
    }

    var isProtectedDataAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return protectedDataAvailable
    }

    var observations: [Observation] {
        lock.lock(); defer { lock.unlock() }
        return AppointmentReport.orderedEntries(from: archive.observations)
    }

    var reportObservations: [Observation] {
        return AppointmentReport.selectedEntries(from: observations)
    }

    func encryptedBackup(passphrase: String) throws -> Data {
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        guard protectedDataAvailable else { throw ObservationServiceError.protectedDataUnavailable }
        guard !deletionPending else { throw ObservationServiceError.deletionInProgress }
        return try ObservationBackup.seal(archive, passphrase: passphrase)
    }

    func importEncryptedBackup(_ data: Data, passphrase: String) throws {
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        guard protectedDataAvailable else { throw ObservationServiceError.protectedDataUnavailable }
        let incoming = try ObservationBackup.open(data, passphrase: passphrase)
        try changeLocked(intent: .explicitUserAction) { current in
            current = try ObservationBackup.merge(incoming, into: current)
        }
    }

    func deleteAll() throws {
        try beginDeletion()
        defer { endDeletion() }
        lock.lock(); defer { lock.unlock() }
        guard protectedDataAvailable else { throw ObservationServiceError.protectedDataUnavailable }
        // Clear cached records before touching either durable store. Mutations
        // remain blocked until the vault confirms completion.
        archive = ObservationArchive(observations: [], processedSourceKeys: [])
        deletionPending = true
        try vault.deleteAll()
        deletionPending = false
    }

    @discardableResult
    func addManual(kind: Observation.Kind, text: String, at date: Date = Date()) throws -> UUID {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationServiceError.emptyText
        }
        let observation = Observation(id: UUID(), kind: kind, originalText: text,
            savedText: text, occurredAt: date, recordedAt: date, origin: .manual,
            sourceRecordID: nil, confirmation: .userConfirmed, previousWording: [])
        try change(intent: .explicitUserAction) { $0.observations.append(observation) }
        return observation.id
    }

    @discardableResult
    func addVoiceNote(audioData: Data,
                      spokenLanguage: VoiceNoteAttachment.SpokenLanguage,
                      durationSeconds: TimeInterval,
                      at date: Date = Date()) throws -> UUID {
        let attachment = try VoiceNoteAttachment(audioData: audioData,
                                                 spokenLanguage: spokenLanguage,
                                                 durationSeconds: durationSeconds)
        let label = "Voice note (original audio retained; not transcribed)"
        let observation = Observation(id: UUID(), kind: .note, originalText: label,
            savedText: label, occurredAt: date, recordedAt: date, origin: .manual,
            sourceRecordID: nil, confirmation: .userConfirmed, previousWording: [],
            voiceNote: attachment)
        try change(intent: .explicitUserAction) { $0.observations.append(observation) }
        return observation.id
    }

    func receiveWatch(_ message: [String: Any], at date: Date = Date()) throws -> WatchReceipt {
        let event = try FictionalWatchEvent.parse(message, receivedAt: date)
        let sourceID = event.id.uuidString
        let key = Observation.sourceKey(origin: .fictionalWatch, recordID: sourceID)
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        guard protectedDataAvailable else { throw ObservationServiceError.protectedDataUnavailable }
        guard !deletionPending else { throw ObservationServiceError.deletionInProgress }
        if archive.processedSourceKeys.contains(key) { return .duplicate }
        let item = Observation(id: UUID(), kind: .fall,
            originalText: FictionalWatchEvent.fixedText,
            savedText: FictionalWatchEvent.fixedText,
            occurredAt: event.occurredAt, recordedAt: date,
            origin: .fictionalWatch, sourceRecordID: sourceID,
            confirmation: .pendingReview, previousWording: [])
        do {
            try changeLocked(intent: .watchDelivery(occurredAt: event.occurredAt)) {
                $0.observations.append(item)
                $0.processedSourceKeys.insert(key)
            }
        } catch VaultError.deletedVaultRequiresUserAction {
            throw ObservationServiceError.watchPausedAfterDeletion
        } catch VaultError.staleWatchEvent {
            throw ObservationServiceError.staleWatchEvent
        }
        return .inserted(item.id)
    }

    func confirm(_ id: UUID) throws {
        try update(id) { $0.confirmation = .userConfirmed }
    }

    func setIncluded(_ id: UUID, included: Bool) throws {
        try update(id) { item in
            guard item.confirmation == .userConfirmed else { throw ObservationServiceError.pending }
            item.includeInAppointment = included
        }
    }

    func edit(_ id: UUID, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationServiceError.emptyText
        }
        try update(id) { item in
            if item.savedText != text {
                item.previousWording.append(item.savedText)
                item.savedText = text
            }
        }
    }

    @discardableResult
    func remove(_ id: UUID) throws -> Observation {
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        guard let item = archive.observations.first(where: { $0.id == id }) else {
            throw ObservationServiceError.missing
        }
        try changeLocked { $0.observations.removeAll(where: { $0.id == id }) }
        return item
    }

    func undoRemoval(_ item: Observation) throws {
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        guard !archive.observations.contains(where: { $0.id == item.id }) else { return }
        try changeLocked { $0.observations.append(item) }
    }

    private func update(_ id: UUID, transform: (inout Observation) throws -> Void) throws {
        try change { candidate in
            guard let index = candidate.observations.firstIndex(where: { $0.id == id }) else {
                throw ObservationServiceError.missing
            }
            try transform(&candidate.observations[index])
        }
    }

    private func change(intent: ObservationSaveIntent = .ordinary,
                        _ transform: (inout ObservationArchive) throws -> Void) throws {
        let generation = try beginMutation()
        lock.lock(); defer { lock.unlock() }
        try validateMutation(generation)
        try changeLocked(intent: intent, transform)
    }

    /// Takes a nonblocking admission snapshot before waiting for the service
    /// lock. A call that began during deletion is rejected after the lock is
    /// released instead of silently running against the newly empty vault.
    private func beginMutation() throws -> UInt64 {
        deletionGate.lock(); defer { deletionGate.unlock() }
        guard !deletionRequested else { throw ObservationServiceError.deletionInProgress }
        return mutationGeneration
    }

    private func validateMutation(_ generation: UInt64) throws {
        deletionGate.lock(); defer { deletionGate.unlock() }
        guard !deletionRequested, generation == mutationGeneration else {
            throw ObservationServiceError.deletionInProgress
        }
    }

    private func beginDeletion() throws {
        deletionGate.lock(); defer { deletionGate.unlock() }
        guard !deletionRequested else { throw ObservationServiceError.deletionInProgress }
        deletionRequested = true
        mutationGeneration &+= 1
    }

    private func endDeletion() {
        deletionGate.lock(); defer { deletionGate.unlock() }
        deletionRequested = false
    }

    private func changeLocked(intent: ObservationSaveIntent = .ordinary,
                              _ transform: (inout ObservationArchive) throws -> Void) throws {
        guard protectedDataAvailable else { throw ObservationServiceError.protectedDataUnavailable }
        guard !deletionPending else { throw ObservationServiceError.deletionInProgress }
        var candidate = archive
        try transform(&candidate)
        try vault.saveArchive(candidate, intent: intent)
        archive = candidate
    }
}
