import FirebaseFirestore
import FirebaseStorage
import Foundation

struct CloudBootstrapPayload {
    var profile: UserProfile?
    var preferences: UserPreferences?
    var records: [DailyRecord]
}

@MainActor
protocol CloudSyncService {
    var isAvailable: Bool { get }
    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload
    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws
    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws
    func pushProfile(_ user: UserAccount) async throws
}

@MainActor
struct NoopCloudSyncService: CloudSyncService {
    var isAvailable: Bool { false }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {}

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {}

    func pushProfile(_ user: UserAccount) async throws {}
}

@MainActor
final class FirebaseCloudSyncService: CloudSyncService {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var db: Firestore? {
        FirebaseBootstrap.configureIfPossible()
        return FirebaseBootstrap.isConfigured ? Firestore.firestore() : nil
    }

    private var storage: Storage? {
        FirebaseBootstrap.configureIfPossible()
        return FirebaseBootstrap.isConfigured ? Storage.storage() : nil
    }

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var isAvailable: Bool {
        db != nil
    }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        guard let db else {
            return CloudBootstrapPayload(profile: nil, preferences: nil, records: [])
        }

        try await upsertProfile(user)

        let userRef = db.collection("users").document(user.userID)
        let prefsSnapshot = try await userRef.collection("preferences").document("current").getDocument()
        let recordsSnapshot = try await userRef.collection("records").getDocuments()

        let remotePreferences = try prefsSnapshot.data().flatMap { try decode(UserPreferences.self, from: $0) }
        let remoteRecords = try recordsSnapshot.documents.compactMap { document in
            try decode(DailyRecord.self, from: document.data())
        }
        .sorted { $0.date < $1.date }

        if prefsSnapshot.exists == false {
            try await pushPreferences(localPreferences, user: user)
        }

        if remoteRecords.isEmpty && !localRecords.isEmpty {
            for record in localRecords {
                try await pushRecord(record, user: user)
            }
        }

        return CloudBootstrapPayload(
            profile: UserProfile(userID: user.userID, createdAt: user.createdAt),
            preferences: remotePreferences,
            records: remoteRecords
        )
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        try await userRef.collection("preferences").document("current").setData(try encode(preferences))
        try await upsertProfile(user)
    }

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {
        guard let db else { return }
        let userRef = db.collection("users").document(user.userID)
        let cloudReadyRecord = try await preparedRecord(record, userID: user.userID)
        try await userRef.collection("records").document(record.date.storageKey()).setData(try encode(cloudReadyRecord))
        try await upsertProfile(user)
    }

    func pushProfile(_ user: UserAccount) async throws {
        try await upsertProfile(user)
    }

    private func upsertProfile(_ user: UserAccount) async throws {
        guard let db else { return }
        let payload: [String: Any] = [
            "userID": user.userID,
            "displayName": user.displayName,
            "email": user.email as Any,
            "authMode": user.authMode.rawValue,
            "createdAt": user.createdAt.displayISO8601,
            "updatedAt": Date().displayISO8601
        ]
        try await db.collection("users").document(user.userID).setData(payload, merge: true)
    }

    private func preparedRecord(_ record: DailyRecord, userID: String) async throws -> DailyRecord {
        guard let storage else { return record }
        var updated = record
        for index in updated.meals.indices {
            guard let photoURL = updated.meals[index].photoURL else { continue }
            guard !photoURL.hasPrefix("http://"), !photoURL.hasPrefix("https://") else { continue }
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
                let ref = storage.reference(withPath: path)
                let resultMeta = try await ref.putDataAsync(data, metadata: meta)
                // Build download URL from the returned metadata to avoid
                // a separate downloadURL() call that may fail on fresh objects.
                let storagePath = resultMeta.path ?? path
                let bucket = resultMeta.bucket ?? storage.reference().bucket
                let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
                let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded.replacingOccurrences(of: "/", with: "%2F"))?alt=media"
                updated.meals[index].photoURL = downloadURL
            } catch {
                // Upload failed — strip local path so it doesn't leak to Firestore.
                // The record itself still pushes to Firestore (without the photo).
                #if DEBUG
                print("CloudSync: photo upload failed for meal \(updated.meals[index].id): \(error)")
                #endif
                updated.meals[index].photoURL = nil
            }
        }
        return updated
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return dictionary
    }

    private func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try decoder.decode(type, from: data)
    }
}

@MainActor
private extension StorageReference {
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
}
