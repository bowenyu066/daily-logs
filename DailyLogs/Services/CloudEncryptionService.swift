import CommonCrypto
import CryptoKit
import FirebaseCore
import FirebaseStorage
import Foundation
import Security
import UIKit

struct CloudProtectionSnapshot: Equatable {
    enum Mode: Equatable {
        case unavailable
        case disabled
        case enabled
    }

    var mode: Mode
    var localKeyAvailable: Bool
    var hasLegacyPlaintextData: Bool = false

    var isLocked: Bool {
        mode == .enabled && !localKeyAvailable
    }

    var isUnlocked: Bool {
        mode == .enabled && localKeyAvailable
    }

    var requiresMigration: Bool {
        mode == .disabled && hasLegacyPlaintextData
    }
}

enum CloudSyncSecurityError: LocalizedError, Equatable {
    case encryptedSyncLocked
    case invalidPassphrase
    case invalidEncryptedPayload
    case firebaseUnavailable
    case keychainSyncUnavailable

    var errorDescription: String? {
        switch self {
        case .encryptedSyncLocked:
            return NSLocalizedString("这台设备还没拿到云端密钥，请检查 iCloud 钥匙串。", comment: "")
        case .invalidPassphrase:
            return NSLocalizedString("同步密码不正确，无法解锁加密数据。", comment: "")
        case .invalidEncryptedPayload:
            return NSLocalizedString("云端加密数据格式不可读。", comment: "")
        case .firebaseUnavailable:
            return NSLocalizedString("Firebase 还没有正确初始化。", comment: "")
        case .keychainSyncUnavailable:
            return NSLocalizedString("iCloud 钥匙串暂时不可用，稍后再试。", comment: "")
        }
    }
}

enum CloudKeyProvider: String, Codable, Equatable {
    case synchronizableKeychain
    case passphrase
}

struct CloudEncryptionMetadata: Codable, Equatable {
    static let currentVersion = 2
    static let currentIterations = 600_000

    var version: Int = Self.currentVersion
    var algorithm: String = "AES-GCM-256"
    var keyProvider: CloudKeyProvider = .synchronizableKeychain
    var keyID: String?
    var saltBase64: String?
    var iterations: Int?
    var enabledAt: Date = .now
}

struct CloudEncryptedEnvelope: Codable, Equatable {
    var version: Int = CloudEncryptionMetadata.currentVersion
    var combinedBase64: String
}

struct CloudMigrationProgress: Equatable, Sendable {
    var fractionCompleted: Double
    var message: String
}

enum SecureCloudPhotoReference {
    static let prefix = "dailylogs-secure-photo:"

    static func make(bucket: String, path: String) -> String {
        prefix + bucket + "|" + path
    }

    static func isSecureReference(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    static func parse(_ value: String) -> (bucket: String, path: String)? {
        guard value.hasPrefix(prefix) else { return nil }
        let payload = String(value.dropFirst(prefix.count))
        let components = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2, !components[0].isEmpty, !components[1].isEmpty else { return nil }
        return (bucket: components[0], path: components[1])
    }
}

struct CloudCryptoService {
    func makeMetadata() -> CloudEncryptionMetadata {
        makePassphraseMetadata()
    }

    func makeSynchronizableMetadata() -> CloudEncryptionMetadata {
        CloudEncryptionMetadata(
            algorithm: "AES-GCM-256",
            keyProvider: .synchronizableKeychain,
            keyID: UUID().uuidString,
            saltBase64: nil,
            iterations: nil
        )
    }

    func makeRandomKey() -> SymmetricKey {
        SymmetricKey(data: randomData(length: 32))
    }

    func makePassphraseMetadata() -> CloudEncryptionMetadata {
        let salt = randomData(length: 16).base64EncodedString()
        return CloudEncryptionMetadata(
            algorithm: "PBKDF2-SHA256-AES-GCM-256",
            keyProvider: .passphrase,
            keyID: nil,
            saltBase64: salt,
            iterations: CloudEncryptionMetadata.currentIterations
        )
    }

    func deriveKey(passphrase: String, metadata: CloudEncryptionMetadata) throws -> SymmetricKey {
        guard let saltBase64 = metadata.saltBase64,
              let salt = Data(base64Encoded: saltBase64) else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }

