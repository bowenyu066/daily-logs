import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import CryptoKit
import Foundation

struct CloudBootstrapPayload {
    var profile: UserProfile?
    var preferences: UserPreferences?
    var records: [DailyRecord]
}

protocol CloudSyncService: Sendable {
    var isAvailable: Bool { get }
    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload
    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws
    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws
    func pushProfile(_ user: UserAccount) async throws
    func deletePhotoReference(_ photoReference: String, user: UserAccount) async throws
    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot
    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws
    /// Local media file names mapped to the cloud references they were uploaded as.
    func uploadedMediaReferences(for user: UserAccount) async -> [String: String]
    /// Stores the data key encrypted with a new recovery code and returns the code. A code created
    /// earlier stops working.
    func createRecoveryCode(for user: UserAccount) async throws -> String
    /// Unlocks encrypted sync on this device with a recovery code and saves the key to the keychain.
    func unlock(withRecoveryCode code: String, user: UserAccount) async throws
}

extension CloudSyncService {
    func uploadedMediaReferences(for user: UserAccount) async -> [String: String] {
        [:]
    }

    func createRecoveryCode(for user: UserAccount) async throws -> String {
        throw CloudSyncSecurityError.firebaseUnavailable
    }

    func unlock(withRecoveryCode code: String, user: UserAccount) async throws {
        throw CloudSyncSecurityError.firebaseUnavailable
    }
}

/// Requests the security rules rejected because they were not made with the account's own sign-in.
enum CloudAuthorizationFailure {
    static func matches(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case FirestoreErrorDomain:
            return nsError.code == FirestoreErrorCode.permissionDenied.rawValue
                || nsError.code == FirestoreErrorCode.unauthenticated.rawValue
        case StorageErrorDomain:
            return nsError.code == StorageErrorCode.unauthorized.rawValue
                || nsError.code == StorageErrorCode.unauthenticated.rawValue
        default:
            return false
        }
    }
}

extension DailyRecord {
    /// The record as it looks once pushed: local photo and video paths that were already uploaded
    /// are replaced by their cloud references.
    func replacingUploadedMediaReferences(_ uploadedReferences: [String: String]) -> DailyRecord {
        guard !uploadedReferences.isEmpty else { return self }
        var updated = self
        for index in updated.meals.indices {
            updated.meals[index].photoURLs = updated.meals[index].photoURLs.map {
                CloudMediaReferenceMap.localKey(for: $0).flatMap { uploadedReferences[$0] } ?? $0
            }
        }
        if var dailyVideo = updated.dailyVideo,
           let uploadedVideoReference = CloudMediaReferenceMap.localKey(for: dailyVideo.videoURL).flatMap({ uploadedReferences[$0] }) {
            dailyVideo.videoURL = uploadedVideoReference
            updated.dailyVideo = dailyVideo
        }
        return updated
    }
}

struct NoopCloudSyncService: CloudSyncService {
    var isAvailable: Bool { false }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {}

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {}

    func pushProfile(_ user: UserAccount) async throws {}

    func deletePhotoReference(_ photoReference: String, user: UserAccount) async throws {}

    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot {
        CloudProtectionSnapshot(mode: .unavailable, localKeyAvailable: false)
    }

    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws {}
}

final class FirebaseCloudSyncService: CloudSyncService, Sendable {
    private let crypto = CloudCryptoService()
    private let keychain = CloudKeychainStore()
    private let session = CloudSessionCache()
    private let mediaReferences = CloudMediaReferenceMap()

    private var db: Firestore? {
        FirebaseBootstrap.configureIfPossible()
        return FirebaseBootstrap.isConfigured ? Firestore.firestore() : nil
    }

    private var storages: [Storage] {
        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured, let app = FirebaseApp.app() else { return [] }

        var bucketCandidates: [String] = []
        if let configuredBucket = app.options.storageBucket?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredBucket.isEmpty {
            bucketCandidates.append(configuredBucket)
        }

        if let projectID = app.options.projectID {
            bucketCandidates.append("\(projectID).firebasestorage.app")
            bucketCandidates.append("\(projectID).appspot.com")
        }

        var storages: [Storage] = []
        var seenBucketURLs = Set<String>()

        for bucket in bucketCandidates {
            let bucketURL = bucket.hasPrefix("gs://") ? bucket : "gs://\(bucket)"
            guard seenBucketURLs.insert(bucketURL).inserted else { continue }
            storages.append(Storage.storage(url: bucketURL))
        }

        if seenBucketURLs.insert("__default__").inserted {
            storages.append(Storage.storage())
        }

        return storages
    }

    var isAvailable: Bool {
        db != nil
    }

    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot {
        guard db != nil else {
            return CloudProtectionSnapshot(mode: .unavailable, localKeyAvailable: false)
        }

        let metadata = try await fetchEncryptionMetadata(for: user)
        return CloudProtectionSnapshot(
            mode: metadata == nil ? .disabled : .enabled,
            localKeyAvailable: try await usableKey(for: user, metadata: metadata) != nil,
            hasLegacyPlaintextData: try await hasLegacyPlaintextData(for: user),
            hasRecoveryCode: metadata == nil ? false : try await fetchRecoveryEnvelope(for: user) != nil
        )
    }

    func createRecoveryCode(for user: UserAccount) async throws -> String {
        guard let db else {
            throw CloudSyncSecurityError.firebaseUnavailable
        }
        guard let metadata = try await fetchEncryptionMetadata(for: user),
              let key = try await usableKey(for: user, metadata: metadata) else {
            throw CloudSyncSecurityError.encryptedSyncLocked
        }
        let code = crypto.makeRecoveryCode()
        let envelope = try crypto.wrapKey(key, recoveryCode: code)
        try await recoveryDocument(in: db, for: user).setData(try encode(envelope))
        return code
    }

