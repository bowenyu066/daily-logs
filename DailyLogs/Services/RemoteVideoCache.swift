import CryptoKit
import Foundation

actor RemoteVideoCache {
    static let shared = RemoteVideoCache()

    private struct CacheEntry: Codable {
        var sourceURL: String
        var filename: String
        var cachedAt: Date
        var lastAccessedAt: Date
        var accessCount: Int
    }

    private let fileManager = FileManager.default
    private let directory: URL
    private let metadataURL: URL
    private let session: URLSession

    private var entriesByURL: [String: CacheEntry] = [:]
    private var hasLoadedMetadata = false
    private var protectedURLs = Set<String>()

    private let protectedWindowDays = 7
    private let staleEntryDays = 21
    private let maxUnprotectedEntries = 24
    private let accessCountCooldown: TimeInterval = 10 * 60

    init(session: URLSession = .shared) {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = cachesDirectory.appendingPathComponent("DailyLogs/RemoteVideos", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        self.directory = directory
        self.metadataURL = directory.appendingPathComponent("metadata.json")
        self.session = session
    }

    func fileURL(for source: String) async -> URL? {
        await loadMetadataIfNeeded()

        if let cachedURL = cachedFileURL(for: source, shouldIncrementAccessCount: true) {
            return cachedURL
        }

        return await downloadAndCacheVideo(from: source, incrementAccessCount: true)
    }

    func syncRetention(with recentRemoteVideoURLs: [String]) async {
        await loadMetadataIfNeeded()

        protectedURLs = Set(recentRemoteVideoURLs.filter(Self.isRemoteVideoURL))

        for urlString in protectedURLs {
            guard entry(for: urlString) == nil else { continue }
            _ = await downloadAndCacheVideo(from: urlString, incrementAccessCount: false)
        }

        await cleanup()
    }

    private func loadMetadataIfNeeded() async {
        guard !hasLoadedMetadata else { return }
        defer { hasLoadedMetadata = true }

        guard fileManager.fileExists(atPath: metadataURL.path) else { return }

        do {
            let data = try Data(contentsOf: metadataURL)
            entriesByURL = try JSONDecoder().decode([String: CacheEntry].self, from: data)
        } catch {
            entriesByURL = [:]
        }
    }

    private func cachedFileURL(for urlString: String, shouldIncrementAccessCount: Bool) -> URL? {
        guard let entry = entry(for: urlString) else { return nil }
        touchEntry(for: urlString, incrementAccessCount: shouldIncrementAccessCount)
        return directory.appendingPathComponent(entry.filename)
    }

    private func downloadAndCacheVideo(from source: String, incrementAccessCount: Bool) async -> URL? {
        do {
            let data: Data

            if SecureCloudMediaReference.isSecureReference(source) {
                data = try await SecureCloudMediaLoader.shared.data(for: source)
            } else if let remoteURL = URL(string: source) {
                let (downloadedData, response) = try await session.data(from: remoteURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    return nil
                }
                data = downloadedData
            } else {
                return nil
            }

            let filename = makeFilename(for: source)
            let fileURL = directory.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)

            let now = Date()
            entriesByURL[source] = CacheEntry(
                sourceURL: source,
                filename: filename,
                cachedAt: now,
                lastAccessedAt: now,
                accessCount: incrementAccessCount ? 1 : 0
            )
            persistMetadata()
            await cleanup()
            return fileURL
        } catch {
            return nil
        }
    }

    private func cleanup() async {
        let protectedThreshold = Date().startOfDay.adding(days: -(protectedWindowDays - 1))
        let protectedRecentURLs = protectedURLs.filter { urlString in
            guard let entry = entriesByURL[urlString] else { return false }
            return entry.cachedAt >= protectedThreshold || entry.lastAccessedAt >= protectedThreshold
        }

        var activeProtectedURLs = protectedURLs
        activeProtectedURLs.formUnion(protectedRecentURLs)

        let staleCutoff = Date().addingTimeInterval(-Double(staleEntryDays) * 86_400)

        let unprotectedEntries = entriesByURL.values
            .filter { !activeProtectedURLs.contains($0.sourceURL) }
            .sorted { lhs, rhs in
                if lhs.lastAccessedAt != rhs.lastAccessedAt {
                    return lhs.lastAccessedAt > rhs.lastAccessedAt
                }
                return lhs.accessCount > rhs.accessCount
            }

        let retainedUnprotectedURLs = Set(
            unprotectedEntries
                .filter { $0.lastAccessedAt >= staleCutoff }
                .prefix(maxUnprotectedEntries)
                .map(\.sourceURL)
        )

        let retainedURLs = activeProtectedURLs.union(retainedUnprotectedURLs)

        for entry in entriesByURL.values where !retainedURLs.contains(entry.sourceURL) {
            let fileURL = directory.appendingPathComponent(entry.filename)
            try? fileManager.removeItem(at: fileURL)
            entriesByURL.removeValue(forKey: entry.sourceURL)
        }

        removeOrphanedFiles()
        persistMetadata()
    }

    private func removeOrphanedFiles() {
        let validFilenames = Set(entriesByURL.values.map(\.filename))
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        for fileURL in files where fileURL.lastPathComponent != metadataURL.lastPathComponent {
            guard !validFilenames.contains(fileURL.lastPathComponent) else { continue }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func entry(for urlString: String) -> CacheEntry? {
        guard let entry = entriesByURL[urlString] else { return nil }
        let fileURL = directory.appendingPathComponent(entry.filename)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            entriesByURL.removeValue(forKey: urlString)
            persistMetadata()
            return nil
        }
        return entry
    }

    private func touchEntry(for urlString: String, incrementAccessCount: Bool) {
        guard var entry = entriesByURL[urlString] else { return }

        let now = Date()
        if incrementAccessCount, now.timeIntervalSince(entry.lastAccessedAt) >= accessCountCooldown {
            entry.accessCount += 1
        }
        entry.lastAccessedAt = now
        entriesByURL[urlString] = entry
        persistMetadata()
    }

    private func persistMetadata() {
        do {
            let data = try JSONEncoder().encode(entriesByURL)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            #if DEBUG
            print("RemoteVideoCache: failed to persist metadata: \(error)")
            #endif
        }
    }

    private func makeFilename(for source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).mp4"
    }

    private static func isRemoteVideoURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("http://")
            || urlString.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(urlString)
    }
}