        let passphraseData = Data(passphrase.utf8)
        let keyData = try pbkdf2SHA256(
            password: passphraseData,
            salt: salt,
            rounds: metadata.iterations ?? CloudEncryptionMetadata.currentIterations,
            keyByteCount: 32
        )
        return SymmetricKey(data: keyData)
    }

    func encrypt<Value: Encodable>(_ value: Value, key: SymmetricKey) throws -> CloudEncryptedEnvelope {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try CloudEncryptedEnvelope(combinedBase64: encrypt(data: data, key: key).base64EncodedString())
    }

    func decrypt<Value: Decodable>(_ type: Value.Type, from envelope: CloudEncryptedEnvelope, key: SymmetricKey) throws -> Value {
        guard let data = Data(base64Encoded: envelope.combinedBase64) else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }
        let decrypted = try decrypt(data: data, key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: decrypted)
    }

    func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }
        return combined
    }

    func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw CloudSyncSecurityError.invalidPassphrase
        }
    }

    private func randomData(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes)
    }

    private func pbkdf2SHA256(password: Data, salt: Data, rounds: Int, keyByteCount: Int) throws -> Data {
        var derived = [UInt8](repeating: 0, count: keyByteCount)

        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    &derived,
                    keyByteCount
                )
            }
        }

        guard status == kCCSuccess else {
            throw CocoaError(.coderInvalidValue)
        }

        return Data(derived)
    }
}

struct CloudKeychainStore {
    private let localService = "com.flyfishyu.DailyLogs.cloud.encryption.local"
    private let syncService = "com.flyfishyu.DailyLogs.cloud.encryption.sync"

    func saveKey(_ key: SymmetricKey, for userID: String, synchronizable: Bool) throws {
        let raw = key.withUnsafeBytes { Data($0) }
        let query = baseQuery(for: userID, synchronizable: synchronizable)

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = raw
        attributes[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            if synchronizable {
                throw CloudSyncSecurityError.keychainSyncUnavailable
            }
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func loadKey(for userID: String) -> SymmetricKey? {
        loadKey(for: userID, synchronizable: true) ?? loadKey(for: userID, synchronizable: false)
    }

    func loadSynchronizableKey(for userID: String) -> SymmetricKey? {
        loadKey(for: userID, synchronizable: true)
    }

    func loadLocalKey(for userID: String) -> SymmetricKey? {
        loadKey(for: userID, synchronizable: false)
    }

    func deleteKey(for userID: String) {
        SecItemDelete(baseQuery(for: userID, synchronizable: true) as CFDictionary)
        SecItemDelete(baseQuery(for: userID, synchronizable: false) as CFDictionary)
    }

    private func loadKey(for userID: String, synchronizable: Bool) -> SymmetricKey? {
        var query = baseQuery(for: userID, synchronizable: synchronizable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private func baseQuery(for userID: String, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: synchronizable ? syncService : localService,
            kSecAttrAccount as String: userID
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }
}

actor SecureCloudPhotoLoader {
    static let shared = SecureCloudPhotoLoader()

    private let crypto = CloudCryptoService()
    private let keychain = CloudKeychainStore()

    func image(for secureReference: String) async -> UIImage? {
        guard let data = try? await data(for: secureReference),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    func data(for secureReference: String) async throws -> Data {
        guard let parsed = SecureCloudPhotoReference.parse(secureReference) else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }
        let userID = userID(fromStoragePath: parsed.path)
        guard let userID, let key = keychain.loadKey(for: userID) else {
            throw CloudSyncSecurityError.encryptedSyncLocked
        }

        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured else {
            throw CloudSyncSecurityError.firebaseUnavailable
        }

        let storage = Storage.storage(url: "gs://\(parsed.bucket)")
        let data = try await storage.reference(withPath: parsed.path).getDataAsync(maxSize: 20 * 1024 * 1024)
        return try crypto.decrypt(data: data, key: key)
    }

    private func userID(fromStoragePath path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count >= 2, components[0] == "users" else { return nil }
        return String(components[1])
    }
}