    func unlock(withRecoveryCode code: String, user: UserAccount) async throws {
        guard db != nil else {
            throw CloudSyncSecurityError.firebaseUnavailable
        }
        guard let envelope = try await fetchRecoveryEnvelope(for: user) else {
            throw CloudSyncSecurityError.recoveryCodeNotSet
        }
        let key = try crypto.unwrapKey(from: envelope, recoveryCode: code)
        guard try await canDecryptCloudData(using: key, for: user) else {
            throw CloudSyncSecurityError.invalidRecoveryCode
        }
        // Saved to iCloud Keychain when possible so the user's other devices get it too.
        do {
            try keychain.saveKey(key, for: user.userID, synchronizable: true)
        } catch {
            try keychain.saveKey(key, for: user.userID, synchronizable: false)
        }
        session.storeKey(key, for: user.userID)
    }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        guard let db else {
            return CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
        }

        // A refresh re-validates the encryption state; routine pushes reuse what it established.
        session.invalidate(userID: user.userID)
        let encryptionMetadata = try await fetchEncryptionMetadata(for: user)
        let hasLegacyPlaintext = try await hasLegacyPlaintextData(for: user)
        guard encryptionMetadata != nil || hasLegacyPlaintext else {
            return CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
        }

        try await upsertProfile(user, encrypted: encryptionMetadata != nil)

        if encryptionMetadata != nil {
            guard let metadata = encryptionMetadata,
                  let key = try await usableKey(for: user, metadata: metadata) else {
                throw CloudSyncSecurityError.encryptedSyncLocked
            }

            let userRef = db.collection("users").document(user.userID)
            async let profileSnapshot = userRef.collection("secureProfile").document("current").getDocument()
            async let prefsSnapshot = userRef.collection("securePreferences").document("current").getDocument()
            async let encryptedRecords = loadEncryptedRecords(user: user, key: key, registrationDate: user.createdAt)

            let remoteProfile = try decryptDocument(UserProfile.self, from: try await profileSnapshot.data(), key: key)
            let prefsDocument = try await prefsSnapshot
            let remotePreferences = try decryptDocument(UserPreferences.self, from: prefsDocument.data(), key: key)
            let remoteRecords = try await encryptedRecords

            if prefsDocument.exists == false {
                try await pushEncryptedPreferences(localPreferences, user: user, key: key)
            }

            if remoteRecords.isEmpty && !localRecords.isEmpty {
                for record in localRecords {
                    try await pushEncryptedRecord(record, user: user, key: key)
                }
            }

            return CloudBootstrapPayload(
                profile: remoteProfile,
                preferences: remotePreferences,
                records: remoteRecords
            )
        }

        let userRef = db.collection("users").document(user.userID)
        async let profileSnapshot = userRef.getDocument()
        async let prefsSnapshot = userRef.collection("preferences").document("current").getDocument()
        async let plaintextRecords = loadPlaintextRecords(user: user, registrationDate: user.createdAt)

        let remoteProfile = try await profileSnapshot.data().flatMap { try decode(UserProfile.self, from: $0) }
        let prefsDocument = try await prefsSnapshot
        let remotePreferences = try prefsDocument.data().flatMap { try decode(UserPreferences.self, from: $0) }
        let remoteRecords = try await plaintextRecords

        if prefsDocument.exists == false {
            try await pushPreferences(localPreferences, user: user)
        }

        if remoteRecords.isEmpty && !localRecords.isEmpty {
            for record in localRecords {
                try await pushRecord(record, user: user)
            }
        }

        return CloudBootstrapPayload(
            profile: remoteProfile,
            preferences: remotePreferences,
            records: remoteRecords
        )
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {
        guard let db else { return }
        if let metadata = try await fetchEncryptionMetadata(for: user) {
            guard let key = try await usableKey(for: user, metadata: metadata) else {
                throw CloudSyncSecurityError.encryptedSyncLocked
            }
            try await pushEncryptedPreferences(preferences, user: user, key: key)
            try await upsertProfile(user, encrypted: true)
            return
        }
        let userRef = db.collection("users").document(user.userID)
        try await userRef.collection("preferences").document("current").setData(try encode(preferences))
        try await upsertProfile(user, encrypted: false)
    }

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {
        guard let db else { return }
        if let metadata = try await fetchEncryptionMetadata(for: user) {
            guard let key = try await usableKey(for: user, metadata: metadata) else {
                throw CloudSyncSecurityError.encryptedSyncLocked
            }
            try await pushEncryptedRecord(record, user: user, key: key)
            try await upsertProfile(user, encrypted: true)
            return
        }
        let userRef = db.collection("users").document(user.userID)
        let canonicalKey = record.canonicalStorageKey(fallback: record.date.storageKey())
        let anchoredRecord = record.anchoredToStorageKey(canonicalKey)
        let cloudReadyRecord = try await preparedPlaintextRecord(anchoredRecord, userID: user.userID)
        try await userRef.collection("records").document(canonicalKey).setData(try encode(cloudReadyRecord))
        try await upsertProfile(user, encrypted: false)
    }

    func pushProfile(_ user: UserAccount) async throws {
        if let metadata = try await fetchEncryptionMetadata(for: user) {
            guard let key = try await usableKey(for: user, metadata: metadata) else {
                throw CloudSyncSecurityError.encryptedSyncLocked
            }
            try await pushEncryptedProfile(user, key: key)
            try await upsertProfile(user, encrypted: true)
            return
        }
        try await upsertProfile(user, encrypted: false)
    }

