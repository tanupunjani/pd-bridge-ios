import Foundation
import Security

private enum InjectedDeletionFailure: Error { case stage }

// The integration suite must never create or delete items in the user's login Keychain.
// This file-backed Keychain and its throwaway password exist only for this test process.
private final class DisposableTestKeychain {
    let reference: SecKeychain
    private let url: URL

    init(at url: URL) throws {
        self.url = url
        let password = UUID().uuidString + UUID().uuidString
        var createdKeychain: SecKeychain?
        let status = password.withCString { passwordBytes in
            SecKeychainCreate(url.path,
                              UInt32(password.utf8.count),
                              UnsafeRawPointer(passwordBytes),
                              false,
                              nil,
                              &createdKeychain)
        }
        guard status == errSecSuccess, let createdKeychain else {
            throw NSError(domain: "PD Bridge isolated test Keychain", code: Int(status))
        }
        reference = createdKeychain
    }

    func delete() {
        _ = SecKeychainDelete(reference)
        try? FileManager.default.removeItem(at: url)
    }
}

private final class DeletionFaultPlan {
    private let lock = NSLock()
    private var failures: Set<VaultDeletionStage>
    private let blockedStage: VaultDeletionStage?
    let enteredBlockedStage = DispatchSemaphore(value: 0)
    let releaseBlockedStage = DispatchSemaphore(value: 0)

    init(failures: Set<VaultDeletionStage> = [], blockedStage: VaultDeletionStage? = nil) {
        self.failures = failures
        self.blockedStage = blockedStage
    }

    func setFailures(_ stages: Set<VaultDeletionStage>) {
        lock.lock(); defer { lock.unlock() }
        failures = stages
    }

    func hit(_ stage: VaultDeletionStage) throws {
        if stage == blockedStage {
            enteredBlockedStage.signal()
            releaseBlockedStage.wait()
        }
        lock.lock(); defer { lock.unlock() }
        if failures.contains(stage) { throw InjectedDeletionFailure.stage }
    }
}

private func removeTestKeychainItems(service: String, account: String, keychain: SecKeychain) {
    for suffix in ["", ".delete-pending-v1", ".delete-complete-v1"] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account + suffix,
            kSecMatchSearchList as String: [keychain]
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

private func testKeychainItemExists(service: String, account: String, keychain: SecKeychain) -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecMatchSearchList as String: [keychain]
    ]
    var result: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
}

private func testObservation(at date: Date) -> Observation {
    Observation(id: UUID(), kind: .note, originalText: "Fictional deletion test",
                savedText: "Fictional deletion test", occurredAt: date, recordedAt: date,
                origin: .manual, sourceRecordID: nil, confirmation: .userConfirmed,
                previousWording: [])
}

