import Foundation
import CryptoKit
import Security

enum VaultDeletionStage: Hashable {
    case writeFileIntent
    case writeKeychainIntent
    case deleteContentKey
    case deleteArchive
    case writeCompletedTombstone
    case removeFileIntent
    case removeKeychainIntent
}

private struct VaultEnvelope: Codable {
    let schemaVersion: Int
    let observations: [Observation]
    let processedSourceKeys: [String]?
}

private struct VaultDeletionMarker: Codable {
    let version: Int
    let requestedAt: Date

    init(requestedAt: Date) {
        self.version = 1
        self.requestedAt = requestedAt
    }
}

// iOS-only storage component. Not wired into the fictional web demo.
// Its file is protected while locked and the non-migrating key requires an
// unlocked device. This does not protect plaintext while the app is unlocked.
final class ProtectedObservationVault: ObservationVault {
    private let manager = FileManager.default
    private let fileName = "observations-v1.bin"
    private let keyService: String
    private let keyAccount: String
    private let testKeychainReference: CFTypeRef?
    private let directoryOverride: URL?
    private let deletionStageHook: ((VaultDeletionStage) throws -> Void)?
    private let deletionIntentFileName = "deletion-pending-v1.marker"

    // Injectable locations and Keychain labels let the integration harness
    // exercise AES-GCM with an isolated, disposable Keychain item.
    init(directoryURL: URL? = nil,
         keyService: String = "PD Bridge local observations",
         keyAccount: String = "pd-bridge-observation-key-v1",
         testKeychainReference: CFTypeRef? = nil,
         deletionStageHook: ((VaultDeletionStage) throws -> Void)? = nil) {
        self.directoryOverride = directoryURL
        self.keyService = keyService
        self.keyAccount = keyAccount
        self.testKeychainReference = testKeychainReference
        self.deletionStageHook = deletionStageHook
    }

    private func keychainSearchQuery(_ query: [String: Any]) -> [String: Any] {
        var scoped = query
#if os(macOS)
        if let testKeychainReference {
            scoped[kSecMatchSearchList as String] = [testKeychainReference]
        }
#endif
        return scoped
    }

    private func keychainAddQuery(_ query: [String: Any]) -> [String: Any] {
        var scoped = query
#if os(macOS)
        if let testKeychainReference {
            scoped[kSecUseKeychain as String] = testKeychainReference
        }
#endif
        return scoped
    }

    private var storageDirectory: URL {
        if let directoryOverride { return directoryOverride }
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PD Bridge Observations", isDirectory: true)
    }

    private var fileURL: URL {
        return storageDirectory.appendingPathComponent(fileName)
    }

    private var deletionIntentURL: URL {
        return storageDirectory.appendingPathComponent(deletionIntentFileName)
    }

    private var pendingMarkerAccount: String { keyAccount + ".delete-pending-v1" }
    private var completedMarkerAccount: String { keyAccount + ".delete-complete-v1" }

    private func key(createIfMissing: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(keychainSearchQuery(query) as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            guard data.count == 32 else { throw VaultError.keyUnavailable(errSecDecode) }
            return SymmetricKey(data: data)
        }
        if status != errSecItemNotFound || !createIfMissing { throw VaultError.keyUnavailable(status) }

        var data = Data(count: 32)
        let randomStatus = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw VaultError.keyUnavailable(randomStatus) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(keychainAddQuery(add) as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return try key(createIfMissing: false) }
        guard addStatus == errSecSuccess else { throw VaultError.keyUnavailable(addStatus) }
        return SymmetricKey(data: data)
    }

    private func keychainMarkerData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(keychainSearchQuery(query) as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        if status == errSecItemNotFound { return nil }
        if status == errSecSuccess { throw VaultError.invalidArchive }
        throw VaultError.keyUnavailable(status)
    }

    private func markerDate(account: String) throws -> Date? {
        guard let data = try keychainMarkerData(account: account) else { return nil }
        let marker = try JSONDecoder().decode(VaultDeletionMarker.self, from: data)
        guard marker.version == 1 else { throw VaultError.invalidArchive }
        return marker.requestedAt
    }

    private func writeKeychainMarker(account: String, requestedAt: Date) throws {
        let data = try JSONEncoder().encode(VaultDeletionMarker(requestedAt: requestedAt))
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(keychainAddQuery(add) as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keyService,
                kSecAttrAccount as String: account
            ]
            let updateStatus = SecItemUpdate(keychainSearchQuery(query) as CFDictionary,
                                             [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw VaultError.keyUnavailable(updateStatus) }
        } else if status != errSecSuccess {
            throw VaultError.keyUnavailable(status)
        }
    }