    func deletePhotoReference(_ photoReference: String, user: UserAccount) async throws {
        guard !storages.isEmpty else { return }

        if let localKey = CloudMediaReferenceMap.localKey(for: photoReference) {
            for uploadedReference in await mediaReferences.removeReferences(forLocalKey: localKey, userID: user.userID) {
                try? await deletePhotoReference(uploadedReference, user: user)
            }
            return
        }

        // A local file mapped to this object must be uploaded again the next time it is pushed.
        await mediaReferences.forgetUploadedReference(photoReference, userID: user.userID)

        if SecureCloudPhotoReference.isSecureReference(photoReference) {
            try await deleteSecurePhoto(at: photoReference)
            return
        }

        if photoReference.hasPrefix("http://") || photoReference.hasPrefix("https://") {
            try await deleteLegacyPhoto(at: photoReference)
        }
    }

    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws {
        guard db != nil else {
            throw CloudSyncSecurityError.firebaseUnavailable
        }

        await progress(CloudMigrationProgress(fractionCompleted: 0.05, message: NSLocalizedString("正在检查旧数据…", comment: "")))
        let legacyPayload = try await legacyPlaintextPayload(for: user)
        let mergedPreferences = legacyPayload.preferences ?? localPreferences
        let mergedRecords = mergeRecords(localRecords, with: legacyPayload.records)

        let metadata = crypto.makeSynchronizableMetadata()
        let key = crypto.makeRandomKey()
        try keychain.saveKey(key, for: user.userID, synchronizable: true)

        await progress(CloudMigrationProgress(fractionCompleted: 0.14, message: NSLocalizedString("正在创建密钥…", comment: "")))
        try await pushEncryptedProfile(user, key: key)
        await progress(CloudMigrationProgress(fractionCompleted: 0.28, message: NSLocalizedString("正在加密设置…", comment: "")))
        try await pushEncryptedPreferences(mergedPreferences, user: user, key: key)

        let totalRecords = max(mergedRecords.count, 1)
        for (index, record) in mergedRecords.enumerated() {
            let fraction = 0.28 + (Double(index) / Double(totalRecords)) * 0.54
            await progress(CloudMigrationProgress(
                fractionCompleted: min(fraction, 0.82),
                message: String(format: NSLocalizedString("正在迁移 %d/%d…", comment: ""), index + 1, totalRecords)
            ))
            try await pushEncryptedRecord(record, user: user, key: key)
        }
        await progress(CloudMigrationProgress(fractionCompleted: 0.88, message: NSLocalizedString("正在切换加密存储…", comment: "")))
        try await writeEncryptionMetadata(metadata, for: user)
        session.storeMetadata(metadata, for: user.userID)
        session.storeKey(key, for: user.userID)
        try await upsertProfile(user, encrypted: true)
        await progress(CloudMigrationProgress(fractionCompleted: 0.95, message: NSLocalizedString("正在清理旧数据…", comment: "")))
        try await deleteLegacyPlaintextCloudData(for: user)
        await progress(CloudMigrationProgress(fractionCompleted: 1.0, message: NSLocalizedString("迁移完成。", comment: "")))
    }

    private func upsertProfile(_ user: UserAccount, encrypted: Bool) async throws {
        guard let db else { return }
        let profileSignature = [user.userID, user.authMode.rawValue, user.createdAt.displayISO8601, String(encrypted), user.displayName, user.email ?? ""]
            .joined(separator: "|")
        // The profile document only changes when one of these fields does; rewriting it on every
        // record push just refreshed `updatedAt`.
        guard session.shouldUpsertProfile(signature: profileSignature, userID: user.userID) else { return }
        let payload: [String: Any] = [
            "userID": user.userID,
            "authMode": user.authMode.rawValue,
            "createdAt": user.createdAt.displayISO8601,
            "updatedAt": Date().displayISO8601,
            "cloudProtectionMode": encrypted ? "e2ee" : "plaintext",
            "cloudProtectionVersion": encrypted ? CloudEncryptionMetadata.currentVersion : 0
        ]
        if encrypted {
            try await db.collection("users").document(user.userID).setData(payload)
        } else {
            var plaintextPayload = payload
            plaintextPayload["displayName"] = user.displayName
            plaintextPayload["email"] = user.email as Any
            try await db.collection("users").document(user.userID).setData(plaintextPayload, merge: true)
        }
        session.recordProfileUpsert(signature: profileSignature, userID: user.userID)
    }