private func runDeletionFailureTests(keychain: SecKeychain) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("pdbridge-delete-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    // If neither independent intent store can persist, no key/file stage runs.
    do {
        let directory = root.appendingPathComponent("no-intent", isDirectory: true)
        let serviceName = "PD Bridge deletion test \(UUID().uuidString)"
        let account = "pd-bridge-delete-\(UUID().uuidString)"
        defer { removeTestKeychainItems(service: serviceName, account: account, keychain: keychain) }
        let baseline = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                keyAccount: account, testKeychainReference: keychain)
        let service = try ObservationService(vault: baseline)
        _ = try service.addManual(kind: .note, text: "Fictional deletion test")

        let plan = DeletionFaultPlan(failures: [.writeFileIntent, .writeKeychainIntent])
        let failingVault = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                    keyAccount: account, testKeychainReference: keychain,
                                                    deletionStageHook: plan.hit)
        let deletingService = try ObservationService(vault: failingVault)
        do {
            try deletingService.deleteAll()
            preconditionFailure("Deletion succeeded without a durable intent")
        } catch VaultError.deletionIntentUnavailable {}
        precondition(deletingService.observations.isEmpty)
        precondition(deletingService.isDeletionPending)
        let unchanged = try ObservationService(vault: baseline)
        precondition(unchanged.observations.count == 1)
        plan.setFailures([])
        try deletingService.deleteAll()
        precondition(deletingService.observations.isEmpty)
        precondition(!deletingService.isDeletionPending)
    }

    // A single durable marker is enough to resume after either marker writer fails.
    for failedMarkerStage: VaultDeletionStage in [.writeFileIntent, .writeKeychainIntent] {
        let directory = root.appendingPathComponent("fallback-\(failedMarkerStage)", isDirectory: true)
        let serviceName = "PD Bridge deletion test \(UUID().uuidString)"
        let account = "pd-bridge-delete-\(UUID().uuidString)"
        defer { removeTestKeychainItems(service: serviceName, account: account, keychain: keychain) }
        let baseline = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                keyAccount: account, testKeychainReference: keychain)
        let service = try ObservationService(vault: baseline)
        _ = try service.addManual(kind: .note, text: "Fictional marker fallback")
        let fault = DeletionFaultPlan(failures: [failedMarkerStage])
        let injected = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                 keyAccount: account, testKeychainReference: keychain,
                                                 deletionStageHook: fault.hit)
        try ObservationService(vault: injected).deleteAll()
        let recovered = try ObservationService(vault: baseline)
        precondition(recovered.observations.isEmpty)
    }

    // Each destructive/cleanup stage is restartable and converges on retry.
    let interruptionStages: [VaultDeletionStage] = [
        .deleteContentKey, .deleteArchive, .writeCompletedTombstone,
        .removeFileIntent, .removeKeychainIntent
    ]
    for stage in interruptionStages {
        let directory = root.appendingPathComponent("interrupt-\(stage)", isDirectory: true)
        let serviceName = "PD Bridge deletion test \(UUID().uuidString)"
        let account = "pd-bridge-delete-\(UUID().uuidString)"
        defer { removeTestKeychainItems(service: serviceName, account: account, keychain: keychain) }
        let baseline = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                keyAccount: account, testKeychainReference: keychain)
        let original = try ObservationService(vault: baseline)
        _ = try original.addManual(kind: .note, text: "Fictional interrupted deletion")

        let fault = DeletionFaultPlan(failures: [stage])
        let injected = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                 keyAccount: account, testKeychainReference: keychain,
                                                 deletionStageHook: fault.hit)
        let deleting = try ObservationService(vault: injected)
        do {
            try deleting.deleteAll()
            preconditionFailure("Injected deletion stage did not fail: \(stage)")
        } catch {}
        precondition(deleting.observations.isEmpty)
        precondition(deleting.isDeletionPending)
        let partiallyCleanedArchive = directory.appendingPathComponent("observations-v1.bin")
        if stage == .deleteContentKey {
            precondition(testKeychainItemExists(service: serviceName, account: account, keychain: keychain), "The injected content-key failure removed the key")
            precondition(!fileManager.fileExists(atPath: partiallyCleanedArchive.path), "Filesystem cleanup was not attempted after the content-key failure")
        }
        if stage == .deleteArchive {
            precondition(!testKeychainItemExists(service: serviceName, account: account, keychain: keychain), "Key cleanup did not run when filesystem cleanup failed")
            precondition(fileManager.fileExists(atPath: partiallyCleanedArchive.path), "The injected filesystem failure did not preserve the ciphertext for retry")
        }
        do {
            _ = try deleting.receiveWatch(FictionalWatchEvent(id: UUID(), occurredAt: Date()).message)
            preconditionFailure("Watch event was accepted while deletion was pending")
        } catch ObservationServiceError.deletionInProgress {}

        let resumed = try ObservationService(vault: baseline)
        precondition(resumed.observations.isEmpty)
        precondition(!resumed.isDeletionPending)
        try resumed.deleteAll() // repeated delete is idempotent
        precondition(resumed.observations.isEmpty)
        let beforeRestartedDiary = FictionalWatchEvent(id: UUID(), occurredAt: Date())
        do {
            _ = try resumed.receiveWatch(beforeRestartedDiary.message, at: beforeRestartedDiary.occurredAt.addingTimeInterval(1))
            preconditionFailure("A new Watch event recreated a cleared vault before user action")
        } catch ObservationServiceError.watchPausedAfterDeletion {}
        let newLocalID = try resumed.addManual(kind: .note, text: "Fictional new entry after deletion")
        precondition(resumed.observations.contains { $0.id == newLocalID })
        let afterRestartedDiary = FictionalWatchEvent(id: UUID(), occurredAt: Date())
        let newWatchReceipt = try resumed.receiveWatch(afterRestartedDiary.message,
                                                       at: afterRestartedDiary.occurredAt.addingTimeInterval(1))
        guard case .inserted = newWatchReceipt else {
            preconditionFailure("A new Watch event did not resume after explicit local action")
        }
        do {
            // Keep the event inside the transport's accepted age window while
            // making it unambiguously older than the deletion cutoff.
            _ = try resumed.receiveWatch(FictionalWatchEvent(id: UUID(), occurredAt: Date().addingTimeInterval(-60)).message)
            preconditionFailure("A pre-deletion queued Watch event recreated deleted data")
        } catch ObservationServiceError.staleWatchEvent {}
        let savedAfterDelete = try baseline.loadArchive()
        precondition(savedAfterDelete.observations.count == 2)
    }

    // A watch callback queued while deletion owns the service lock is rejected
    // after the injected failure, so it cannot be acknowledged as stored.
    do {
        let directory = root.appendingPathComponent("concurrent-watch", isDirectory: true)
        let serviceName = "PD Bridge deletion test \(UUID().uuidString)"
        let account = "pd-bridge-delete-\(UUID().uuidString)"
        defer { removeTestKeychainItems(service: serviceName, account: account, keychain: keychain) }
        let baseline = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                keyAccount: account, testKeychainReference: keychain)
        _ = try ObservationService(vault: baseline).addManual(kind: .note, text: "Fictional concurrent test")
        let fault = DeletionFaultPlan(failures: [.deleteContentKey], blockedStage: .deleteContentKey)
        let injected = ProtectedObservationVault(directoryURL: directory, keyService: serviceName,
                                                 keyAccount: account, testKeychainReference: keychain,
                                                 deletionStageHook: fault.hit)
        let service = try ObservationService(vault: injected)
        let deleteFinished = DispatchSemaphore(value: 0)
        let eventStarted = DispatchSemaphore(value: 0)
        let eventFinished = DispatchSemaphore(value: 0)
        let eventResultLock = NSLock()
        var eventRejected = false
        DispatchQueue.global().async {
            try? service.deleteAll()
            deleteFinished.signal()
        }
        precondition(fault.enteredBlockedStage.wait(timeout: .now() + 3) == .success)
        let message = FictionalWatchEvent(id: UUID(), occurredAt: Date()).message
        DispatchQueue.global().async {
            eventStarted.signal()
            defer { eventFinished.signal() }
            do { _ = try service.receiveWatch(message) }
            catch ObservationServiceError.deletionInProgress {
                eventResultLock.lock(); eventRejected = true; eventResultLock.unlock()
            }
            catch {}
        }
        precondition(eventStarted.wait(timeout: .now() + 3) == .success)
        fault.releaseBlockedStage.signal()
        precondition(deleteFinished.wait(timeout: .now() + 3) == .success)
        precondition(eventFinished.wait(timeout: .now() + 3) == .success)
        eventResultLock.lock(); defer { eventResultLock.unlock() }
        precondition(eventRejected)
        precondition(service.observations.isEmpty)
    }

    try? fileManager.removeItem(at: root)
}

