import Foundation
import CryptoKit
import CommonCrypto
import Security

enum ObservationBackupError: Error {
    case weakPassphrase
    case malformedFile
    case unsupportedVersion
    case recordConflict
    case keyDerivationFailed(Int32)
}

private struct BackupContainer: Codable {
    let formatVersion: Int
    let salt: Data
    let sealedArchive: Data
}

private struct BackupArchive: Codable {
    let formatVersion: Int
    let observations: [Observation]
    let processedSourceKeys: [String]
}

/// Encrypted, user-initiated backup. The passphrase is never saved by this
/// type; the exported file contains authenticated ciphertext only.
enum ObservationBackup {
    private static let context = Data("PD Bridge encrypted observation backup v1".utf8)
    private static let saltLength = 16
    private static let keyLength = 32
    private static let rounds: UInt32 = 310_000
    private static let maximumFileSize = 32 * 1024 * 1024

    static func seal(_ archive: ObservationArchive, passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw ObservationBackupError.weakPassphrase }
        try validate(archive)
        var salt = Data(count: saltLength)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw ObservationBackupError.keyDerivationFailed(randomStatus)
        }
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let plaintext = try JSONEncoder().encode(BackupArchive(
            formatVersion: 1,
            observations: archive.observations,
            processedSourceKeys: archive.processedSourceKeys.sorted()
        ))
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context)
        guard let combined = box.combined else { throw ObservationBackupError.malformedFile }
        let output = try JSONEncoder().encode(BackupContainer(
            formatVersion: 1, salt: salt, sealedArchive: combined
        ))
        guard output.count <= maximumFileSize else { throw ObservationBackupError.malformedFile }
        return output
    }

    static func open(_ data: Data, passphrase: String) throws -> ObservationArchive {
        guard passphrase.count >= 12 else { throw ObservationBackupError.weakPassphrase }
        guard data.count <= maximumFileSize,
              let container = try? JSONDecoder().decode(BackupContainer.self, from: data),
              container.salt.count == saltLength,
              container.sealedArchive.count >= 28 else {
            throw ObservationBackupError.malformedFile
        }
        guard container.formatVersion == 1 else { throw ObservationBackupError.unsupportedVersion }
        let key = try deriveKey(passphrase: passphrase, salt: container.salt)
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: container.sealedArchive)
            let clear = try AES.GCM.open(box, using: key, authenticating: context)
            let payload = try JSONDecoder().decode(BackupArchive.self, from: clear)
            guard payload.formatVersion == 1 else { throw ObservationBackupError.unsupportedVersion }
            let archive = ObservationArchive(
                observations: payload.observations,
                processedSourceKeys: Set(payload.processedSourceKeys)
            )
            try validate(archive)
            return archive
        } catch let error as ObservationBackupError {
            throw error
        } catch {
            throw ObservationBackupError.malformedFile
        }
    }

    /// Imports merge by record ID and opaque source ID. Existing entries are
    /// never overwritten; conflicting IDs fail closed for user review.
    static func merge(_ incoming: ObservationArchive, into existing: ObservationArchive) throws -> ObservationArchive {
        try validate(incoming)
        try validate(existing)
        var result = existing
        let existingByID = Dictionary(uniqueKeysWithValues: existing.observations.map { ($0.id, $0) })
        let existingSourceKeys = existing.processedSourceKeys
        for item in incoming.observations {
            if let current = existingByID[item.id] {
                guard current == item else { throw ObservationBackupError.recordConflict }
                continue
            }
            if let sourceID = item.sourceRecordID {
                let key = Observation.sourceKey(origin: item.origin, recordID: sourceID)
                if existingSourceKeys.contains(key) { continue }
            }
            result.observations.append(item)
        }
        result.processedSourceKeys.formUnion(incoming.processedSourceKeys)
        try validate(result)
        return result
    }

    private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        var output = Data(count: keyLength)
        let status = passphrase.withCString { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passphrase.utf8.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        outputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ObservationBackupError.keyDerivationFailed(status) }
        return SymmetricKey(data: output)
    }

    private static func validate(_ archive: ObservationArchive) throws {
        let ids = archive.observations.map(\.id)
        guard Set(ids).count == ids.count else { throw ObservationBackupError.malformedFile }
        guard archive.observations.allSatisfy(\.hasValidVoiceNote) else {
            throw ObservationBackupError.malformedFile
        }
        let sourceKeys = archive.observations.compactMap { item -> String? in
            guard let sourceID = item.sourceRecordID else { return nil }
            return Observation.sourceKey(origin: item.origin, recordID: sourceID)
        }
        guard Set(sourceKeys).count == sourceKeys.count,
              Set(sourceKeys).isSubset(of: archive.processedSourceKeys),
              archive.processedSourceKeys.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else {
            throw ObservationBackupError.malformedFile
        }
    }
}