    private func preparedPlaintextRecord(_ record: DailyRecord, userID: String) async throws -> DailyRecord {
        guard !storages.isEmpty else { return record }
        var updated = record
        let recordKey = updated.canonicalStorageKey(fallback: updated.date.storageKey())
        for index in updated.meals.indices {
            var uploadedPhotoURLs: [String] = []
            for (photoIndex, photoURL) in updated.meals[index].photoURLs.enumerated() {
                guard !photoURL.hasPrefix("http://"), !photoURL.hasPrefix("https://") else {
                    uploadedPhotoURLs.append(photoURL)
                    continue
                }
                guard !SecureCloudPhotoReference.isSecureReference(photoURL) else {
                    uploadedPhotoURLs.append(photoURL)
                    continue
                }
                let localKey = CloudMediaReferenceMap.localKey(for: photoURL)
                if let localKey,
                   let uploadedPhotoURL = await mediaReferences.reference(forLocalKey: localKey, userID: userID, mode: .plaintext) {
                    uploadedPhotoURLs.append(uploadedPhotoURL)
                    continue
                }
                guard let localPhotoURL = LocalPhotoStorageService.resolvedURL(for: photoURL) else {
                    continue
                }
                do {
                    let data = try Data(contentsOf: localPhotoURL)
                    let filename = "\(updated.meals[index].id.uuidString)-\(Self.uploadNameComponent(for: localKey, fallbackIndex: photoIndex)).jpg"
                    let path = "users/\(userID)/meal-photos/\(filename)"
                    let meta = StorageMetadata()
                    meta.contentType = "image/jpeg"
                    let uploadedPhotoURL = try await uploadPhoto(
                        data: data,
                        storagePath: path,
                        metadata: meta
                    )
                    uploadedPhotoURLs.append(uploadedPhotoURL)
                    if let localKey {
                        await mediaReferences.store(uploadedPhotoURL, forLocalKey: localKey, userID: userID, mode: .plaintext)
                    }
                } catch {
                    #if DEBUG
                    print(
                        "CloudSync: photo upload failed for meal \(updated.meals[index].id) " +
                        "at path users/\(userID)/meal-photos/\(updated.meals[index].id.uuidString)-\(photoIndex).jpg: \(error)"
                    )
                    #endif
                }
            }
            updated.meals[index].photoURLs = uploadedPhotoURLs
        }
        if var dailyVideo = updated.dailyVideo,
           let localKey = CloudMediaReferenceMap.localKey(for: dailyVideo.videoURL),
           let uploadedVideoURL = await mediaReferences.reference(forLocalKey: localKey, userID: userID, mode: .plaintext) {
            dailyVideo.videoURL = uploadedVideoURL
            updated.dailyVideo = dailyVideo
        } else if var dailyVideo = updated.dailyVideo,
           !dailyVideo.videoURL.hasPrefix("http://"),
           !dailyVideo.videoURL.hasPrefix("https://"),
           !SecureCloudMediaReference.isSecureReference(dailyVideo.videoURL),
           let localVideoURL = LocalVideoStorageService.resolvedURL(for: dailyVideo.videoURL) {
            let localKey = CloudMediaReferenceMap.localKey(for: dailyVideo.videoURL)
            do {
                let data = try Data(contentsOf: localVideoURL)
                let path = "users/\(userID)/daily-videos/\(recordKey).mp4"
                let meta = StorageMetadata()
                meta.contentType = "video/mp4"
                dailyVideo.videoURL = try await uploadPhoto(
                    data: data,
                    storagePath: path,
                    metadata: meta
                )
                updated.dailyVideo = dailyVideo
                if let localKey {
                    await mediaReferences.store(dailyVideo.videoURL, forLocalKey: localKey, userID: userID, mode: .plaintext)
                }
            } catch {
                #if DEBUG
                print("CloudSync: video upload failed for record \(recordKey): \(error)")
                #endif
            }
        }
        return updated
    }

