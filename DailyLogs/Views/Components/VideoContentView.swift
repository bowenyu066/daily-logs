import AVFoundation
import AVKit
import Photos
import SwiftUI
import UIKit

enum DailyVideoAudioSession {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("Failed to activate video playback audio session:", error)
            #endif
        }
    }
}

struct VideoContentView: View {
    let videoURL: String

    @State private var playableURL: URL?
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    placeholder
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                Circle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }

                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .clipped()
        .task(id: videoURL) {
            await loadThumbnail()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface)
            .overlay {
                Image(systemName: "video")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
    }

    @MainActor
    private func loadThumbnail() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = await resolvedPlayableURL() else {
            playableURL = nil
            thumbnail = nil
            return
        }

        playableURL = url
        thumbnail = makeThumbnail(for: url)
    }

    private func resolvedPlayableURL() async -> URL? {
        if videoURL.hasPrefix("http://")
            || videoURL.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(videoURL) {
            return await RemoteVideoCache.shared.fileURL(for: videoURL)
        }
        return LocalVideoStorageService.resolvedURL(for: videoURL)
    }

    private func makeThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        do {
            let image = try generator.copyCGImage(at: CMTime(seconds: 0.2, preferredTimescale: 600), actualTime: nil)
            return UIImage(cgImage: image)
        } catch {
            return nil
        }
    }
}

struct DailyVideoPlaybackOverlay: View {
    let videoURL: String
    let onClose: () -> Void

    @State private var player = AVPlayer()
    @State private var isLoading = true
    @State private var didLoadSource = false
    @State private var isSavingToLibrary = false
    @State private var didSaveToLibrary = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            mediaSaveButton(
                isSaving: isSavingToLibrary,
                didSave: didSaveToLibrary,
                action: saveVideoToLibrary
            )
            .padding(.top, 54)
            .padding(.leading, 20)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 54)
            .padding(.trailing, 20)
        }
        .alert(NSLocalizedString("保存失败", comment: ""), isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button(NSLocalizedString("知道了", comment: ""), role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .task(id: videoURL) {
            await loadVideo()
        }
        .onDisappear {
            player.pause()
        }
    }

    @MainActor
    private func loadVideo() async {
        guard !didLoadSource else { return }
        didLoadSource = true
        isLoading = true
        defer { isLoading = false }

        guard let url = await resolvedPlayableURL() else { return }
        DailyVideoAudioSession.activatePlayback()
        player.isMuted = false
        player.volume = 1
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    private func resolvedPlayableURL() async -> URL? {
        if videoURL.hasPrefix("http://")
            || videoURL.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(videoURL) {
            return await RemoteVideoCache.shared.fileURL(for: videoURL)
        }
        return LocalVideoStorageService.resolvedURL(for: videoURL)
    }

    private func saveVideoToLibrary() {
        guard !isSavingToLibrary else { return }
        didSaveToLibrary = false
        isSavingToLibrary = true

        Task {
            do {
                try await MediaLibrarySaver.saveVideo(from: videoURL)
                didSaveToLibrary = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSavingToLibrary = false
        }
    }
}

@MainActor
@ViewBuilder
func mediaSaveButton(isSaving: Bool, didSave: Bool, action: @escaping () -> Void) -> some View {
    Button {
        action()
    } label: {
        HStack(spacing: 7) {
            if isSaving {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.82)
            } else {
                Image(systemName: didSave ? "checkmark" : "square.and.arrow.down")
                    .font(.system(size: 16, weight: .bold))
            }

            Text(didSave ? NSLocalizedString("已保存", comment: "") : NSLocalizedString("保存", comment: ""))
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(isSaving)
    .accessibilityLabel(Text(NSLocalizedString("保存到相册", comment: "")))
}

enum MediaLibrarySaver {
    static func savePhoto(from source: String) async throws {
        guard let image = await image(for: source) else {
            throw MediaLibrarySaveError.sourceUnavailable
        }
        try await requestAddOnlyAuthorizationIfNeeded()
        try await saveImage(image)
    }

    static func saveVideo(from source: String) async throws {
        guard let fileURL = await videoFileURL(for: source) else {
            throw MediaLibrarySaveError.sourceUnavailable
        }
        try await requestAddOnlyAuthorizationIfNeeded()
        try await saveVideoFile(at: fileURL)
    }

    private static func image(for source: String) async -> UIImage? {
        if isRemotePhotoSource(source) {
            return await RemotePhotoCache.shared.image(for: source)
        }
        guard let fileURL = LocalPhotoStorageService.resolvedURL(for: source) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    private static func videoFileURL(for source: String) async -> URL? {
        if isRemoteVideoSource(source) {
            return await RemoteVideoCache.shared.fileURL(for: source)
        }
        return LocalVideoStorageService.resolvedURL(for: source)
    }

    private static func requestAddOnlyAuthorizationIfNeeded() async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch currentStatus {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw MediaLibrarySaveError.notAuthorized
            }
        case .denied, .restricted:
            throw MediaLibrarySaveError.notAuthorized
        @unknown default:
            throw MediaLibrarySaveError.notAuthorized
        }
    }

    private static func saveImage(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MediaLibrarySaveError.saveFailed)
                }
            }
        }
    }

    private static func saveVideoFile(at fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MediaLibrarySaveError.saveFailed)
                }
            }
        }
    }

    private static func isRemotePhotoSource(_ source: String) -> Bool {
        source.hasPrefix("http://")
            || source.hasPrefix("https://")
            || SecureCloudPhotoReference.isSecureReference(source)
    }

    private static func isRemoteVideoSource(_ source: String) -> Bool {
        source.hasPrefix("http://")
            || source.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(source)
    }
}

enum MediaLibrarySaveError: LocalizedError {
    case notAuthorized
    case sourceUnavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            NSLocalizedString("无法保存，请在系统设置里允许保存到照片。", comment: "")
        case .sourceUnavailable:
            NSLocalizedString("无法读取这个媒体文件。", comment: "")
        case .saveFailed:
            NSLocalizedString("保存到相册失败，请稍后再试。", comment: "")
        }
    }
}