@main
enum VaultIntegration {
    static func main() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("pdbridge-vault-test-\(UUID().uuidString)", isDirectory: true)
        let account = "pd-bridge-test-\(UUID().uuidString)"
        let serviceName = "PD Bridge disposable vault test"
        try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: true)
        let isolatedKeychain = try DisposableTestKeychain(
            at: fileManager.temporaryDirectory.appendingPathComponent(
                "pdbridge-isolated-keychain-\(UUID().uuidString).keychain"
            )
        )
        let keychain = isolatedKeychain.reference
        let vault = ProtectedObservationVault(directoryURL: testRoot, keyService: serviceName,
                                             keyAccount: account, testKeychainReference: keychain)
        defer {
            try? vault.deleteAll()
            removeTestKeychainItems(service: serviceName, account: account, keychain: keychain)
            isolatedKeychain.delete()
            try? fileManager.removeItem(at: testRoot)
        }

        let stamp = Date(timeIntervalSince1970: 1_782_000_000)
        let marker = "Fictional ciphertext check – Gujarati ગુજરાતી Urdu اردو"
        let note = Observation(
            id: UUID(), kind: .note, originalText: marker, savedText: marker,
            occurredAt: stamp, recordedAt: stamp, origin: .manual, sourceRecordID: nil,
            confirmation: .userConfirmed, previousWording: []
        )
        try vault.saveArchive(ObservationArchive(observations: [note], processedSourceKeys: []), intent: .explicitUserAction)

        let archiveURL = testRoot.appendingPathComponent("observations-v1.bin")
        let encryptedBytes = try Data(contentsOf: archiveURL)
        precondition(String(data: encryptedBytes, encoding: .utf8)?.contains(marker) != true)
        let initialArchive = try vault.loadArchive()
        precondition(initialArchive.observations == [note])

        let duplicateID = Observation(
            id: note.id, kind: .fall, originalText: "Fictional duplicate", savedText: "Fictional duplicate",
            occurredAt: stamp, recordedAt: stamp, origin: .manual, sourceRecordID: nil,
            confirmation: .userConfirmed, previousWording: []
        )
        do {
            try vault.saveArchive(ObservationArchive(observations: [note, duplicateID], processedSourceKeys: []), intent: .explicitUserAction)
            preconditionFailure("Vault accepted duplicate observation IDs")
        } catch VaultError.invalidArchive {}
        let preservedArchive = try vault.loadArchive()
        precondition(preservedArchive.observations == [note])

        let receivedAt = stamp.addingTimeInterval(7_200)
        let watchEvent = FictionalWatchEvent(id: UUID(), occurredAt: stamp.addingTimeInterval(60))
        let message = watchEvent.message
        let service = try ObservationService(vault: vault)
        let receipt = try service.receiveWatch(message, at: receivedAt)
        guard case .inserted(let watchRecordID) = receipt else {
            preconditionFailure("The first fictional Watch event was not inserted")
        }
        let persistedWatchEvent = try vault.loadArchive()
        let sourceKey = Observation.sourceKey(origin: .fictionalWatch, recordID: watchEvent.id.uuidString)
        precondition(persistedWatchEvent.processedSourceKeys.contains(sourceKey))
        let savedWatchRecord = persistedWatchEvent.observations.first { $0.id == watchRecordID }
        precondition(savedWatchRecord?.originalText == FictionalWatchEvent.fixedText)
        precondition(savedWatchRecord?.occurredAt == watchEvent.occurredAt)
        precondition(savedWatchRecord?.recordedAt == receivedAt)
        precondition(savedWatchRecord?.confirmation == .pendingReview)

        let restartedService = try ObservationService(vault: vault)
        let repeatedAfterRestart = try restartedService.receiveWatch(message, at: receivedAt)
        precondition(repeatedAfterRestart == .duplicate)
        _ = try restartedService.remove(watchRecordID)
        let afterRemoval = try vault.loadArchive()
        precondition(!afterRemoval.observations.contains { $0.id == watchRecordID })
        precondition(afterRemoval.processedSourceKeys.contains(sourceKey))
        let repeatedAfterDeletion = try restartedService.receiveWatch(message, at: receivedAt)
        precondition(repeatedAfterDeletion == .duplicate)

        let syntheticAudioMarker = Data("SYNTHETIC_AUDIO_PAYLOAD_ONLY".utf8)
        let voiceID = try restartedService.addVoiceNote(audioData: syntheticAudioMarker,
                                                       spokenLanguage: .kutchi,
                                                       durationSeconds: 1.25,
                                                       at: receivedAt)
        let voiceEntry = try vault.loadArchive().observations.first { $0.id == voiceID }
        precondition(voiceEntry?.voiceNote?.audioData == syntheticAudioMarker)
        precondition(voiceEntry?.voiceNote?.spokenLanguage == .kutchi)
        precondition(voiceEntry?.voiceNote?.durationSeconds == 1.25)
        let encryptedWithVoice = try Data(contentsOf: archiveURL)
        precondition(String(data: encryptedWithVoice, encoding: .utf8)?.contains("SYNTHETIC_AUDIO_PAYLOAD_ONLY") != true)

        let backupPassphrase = "fictional-audio-test-passphrase"
        let encryptedBackup = try restartedService.encryptedBackup(passphrase: backupPassphrase)
        let openedBackup = try ObservationBackup.open(encryptedBackup, passphrase: backupPassphrase)
        precondition(openedBackup.observations.first { $0.id == voiceID }?.voiceNote?.audioData == syntheticAudioMarker)

        let restoreDirectory = testRoot.appendingPathComponent("voice-restore", isDirectory: true)
        let restoreVault = ProtectedObservationVault(directoryURL: restoreDirectory,
                                                    keyService: serviceName + " restore",
                                                    keyAccount: account + " restore",
                                                    testKeychainReference: keychain)
        defer {
            try? restoreVault.deleteAll()
            removeTestKeychainItems(service: serviceName + " restore", account: account + " restore",
                                    keychain: keychain)
            try? fileManager.removeItem(at: restoreDirectory)
        }
        let restoredService = try ObservationService(vault: restoreVault)
        try restoredService.importEncryptedBackup(encryptedBackup, passphrase: backupPassphrase)
        let restoredArchive = try restoreVault.loadArchive()
        precondition(restoredArchive.observations.first { $0.id == voiceID }?.voiceNote?.audioData == syntheticAudioMarker)

        let removedVoice = try restartedService.remove(voiceID)
        precondition(removedVoice.voiceNote?.audioData == syntheticAudioMarker)
        let afterVoiceDeletion = try vault.loadArchive()
        precondition(afterVoiceDeletion.observations.first { $0.id == voiceID } == nil)
        try restartedService.undoRemoval(removedVoice)
        let afterVoiceUndo = try vault.loadArchive()
        precondition(afterVoiceUndo.observations.first { $0.id == voiceID }?.voiceNote?.audioData == syntheticAudioMarker)

        do {
            _ = try VoiceNoteAttachment(audioData: Data(repeating: 0, count: VoiceNoteAttachment.maximumAudioBytes + 1),
                                        spokenLanguage: .english, durationSeconds: 1)
            preconditionFailure("Oversized voice note was accepted")
        } catch ObservationServiceError.invalidVoiceNote {}

        do {
            _ = try VoiceNoteAttachment(audioData: syntheticAudioMarker,
                                        spokenLanguage: .english,
                                        durationSeconds: VoiceNoteAttachment.maximumDuration + 1)
            preconditionFailure("Voice note over the duration limit was accepted")
        } catch ObservationServiceError.invalidVoiceNote {}

        var tampered = try Data(contentsOf: archiveURL)
        tampered[tampered.count - 1] ^= 0x01
        try tampered.write(to: archiveURL, options: [.atomic])
        do {
            _ = try vault.loadArchive()
            preconditionFailure("Vault accepted tampered ciphertext")
        } catch VaultError.invalidArchive {}

        try vault.deleteAll()
        let deletedArchive = try vault.loadArchive()
        precondition(deletedArchive.observations.isEmpty)
        precondition(deletedArchive.processedSourceKeys.isEmpty)
        precondition(!fileManager.fileExists(atPath: archiveURL.path))
        try runDeletionFailureTests(keychain: keychain)
        print("Encrypted vault integration: AES-GCM round trip, voice-note encryption, backup/restore, deletion/Undo and bounds, tamper rejection, idempotent deletion, dual-marker recovery, interrupted-stage restart, Watch replay rejection and concurrent event blocking passed")
    }
}