    private func pushEncryptedPreferences(_ preferences: UserPreferences, user: UserAccount, key: SymmetricKey) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        let envelope = try crypto.encrypt(preferences, key: key)
        try await userRef.collection("securePreferences").document("current").setData(try encode(envelope))
    }

    private func pushEncryptedProfile(_ user: UserAccount, key: SymmetricKey) async throws {
        guard let db else { return }
        let profile = UserProfile(
            userID: user.userID,
            displayName: user.displayName,
            email: user.email,
            authMode: user.authMode,
            createdAt: user.createdAt
        )
        let envelope = try crypto.encrypt(profile, key: key)
        try await db.collection("users").document(user.userID).collection("secureProfile").document("current").setData(try encode(envelope))
    }

    private func pushEncryptedRecord(_ record: DailyRecord, user: UserAccount, key: SymmetricKey) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        let canonicalKey = record.canonicalStorageKey(fallback: record.date.storageKey())
        let anchoredRecord = record.anchoredToStorageKey(canonicalKey)
        let cloudReadyRecord = try await preparedEncryptedRecord(anchoredRecord, userID: user.userID, key: key)
        let envelope = try crypto.encrypt(cloudReadyRecord, key: key)
        try await userRef.collection("secureRecords").document(canonicalKey).setData(try encode(envelope))
    }

    private func preparedEncryptedRecord(_ record: DailyRecord, userID: String, key: SymmetricKey) async throws -> DailyRecord {
        guard !storages.isEmpty else { return record }
        var updated = record
        let recordKey = updated.canonicalStorageKey(fallback: updated.date.storageKey())
        for index in updated.meals.indices {
            var encryptedPhotoReferences: [String] = []
            for (photoIndex, photoReference) in updated.meals[index].photoURLs.enumerated() {
                guard !SecureCloudPhotoReference.isSecureReference(photoReference) else {
                    encryptedPhotoReferences.append(photoReference)
                    continue
                }
                let localKey = CloudMediaReferenceMap.localKey(for: photoReference)
                if let localKey,
                   let uploadedReference = await mediaReferences.reference(forLocalKey: localKey, userID: userID, mode: .encrypted) {
                    encryptedPhotoReferences.append(uploadedReference)
                    continue
                }
                guard let data = try await loadPhotoData(for: photoReference) else {
                    continue
                }

                do {
                    let filename = "\(updated.meals[index].id.uuidString)-\(Self.uploadNameComponent(for: localKey, fallbackIndex: photoIndex)).bin"
                    let path = "users/\(userID)/secure-meal-photos/\(filename)"
                    let encryptedReference = try await uploadEncryptedPhoto(
                        data: data,
                        storagePath: path,
                        key: key
                    )
                    encryptedPhotoReferences.append(encryptedReference)
                    if let localKey {
                        await mediaReferences.store(encryptedReference, forLocalKey: localKey, userID: userID, mode: .encrypted)
                    }
                    if photoReference.hasPrefix("http://") || photoReference.hasPrefix("https://") {
                        try? await deleteLegacyPhoto(at: photoReference)
                    }
                } catch {
                    #if DEBUG
                    print("CloudSync: encrypted photo upload failed for meal \(updated.meals[index].id): \(error)")
                    #endif
                }
            }
            updated.meals[index].photoURLs = encryptedPhotoReferences
        }
        if var dailyVideo = updated.dailyVideo,
           let localKey = CloudMediaReferenceMap.localKey(for: dailyVideo.videoURL),
           let uploadedReference = await mediaReferences.reference(forLocalKey: localKey, userID: userID, mode: .encrypted) {
            dailyVideo.videoURL = uploadedReference
            updated.dailyVideo = dailyVideo
        } else if var dailyVideo = updated.dailyVideo,
           !SecureCloudMediaReference.isSecureReference(dailyVideo.videoURL),
           let data = try await loadVideoData(for: dailyVideo.videoURL) {
            let localKey = CloudMediaReferenceMap.localKey(for: dailyVideo.videoURL)
            do {
                let path = "users/\(userID)/secure-daily-videos/\(recordKey).bin"
                dailyVideo.videoURL = try await uploadEncryptedVideo(
                    data: data,
                    storagePath: path,
                    key: key
                )
                updated.dailyVideo = dailyVideo
                if let localKey {
                    await mediaReferences.store(dailyVideo.videoURL, forLocalKey: localKey, userID: userID, mode: .encrypted)
                }
            } catch {
                #if DEBUG
                print("CloudSync: encrypted video upload failed for record \(recordKey): \(error)")
                #endif
            }
        }
        return updated
    }

    private func uploadPhoto(data: Data, storagePath: String, metadata: StorageMetadata) async throws -> String {
        var lastError: Error?

        for storage in storages {
            let ref = storage.reference().child(storagePath)
            do {
                _ = try await ref.putDataAsync(data, metadata: metadata)
                let downloadURL = try await ref.downloadURL()
                return downloadURL.absoluteString
            } catch {
                lastError = error
                #if DEBUG
                print("CloudSync: upload attempt failed in bucket \(storage.reference().bucket) for \(storagePath): \(error)")
                #endif
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func uploadEncryptedPhoto(data: Data, storagePath: String, key: SymmetricKey) async throws -> String {
        let encryptedData = try crypto.encrypt(data: data, key: key)
        var lastError: Error?

        for storage in storages {
            let ref = storage.reference().child(storagePath)
            do {
                let result = try await ref.putDataAsync(encryptedData, metadata: nil)
                let bucket = result.bucket ?? storage.reference().bucket
                return SecureCloudPhotoReference.make(bucket: bucket, path: storagePath)
            } catch {
                lastError = error
                #if DEBUG
                print("CloudSync: encrypted upload attempt failed in bucket \(storage.reference().bucket) for \(storagePath): \(error)")
                #endif
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func uploadEncryptedVideo(data: Data, storagePath: String, key: SymmetricKey) async throws -> String {
        let encryptedData = try crypto.encrypt(data: data, key: key)
        var lastError: Error?

        for storage in storages {
            let ref = storage.reference().child(storagePath)
            do {
                let result = try await ref.putDataAsync(encryptedData, metadata: nil)
                let bucket = result.bucket ?? storage.reference().bucket
                return SecureCloudMediaReference.make(bucket: bucket, path: storagePath)
            } catch {
                lastError = error
                #if DEBUG
                print("CloudSync: encrypted video upload attempt failed in bucket \(storage.reference().bucket) for \(storagePath): \(error)")
                #endif
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func loadPhotoData(for photoReference: String) async throws -> Data? {
        if SecureCloudPhotoReference.isSecureReference(photoReference) {
            return try await SecureCloudPhotoLoader.shared.data(for: photoReference)
        }

        if photoReference.hasPrefix("http://") || photoReference.hasPrefix("https://"),
           let url = URL(string: photoReference) {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }
            return data
        }

        guard let localPhotoURL = LocalPhotoStorageService.resolvedURL(for: photoReference) else { return nil }
        return try Data(contentsOf: localPhotoURL)
    }

    private func loadVideoData(for videoReference: String) async throws -> Data? {
        if SecureCloudMediaReference.isSecureReference(videoReference) {
            return try await SecureCloudMediaLoader.shared.data(for: videoReference)
        }

        if videoReference.hasPrefix("http://") || videoReference.hasPrefix("https://"),
           let url = URL(string: videoReference) {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }
            return data
        }

        guard let localVideoURL = LocalVideoStorageService.resolvedURL(for: videoReference) else { return nil }
        return try Data(contentsOf: localVideoURL)
    }

    private func legacyPlaintextPayload(for user: UserAccount) async throws -> CloudBootstrapPayload {
        guard let db else {
            return CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
        }

        let userRef = db.collection("users").document(user.userID)
        let profileSnapshot = try await userRef.getDocument()
        let prefsSnapshot = try await userRef.collection("preferences").document("current").getDocument()

        let remoteProfile = try profileSnapshot.data().flatMap { try decode(UserProfile.self, from: $0) }
        let remotePreferences = try prefsSnapshot.data().flatMap { try decode(UserPreferences.self, from: $0) }
        let remoteRecords = try await loadPlaintextRecords(user: user, registrationDate: user.createdAt)

        return CloudBootstrapPayload(
            profile: remoteProfile,
            preferences: remotePreferences,
            records: remoteRecords
        )
    }

    private func hasLegacyPlaintextData(for user: UserAccount) async throws -> Bool {
        guard let db else { return false }
        if try await fetchEncryptionMetadata(for: user) != nil {
            return false
        }

        let userRef = db.collection("users").document(user.userID)
        let prefsSnapshot = try await userRef.collection("preferences").document("current").getDocument()
        if prefsSnapshot.exists {
            return true
        }

        let recordsSnapshot = try await userRef.collection("records").limit(to: 1).getDocuments()
        if recordsSnapshot.isEmpty == false {
            return true
        }
        return false
    }

    private func loadPlaintextRecords(user: UserAccount, registrationDate: Date) async throws -> [DailyRecord] {
        guard let db else { return [] }
        let userRef = db.collection("users").document(user.userID)
        let recordsSnapshot = try await userRef.collection("records").getDocuments()
        let keyedRecords = try recordsSnapshot.documents.map { document in
            (document.documentID, try decode(DailyRecord.self, from: document.data()))
        }
        let canonicalized = canonicalizedRecordMap(from: keyedRecords)
        let cutoffKey = registrationDate.storageKey()
        let filteredCanonicalized = canonicalized.filter { $0.key >= cutoffKey }
        let needsRepair = keyedRecords.count != filteredCanonicalized.count
            || keyedRecords.contains { $0.1.canonicalStorageKey(fallback: $0.0) != $0.0 }
            || canonicalized.count != filteredCanonicalized.count

        if needsRepair {
            try await rewritePlaintextRecords(filteredCanonicalized, originalDocumentIDs: keyedRecords.map(\.0), user: user)
        }

        return filteredCanonicalized.values.sorted { $0.date < $1.date }
    }

    private func loadEncryptedRecords(user: UserAccount, key: SymmetricKey, registrationDate: Date) async throws -> [DailyRecord] {
        guard let db else { return [] }
        let userRef = db.collection("users").document(user.userID)
        let recordsSnapshot = try await userRef.collection("secureRecords").getDocuments()
        let keyedRecords = try recordsSnapshot.documents.compactMap { document -> (String, DailyRecord)? in
            guard let record = try decryptDocument(DailyRecord.self, from: document.data(), key: key) else {
                return nil
            }
            return (document.documentID, record)
        }
        let canonicalized = canonicalizedRecordMap(from: keyedRecords)
        let cutoffKey = registrationDate.storageKey()
        let filteredCanonicalized = canonicalized.filter { $0.key >= cutoffKey }
        let needsRepair = keyedRecords.count != filteredCanonicalized.count
            || keyedRecords.contains { $0.1.canonicalStorageKey(fallback: $0.0) != $0.0 }
            || canonicalized.count != filteredCanonicalized.count

        if needsRepair {
            try await rewriteEncryptedRecords(filteredCanonicalized, originalDocumentIDs: keyedRecords.map(\.0), user: user, key: key)
        }

        return filteredCanonicalized.values.sorted { $0.date < $1.date }
    }

    private func mergeRecords(_ localRecords: [DailyRecord], with remoteRecords: [DailyRecord]) -> [DailyRecord] {
        var merged: [String: DailyRecord] = [:]

        for record in remoteRecords + localRecords {
            let normalized = record.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
            let key = normalized.canonicalStorageKey(fallback: normalized.date.storageKey())
            let anchored = normalized.anchoredToStorageKey(key)
            if let existing = merged[key] {
                merged[key] = existing.mergedPreservingSupplementalContent(
                    with: anchored,
                    preferences: UserPreferences()
                )
            } else {
                merged[key] = anchored
            }
        }

        return merged.values.sorted { $0.date < $1.date }
    }

    private func canonicalizedRecordMap(from keyedRecords: [(String, DailyRecord)]) -> [String: DailyRecord] {
        keyedRecords.reduce(into: [:]) { partialResult, entry in
            let canonicalKey = entry.1.canonicalStorageKey(fallback: entry.0)
            let anchored = entry.1.anchoredToStorageKey(canonicalKey)
            if let existing = partialResult[canonicalKey] {
                partialResult[canonicalKey] = existing.mergedPreservingSupplementalContent(
                    with: anchored,
                    preferences: UserPreferences()
                )
            } else {
                partialResult[canonicalKey] = anchored
            }
        }
    }

    private func rewritePlaintextRecords(
        _ records: [String: DailyRecord],
        originalDocumentIDs: [String],
        user: UserAccount
    ) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        for (key, record) in records {
            let prepared = try await preparedPlaintextRecord(record.anchoredToStorageKey(key), userID: user.userID)
            try await userRef.collection("records").document(key).setData(try encode(prepared))
        }

        let canonicalKeys = Set(records.keys)
        for documentID in Set(originalDocumentIDs).subtracting(canonicalKeys) {
            try? await userRef.collection("records").document(documentID).delete()
        }
    }

    private func rewriteEncryptedRecords(
        _ records: [String: DailyRecord],
        originalDocumentIDs: [String],
        user: UserAccount,
        key: SymmetricKey
    ) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        for (documentID, record) in records {
            let prepared = try await preparedEncryptedRecord(record.anchoredToStorageKey(documentID), userID: user.userID, key: key)
            let envelope = try crypto.encrypt(prepared, key: key)
            try await userRef.collection("secureRecords").document(documentID).setData(try encode(envelope))
        }

        let canonicalKeys = Set(records.keys)
        for documentID in Set(originalDocumentIDs).subtracting(canonicalKeys) {
            try? await userRef.collection("secureRecords").document(documentID).delete()
        }
    }

    private func fetchEncryptionMetadata(for user: UserAccount) async throws -> CloudEncryptionMetadata? {
        guard let db else { return nil }
        if let cached = session.metadata(for: user.userID) {
            return cached
        }
        let snapshot = try await db.collection("users").document(user.userID).collection("secureMeta").document("current").getDocument()
        let metadata = try snapshot.data().map { try decode(CloudEncryptionMetadata.self, from: $0) }
        session.storeMetadata(metadata, for: user.userID)
        return metadata
    }

    private func recoveryDocument(in db: Firestore, for user: UserAccount) -> DocumentReference {
        db.collection("users").document(user.userID).collection("secureMeta").document("recovery")
    }

    private func fetchRecoveryEnvelope(for user: UserAccount) async throws -> CloudRecoveryEnvelope? {
        guard let db else { return nil }
        let snapshot = try await recoveryDocument(in: db, for: user).getDocument()
        return try snapshot.data().map { try decode(CloudRecoveryEnvelope.self, from: $0) }
    }

    private func writeEncryptionMetadata(_ metadata: CloudEncryptionMetadata, for user: UserAccount) async throws {
        guard let db else { return }
        try await db.collection("users").document(user.userID).collection("secureMeta").document("current").setData(try encode(metadata))
    }

    private func decryptDocument<Value: Decodable>(_ type: Value.Type, from dictionary: [String: Any]?, key: SymmetricKey) throws -> Value? {
        guard let dictionary else { return nil }
        let envelope = try decode(CloudEncryptedEnvelope.self, from: dictionary)
        return try crypto.decrypt(type, from: envelope, key: key)
    }

    private func usableKey(for user: UserAccount, metadata: CloudEncryptionMetadata?) async throws -> SymmetricKey? {
        guard let metadata else { return nil }
        if let cachedKey = session.key(for: user.userID) {
            return cachedKey
        }

        let candidates: [SymmetricKey]
        switch metadata.keyProvider {
        case .synchronizableKeychain:
            // The local copy exists when unlocking with a recovery code could not write to iCloud Keychain.
            candidates = [
                keychain.loadSynchronizableKey(for: user.userID),
                keychain.loadLocalKey(for: user.userID)
            ].compactMap { $0 }
        case .passphrase:
            candidates = [
                keychain.loadLocalKey(for: user.userID),
                keychain.loadSynchronizableKey(for: user.userID)
            ].compactMap { $0 }
        }

        for candidate in candidates {
            if try await canDecryptCloudData(using: candidate, for: user) {
                session.storeKey(candidate, for: user.userID)
                return candidate
            }
        }

        return nil
    }

    /// Uploaded media gets a name derived from the local file so a later upload for another photo
    /// of the same meal can never overwrite it.
    private static func uploadNameComponent(for localKey: String?, fallbackIndex: Int) -> String {
        guard let localKey else { return String(fallbackIndex) }
        let stem = (localKey as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = String(stem.unicodeScalars.filter { allowed.contains($0) })
        return sanitized.isEmpty ? String(fallbackIndex) : sanitized
    }

    func uploadedMediaReferences(for user: UserAccount) async -> [String: String] {
        let mode: CloudMediaReferenceMap.Mode = session.metadata(for: user.userID).map { $0 == nil ? .plaintext : .encrypted } ?? .encrypted
        return await mediaReferences.references(userID: user.userID, mode: mode)
    }

    private func canDecryptCloudData(using key: SymmetricKey, for user: UserAccount) async throws -> Bool {
        guard let db else { return false }

        let userRef = db.collection("users").document(user.userID)

        let profileSnapshot = try await userRef.collection("secureProfile").document("current").getDocument()
        if profileSnapshot.exists {
            return (try? decryptDocument(UserProfile.self, from: profileSnapshot.data(), key: key)) != nil
        }

        let prefsSnapshot = try await userRef.collection("securePreferences").document("current").getDocument()
        if prefsSnapshot.exists {
            return (try? decryptDocument(UserPreferences.self, from: prefsSnapshot.data(), key: key)) != nil
        }

        let recordsSnapshot = try await userRef.collection("secureRecords").limit(to: 1).getDocuments()
        if let firstRecord = recordsSnapshot.documents.first {
            return (try? decryptDocument(DailyRecord.self, from: firstRecord.data(), key: key)) != nil
        }

        return true
    }

    private func deleteLegacyPlaintextCloudData(for user: UserAccount) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        try? await userRef.collection("preferences").document("current").delete()

        let recordsSnapshot = try await userRef.collection("records").getDocuments()
        for document in recordsSnapshot.documents {
            try? await userRef.collection("records").document(document.documentID).delete()
        }

        for storage in storages {
            let rootRef = storage.reference().child("users/\(user.userID)/meal-photos")
            if let itemPaths = try? await rootRef.listAllPathsAsync() {
                for path in itemPaths {
                    try? await storage.reference(withPath: path).deleteAsync()
                }
            }
        }
    }

    private func deleteSecurePhoto(at photoReference: String) async throws {
        guard let parsed = SecureCloudPhotoReference.parse(photoReference) else { return }
        var lastError: Error?

        for storage in storageDeletionCandidates(preferredBucket: parsed.bucket) {
            do {
                try await storage.reference(withPath: parsed.path).deleteAsync()
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private func deleteLegacyPhoto(at photoReference: String) async throws {
        guard photoReference.hasPrefix("http://") || photoReference.hasPrefix("https://") else { return }
        for storage in storages {
            do {
                let ref = storage.reference(forURL: photoReference)
                try await ref.deleteAsync()
                return
            } catch {
                continue
            }
        }
    }

    private func storageDeletionCandidates(preferredBucket: String) -> [Storage] {
        var candidates: [Storage] = []
        let bucketURL = preferredBucket.hasPrefix("gs://") ? preferredBucket : "gs://\(preferredBucket)"
        candidates.append(Storage.storage(url: bucketURL))
        candidates.append(contentsOf: storages)

        var seenBuckets = Set<String>()
        return candidates.filter { storage in
            seenBuckets.insert(storage.reference().bucket).inserted
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return dictionary
    }

    private func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try decoder.decode(type, from: data)
    }
}

/// Encryption state and profile writes remembered for the current app session, so routine pushes
/// don't re-download the encryption metadata and re-verify the key with several Firestore reads.
/// A validated key is trusted for a limited time; refreshing from the cloud re-validates it.
private final class CloudSessionCache: @unchecked Sendable {
    private static let keyLifetime: TimeInterval = 10 * 60
    private static let disabledMetadataLifetime: TimeInterval = 2 * 60
    private static let profileUpsertLifetime: TimeInterval = 30 * 60

    private struct Timestamped<Value> {
        var value: Value
        var storedAt: Date

        func isFresh(within lifetime: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) < lifetime
        }
    }

    private let lock = NSLock()
    private var metadataByUser: [String: Timestamped<CloudEncryptionMetadata?>] = [:]
    private var keysByUser: [String: Timestamped<SymmetricKey>] = [:]
    private var profileUpsertsByUser: [String: Timestamped<String>] = [:]

    /// `nil` when nothing is cached; `.some(nil)` when encryption is known to be disabled.
    func metadata(for userID: String) -> CloudEncryptionMetadata?? {
        lock.withLock {
            guard let entry = metadataByUser[userID] else { return nil }
            // Encryption can be switched on from another device, so "disabled" is rechecked regularly.
            if entry.value == nil, !entry.isFresh(within: Self.disabledMetadataLifetime) {
                return nil
            }
            return .some(entry.value)
        }
    }

    func storeMetadata(_ metadata: CloudEncryptionMetadata?, for userID: String) {
        lock.withLock {
            metadataByUser[userID] = Timestamped(value: metadata, storedAt: Date())
        }
    }

    func key(for userID: String) -> SymmetricKey? {
        lock.withLock {
            guard let entry = keysByUser[userID], entry.isFresh(within: Self.keyLifetime) else { return nil }
            return entry.value
        }
    }

    func storeKey(_ key: SymmetricKey, for userID: String) {
        lock.withLock {
            keysByUser[userID] = Timestamped(value: key, storedAt: Date())
        }
    }

    func shouldUpsertProfile(signature: String, userID: String) -> Bool {
        lock.withLock {
            guard let entry = profileUpsertsByUser[userID] else { return true }
            return entry.value != signature || !entry.isFresh(within: Self.profileUpsertLifetime)
        }
    }

    func recordProfileUpsert(signature: String, userID: String) {
        lock.withLock {
            profileUpsertsByUser[userID] = Timestamped(value: signature, storedAt: Date())
        }
    }

    func invalidate(userID: String) {
        lock.withLock {
            metadataByUser[userID] = nil
            keysByUser[userID] = nil
            profileUpsertsByUser[userID] = nil
        }
    }
}

/// Remembers which cloud reference each local photo or video was uploaded as. Without it every push
/// re-uploaded all media of the record, and every cloud refresh treated local-vs-cloud paths as a
/// difference and pushed the record (with all of its media) again.
actor CloudMediaReferenceMap {
    enum Mode: String, Codable {
        case encrypted
        case plaintext
    }

    private typealias Storage = [String: [String: [String: String]]]

    private let fileURL: URL
    private var storage: Storage?

    init(filename: String = "cloud-media-references.json") {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = supportURL.appendingPathComponent("DailyLogs", isDirectory: true)
        fileURL = directory.appendingPathComponent(filename)
    }

    /// Key identifying a local media reference (its file name), or `nil` for cloud references.
    nonisolated static func localKey(for reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("http://"),
              !trimmed.hasPrefix("https://"),
              !SecureCloudPhotoReference.isSecureReference(trimmed),
              !SecureCloudMediaReference.isSecureReference(trimmed) else {
            return nil
        }
        if let url = URL(string: trimmed), url.isFileURL {
            return url.lastPathComponent
        }
        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        return lastComponent.isEmpty ? nil : lastComponent
    }

    func reference(forLocalKey localKey: String, userID: String, mode: Mode) -> String? {
        loadedStorage()[userID]?[mode.rawValue]?[localKey]
    }

    func references(userID: String, mode: Mode) -> [String: String] {
        loadedStorage()[userID]?[mode.rawValue] ?? [:]
    }

    func store(_ reference: String, forLocalKey localKey: String, userID: String, mode: Mode) {
        var updated = loadedStorage()
        updated[userID, default: [:]][mode.rawValue, default: [:]][localKey] = reference
        storage = updated
        persist(updated)
    }

    /// Forgets `localKey` and returns the cloud references it was uploaded as.
    func removeReferences(forLocalKey localKey: String, userID: String) -> [String] {
        var updated = loadedStorage()
        var removed: [String] = []
        for mode in [Mode.encrypted, .plaintext] {
            if let reference = updated[userID]?[mode.rawValue]?.removeValue(forKey: localKey) {
                removed.append(reference)
            }
        }
        guard !removed.isEmpty else { return [] }
        storage = updated
        persist(updated)
        return removed
    }

    func forgetUploadedReference(_ reference: String, userID: String) {
        guard var userReferences = loadedStorage()[userID] else { return }
        var changed = false
        for (mode, references) in userReferences {
            let remaining = references.filter { $0.value != reference }
            if remaining.count != references.count {
                userReferences[mode] = remaining
                changed = true
            }
        }
        guard changed else { return }
        var updated = loadedStorage()
        updated[userID] = userReferences
        storage = updated
        persist(updated)
    }

    private func loadedStorage() -> Storage {
        if let storage {
            return storage
        }
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Storage.self, from: $0) } ?? [:]
        storage = loaded
        return loaded
    }

    private func persist(_ storage: Storage) {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension StorageReference {
    struct UploadResult: Sendable {
        var path: String?
        var bucket: String?
    }

    func putDataAsync(_ uploadData: Data, metadata: StorageMetadata?) async throws -> UploadResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UploadResult, Error>) in
            putData(uploadData, metadata: metadata) { resultMetadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: UploadResult(
                        path: resultMetadata?.path,
                        bucket: resultMetadata?.bucket
                    ))
                }
            }
        }
    }

    func downloadURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func getDataAsync(maxSize: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            getData(maxSize: maxSize) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func deleteAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func listAllPathsAsync() async throws -> [String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            listAll { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result.items.map(\.fullPath))
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
