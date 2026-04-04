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
    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot
    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws
}

struct NoopCloudSyncService: CloudSyncService {
    var isAvailable: Bool { false }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {}

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {}

    func pushProfile(_ user: UserAccount) async throws {}

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
            hasLegacyPlaintextData: try await hasLegacyPlaintextData(for: user)
        )
    }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        guard let db else {
            return CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
        }

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
            let profileSnapshot = try await userRef.collection("secureProfile").document("current").getDocument()
            let prefsSnapshot = try await userRef.collection("securePreferences").document("current").getDocument()

            let remoteProfile = try decryptDocument(UserProfile.self, from: profileSnapshot.data(), key: key)
            let remotePreferences = try decryptDocument(UserPreferences.self, from: prefsSnapshot.data(), key: key)
            let remoteRecords = try await loadEncryptedRecords(user: user, key: key, registrationDate: user.createdAt)

            if prefsSnapshot.exists == false {
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
        let profileSnapshot = try await userRef.getDocument()
        let prefsSnapshot = try await userRef.collection("preferences").document("current").getDocument()

        let remoteProfile = try profileSnapshot.data().flatMap { try decode(UserProfile.self, from: $0) }
        let remotePreferences = try prefsSnapshot.data().flatMap { try decode(UserPreferences.self, from: $0) }
        let remoteRecords = try await loadPlaintextRecords(user: user, registrationDate: user.createdAt)

        if prefsSnapshot.exists == false {
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
        try await upsertProfile(user, encrypted: true)
        await progress(CloudMigrationProgress(fractionCompleted: 0.95, message: NSLocalizedString("正在清理旧数据…", comment: "")))
        try await deleteLegacyPlaintextCloudData(for: user)
        await progress(CloudMigrationProgress(fractionCompleted: 1.0, message: NSLocalizedString("迁移完成。", comment: "")))
    }

    private func upsertProfile(_ user: UserAccount, encrypted: Bool) async throws {
        guard let db else { return }
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
    }

    private func preparedPlaintextRecord(_ record: DailyRecord, userID: String) async throws -> DailyRecord {
        guard !storages.isEmpty else { return record }
        var updated = record
        for index in updated.meals.indices {
            guard let photoURL = updated.meals[index].photoURL else { continue }
            guard !photoURL.hasPrefix("http://"), !photoURL.hasPrefix("https://") else { continue }
            guard !SecureCloudPhotoReference.isSecureReference(photoURL) else { continue }
            guard FileManager.default.fileExists(atPath: photoURL) else {
                updated.meals[index].photoURL = nil
                continue
            }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: photoURL))
                let filename = "\(updated.meals[index].id.uuidString).jpg"
                let path = "users/\(userID)/meal-photos/\(filename)"
                let meta = StorageMetadata()
                meta.contentType = "image/jpeg"
                updated.meals[index].photoURL = try await uploadPhoto(
                    data: data,
                    storagePath: path,
                    metadata: meta
                )
            } catch {
                // Upload failed — strip local path so it doesn't leak to Firestore.
                // The record itself still pushes to Firestore (without the photo).
                #if DEBUG
                print(
                    "CloudSync: photo upload failed for meal \(updated.meals[index].id) " +
                    "at path users/\(userID)/meal-photos/\(updated.meals[index].id.uuidString).jpg: \(error)"
                )
                #endif
                updated.meals[index].photoURL = nil
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
        for index in updated.meals.indices {
            guard let photoReference = updated.meals[index].photoURL else { continue }
            guard !SecureCloudPhotoReference.isSecureReference(photoReference) else { continue }
            guard let data = try await loadPhotoData(for: photoReference) else {
                updated.meals[index].photoURL = nil
                continue
            }

            do {
                let filename = "\(updated.meals[index].id.uuidString).bin"
                let path = "users/\(userID)/secure-meal-photos/\(filename)"
                updated.meals[index].photoURL = try await uploadEncryptedPhoto(
                    data: data,
                    storagePath: path,
                    key: key
                )
                if photoReference.hasPrefix("http://") || photoReference.hasPrefix("https://") {
                    try? await deleteLegacyPhoto(at: photoReference)
                }
            } catch {
                #if DEBUG
                print("CloudSync: encrypted photo upload failed for meal \(updated.meals[index].id): \(error)")
                #endif
                updated.meals[index].photoURL = nil
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

        guard FileManager.default.fileExists(atPath: photoReference) else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: photoReference))
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
                merged[key] = preferredRecord(between: existing, and: anchored)
            } else {
                merged[key] = anchored
            }
        }

        return merged.values.sorted { $0.date < $1.date }
    }

    private func preferredRecord(between lhs: DailyRecord, and rhs: DailyRecord) -> DailyRecord {
        if lhs.effectiveModifiedAt != rhs.effectiveModifiedAt {
            return lhs.effectiveModifiedAt > rhs.effectiveModifiedAt ? lhs : rhs
        }

        return score(for: rhs) >= score(for: lhs) ? rhs : lhs
    }

    private func score(for record: DailyRecord) -> Int {
        var total = 0
        if record.sleepRecord.bedtimePreviousNight != nil { total += 2 }
        if record.sleepRecord.wakeTimeCurrentDay != nil { total += 2 }
        if record.sleepRecord.note?.isEmpty == false { total += 1 }
        total += record.sleepRecord.stageIntervals.count
        total += record.meals.filter { $0.status == .logged || $0.time != nil || $0.photoURL != nil || $0.note?.isEmpty == false }.count * 2
        total += record.showers.count * 2
        total += record.bowelMovements.count * 2
        total += record.sexualActivities.count * 2
        if record.aiInsightNarrative?.hasAIScoring == true { total += 2 }
        if record.sunTimes != nil { total += 2 }
        return total
    }

    private func canonicalizedRecordMap(from keyedRecords: [(String, DailyRecord)]) -> [String: DailyRecord] {
        keyedRecords.reduce(into: [:]) { partialResult, entry in
            let canonicalKey = entry.1.canonicalStorageKey(fallback: entry.0)
            let anchored = entry.1.anchoredToStorageKey(canonicalKey)
            if let existing = partialResult[canonicalKey] {
                partialResult[canonicalKey] = preferredRecord(between: existing, and: anchored)
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
        let snapshot = try await db.collection("users").document(user.userID).collection("secureMeta").document("current").getDocument()
        guard let data = snapshot.data() else { return nil }
        return try decode(CloudEncryptionMetadata.self, from: data)
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

        let candidates: [SymmetricKey]
        switch metadata.keyProvider {
        case .synchronizableKeychain:
            candidates = [keychain.loadSynchronizableKey(for: user.userID)].compactMap { $0 }
        case .passphrase:
            candidates = [
                keychain.loadLocalKey(for: user.userID),
                keychain.loadSynchronizableKey(for: user.userID)
            ].compactMap { $0 }
        }

        for candidate in candidates {
            if try await canDecryptCloudData(using: candidate, for: user) {
                return candidate
            }
        }

        return nil
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