    private func removeKeychainMarker(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(keychainSearchQuery(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keyUnavailable(status)
        }
    }

    private func hasPendingDeletionIntent() throws -> Bool {
        if manager.fileExists(atPath: deletionIntentURL.path) { return true }
        return try keychainMarkerData(account: pendingMarkerAccount) != nil
    }

    private func completedDeletionDate() throws -> Date? {
        return try markerDate(account: completedMarkerAccount)
    }

    /// Writes the intent to two independent stores. Deletion may proceed when
    /// either marker is durable; restart can then resume even if the other
    /// store is temporarily unavailable.
    private func ensureDeletionIntent() throws -> Date {
        let fileDate = (try? Data(contentsOf: deletionIntentURL))
            .flatMap { try? JSONDecoder().decode(VaultDeletionMarker.self, from: $0).requestedAt }
        let keychainDate = try? markerDate(account: pendingMarkerAccount)
        let requestedAt = fileDate ?? keychainDate ?? Date()
        var hasDurableIntent = fileDate != nil || manager.fileExists(atPath: deletionIntentURL.path)
        do {
            if !manager.fileExists(atPath: deletionIntentURL.path) {
                try deletionStageHook?(.writeFileIntent)
                try manager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
#if os(iOS)
                var excluded = URLResourceValues()
                excluded.isExcludedFromBackup = true
                var mutableDirectory = storageDirectory
                try mutableDirectory.setResourceValues(excluded)
                let marker = try JSONEncoder().encode(VaultDeletionMarker(requestedAt: requestedAt))
                try marker.write(to: deletionIntentURL, options: [.atomic, .completeFileProtection])
#else
                try manager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                let marker = try JSONEncoder().encode(VaultDeletionMarker(requestedAt: requestedAt))
                try marker.write(to: deletionIntentURL, options: [.atomic])
#endif
                hasDurableIntent = true
            }
        } catch {
            // The Keychain marker below can independently carry the request.
        }
        do {
            if try markerDate(account: pendingMarkerAccount) != nil {
                hasDurableIntent = true
            } else {
                try deletionStageHook?(.writeKeychainIntent)
                try writeKeychainMarker(account: pendingMarkerAccount, requestedAt: requestedAt)
                hasDurableIntent = true
            }
        } catch {
            // The protected file marker may independently carry the request.
        }
        guard hasDurableIntent else { throw VaultError.deletionIntentUnavailable }
        return requestedAt
    }

    private func deleteContentKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount
        ]
        let status = SecItemDelete(keychainSearchQuery(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keyUnavailable(status)
        }
    }

    private func finishPendingDeletion() throws {
        let requestedAt = try ensureDeletionIntent()

        // The Keychain key and ciphertext file are independent stores. Attempt
        // both even if one fails, then retain the pending intent until both
        // cleanup operations have succeeded.
        var cleanupError: Error?
        do {
            try deletionStageHook?(.deleteContentKey)
            try deleteContentKey()
        } catch {
            cleanupError = error
        }
        do {
            try deletionStageHook?(.deleteArchive)
            if manager.fileExists(atPath: fileURL.path) { try manager.removeItem(at: fileURL) }
        } catch {
            if cleanupError == nil { cleanupError = error }
        }
        if let cleanupError { throw cleanupError }

        // This non-record tombstone prevents queued Watch retries from
        // recreating records captured before deletion. It contains only the
        // deletion time; no observation text or source identifiers are kept.
        try deletionStageHook?(.writeCompletedTombstone)
        try writeKeychainMarker(account: completedMarkerAccount, requestedAt: requestedAt)

        try deletionStageHook?(.removeFileIntent)
        if manager.fileExists(atPath: deletionIntentURL.path) {
            try manager.removeItem(at: deletionIntentURL)
        }

        try deletionStageHook?(.removeKeychainIntent)
        try removeKeychainMarker(account: pendingMarkerAccount)
        try? manager.removeItem(at: storageDirectory)
    }

