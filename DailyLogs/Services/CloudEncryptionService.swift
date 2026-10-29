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
    var hasRecoveryCode: Bool = false

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
    case invalidRecoveryCode
    case recoveryCodeNotSet

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
        case .invalidRecoveryCode:
            return NSLocalizedString("应急恢复密钥不正确，请检查后再试。", comment: "")
        case .recoveryCodeNotSet:
            return NSLocalizedString("这个账号还没有设置应急恢复密钥。", comment: "")
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

/// The data key encrypted with a key derived from the user's recovery code. Stored in the cloud so
/// a device without the key can unlock with the code; the server never sees the code or the key.
struct CloudRecoveryEnvelope: Codable, Equatable {
    static let currentVersion = 1
    static let currentIterations = 100_000

    var version: Int = Self.currentVersion
    var saltBase64: String
    var iterations: Int = Self.currentIterations
    var wrappedKeyBase64: String
    var createdAt: Date = .now
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

enum SecureCloudMediaReference {
    static let prefix = "dailylogs-secure-media:"

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
        try deriveKey(
            secret: passphrase,
            saltBase64: metadata.saltBase64,
            iterations: metadata.iterations ?? CloudEncryptionMetadata.currentIterations
        )
    }

    /// 24 characters of Crockford base32 (120 random bits) in groups of four.
    func makeRecoveryCode() -> String {
        let alphabet = Array(Self.recoveryCodeAlphabet)
        // 256 is a multiple of 32, so taking each byte modulo 32 keeps every character equally likely.
        let characters = randomData(length: 24).map { alphabet[Int($0) % alphabet.count] }
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }

    /// Ignores case, dashes and spaces, and reads the letters people mistake for digits as those digits.
    static func normalizedRecoveryCode(_ code: String) -> String {
        String(code.uppercased().compactMap { character -> Character? in
            switch character {
            case "O":
                return "0"
            case "I", "L":
                return "1"
            default:
                return recoveryCodeAlphabet.contains(character) ? character : nil
            }
        })
    }

    func wrapKey(_ key: SymmetricKey, recoveryCode: String) throws -> CloudRecoveryEnvelope {
        let saltBase64 = randomData(length: 16).base64EncodedString()
        let wrappingKey = try deriveKey(
            secret: Self.normalizedRecoveryCode(recoveryCode),
            saltBase64: saltBase64,
            iterations: CloudRecoveryEnvelope.currentIterations
        )
        let rawKey = key.withUnsafeBytes { Data($0) }
        return CloudRecoveryEnvelope(
            saltBase64: saltBase64,
            wrappedKeyBase64: try encrypt(data: rawKey, key: wrappingKey).base64EncodedString()
        )
    }

    func unwrapKey(from envelope: CloudRecoveryEnvelope, recoveryCode: String) throws -> SymmetricKey {
        guard let wrappedKey = Data(base64Encoded: envelope.wrappedKeyBase64) else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }
        let wrappingKey = try deriveKey(
            secret: Self.normalizedRecoveryCode(recoveryCode),
            saltBase64: envelope.saltBase64,
            iterations: envelope.iterations
        )
        do {
            return SymmetricKey(data: try decrypt(data: wrappedKey, key: wrappingKey))
        } catch {
            throw CloudSyncSecurityError.invalidRecoveryCode
        }
    }

    private static let recoveryCodeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    private func deriveKey(secret: String, saltBase64: String?, iterations: Int) throws -> SymmetricKey {
        guard let saltBase64,
              let salt = Data(base64Encoded: saltBase64) else {
            throw CloudSyncSecurityError.invalidEncryptedPayload
        }

        let keyData = try pbkdf2SHA256(
            password: Data(secret.utf8),
            salt: salt,
            rounds: iterations,
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

actor SecureCloudMediaLoader {
    static let shared = SecureCloudMediaLoader()

    private let crypto = CloudCryptoService()
    private let keychain = CloudKeychainStore()

    func data(for secureReference: String) async throws -> Data {
        guard let parsed = SecureCloudMediaReference.parse(secureReference) else {
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
        let data = try await storage.reference(withPath: parsed.path).getDataAsync(maxSize: 120 * 1024 * 1024)
        return try crypto.decrypt(data: data, key: key)
    }

    private func userID(fromStoragePath path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count >= 2, components[0] == "users" else { return nil }
        return String(components[1])
    }
}