    func loadArchive() throws -> ObservationArchive {
        if try hasPendingDeletionIntent() {
            do {
                try finishPendingDeletion()
                return ObservationArchive(observations: [], processedSourceKeys: [])
            } catch {
                throw VaultError.deletionPending
            }
        }
        guard manager.fileExists(atPath: fileURL.path) else {
            if try completedDeletionDate() != nil {
                return ObservationArchive(observations: [], processedSourceKeys: [])
            }
            do { _ = try key(createIfMissing: false) }
            catch VaultError.keyUnavailable(let status) where status == errSecItemNotFound {
                return ObservationArchive(observations: [], processedSourceKeys: [])
            }
            throw VaultError.invalidArchive
        }
        if let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber, size.intValue > 32 * 1024 * 1024 {
            throw VaultError.invalidArchive
        }
        let encrypted = try Data(contentsOf: fileURL)
        let encryptionKey = try key(createIfMissing: false)
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let clear = try AES.GCM.open(box, using: encryptionKey)
            let envelope = try JSONDecoder().decode(VaultEnvelope.self, from: clear)
            guard envelope.schemaVersion == 1 || envelope.schemaVersion == 2 else { throw VaultError.invalidArchive }
            guard envelope.schemaVersion != 2 || envelope.processedSourceKeys != nil else {
                throw VaultError.invalidArchive
            }
            let ids = envelope.observations.map(\.id)
            guard Set(ids).count == ids.count else { throw VaultError.invalidArchive }
            guard envelope.observations.allSatisfy(\.hasValidVoiceNote) else { throw VaultError.invalidArchive }
            let observedKeys = envelope.observations.compactMap { item -> String? in
                guard let id = item.sourceRecordID else { return nil }
                return Observation.sourceKey(origin: item.origin, recordID: id)
            }
            guard Set(observedKeys).count == observedKeys.count else { throw VaultError.invalidArchive }
            let storedKeys = envelope.processedSourceKeys ?? []
            guard storedKeys.allSatisfy({ $0.count <= 100 && !$0.isEmpty }) else {
                throw VaultError.invalidArchive
            }
            return ObservationArchive(
                observations: envelope.observations,
                processedSourceKeys: Set(storedKeys).union(observedKeys)
            )
        } catch {
            throw VaultError.invalidArchive
        }
    }

    func saveArchive(_ archive: ObservationArchive, intent: ObservationSaveIntent) throws {
        if try hasPendingDeletionIntent() { throw VaultError.deletionPending }
        let fileExists = manager.fileExists(atPath: fileURL.path)
        if let deletionDate = try completedDeletionDate() {
            if case .watchDelivery(let occurredAt) = intent, occurredAt <= deletionDate {
                throw VaultError.staleWatchEvent
            }
            if !fileExists {
                switch intent {
                case .explicitUserAction:
                    break
                case .ordinary, .watchDelivery:
                    throw VaultError.deletedVaultRequiresUserAction
                }
            }
        }
        if fileExists { _ = try loadArchive() }
        let observations = archive.observations
        let ids = observations.map(\.id)
        guard Set(ids).count == ids.count else { throw VaultError.invalidArchive }
        guard observations.allSatisfy(\.hasValidVoiceNote) else { throw VaultError.invalidArchive }
        let sourceKeys = observations.compactMap { item -> String? in
            guard let recordID = item.sourceRecordID else { return nil }
            return Observation.sourceKey(origin: item.origin, recordID: recordID)
        }
        guard Set(sourceKeys).count == sourceKeys.count else { throw VaultError.invalidArchive }
        guard Set(sourceKeys).isSubset(of: archive.processedSourceKeys) else { throw VaultError.invalidArchive }
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
#if os(iOS)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(excluded)
#endif
        guard archive.processedSourceKeys.allSatisfy({ $0.count <= 100 && !$0.isEmpty }) else {
            throw VaultError.invalidArchive
        }
        let clear = try JSONEncoder().encode(VaultEnvelope(
            schemaVersion: 2,
            observations: observations,
            processedSourceKeys: archive.processedSourceKeys.sorted()
        ))
        guard clear.count <= 32 * 1024 * 1024 else { throw VaultError.invalidArchive }
        let box = try AES.GCM.seal(clear, using: key(createIfMissing: !fileExists))
        guard let combined = box.combined else { throw VaultError.invalidArchive }
#if os(iOS)
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
#else
        try combined.write(to: fileURL, options: [.atomic])
#endif
    }

    func load() throws -> [Observation] { return try loadArchive().observations }

    // Legacy convenience for scaffold callers. Preserve the processed-ID ledger.
    func save(_ observations: [Observation]) throws {
        var archive = try loadArchive()
        archive.observations = observations
        for item in observations {
            if let recordID = item.sourceRecordID {
                archive.processedSourceKeys.insert(Observation.sourceKey(origin: item.origin, recordID: recordID))
            }
        }
        try saveArchive(archive, intent: .explicitUserAction)
    }

    func deleteAll() throws {
        try finishPendingDeletion()
    }
}
