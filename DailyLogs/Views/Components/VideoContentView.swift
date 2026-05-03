import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct VideoContentView: View {
    let videoURL: String

    @State private var playableURL: URL?
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
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
        let url = URL(fileURLWithPath: videoURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

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
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    private func resolvedPlayableURL() async -> URL? {
        if videoURL.hasPrefix("http://")
            || videoURL.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(videoURL) {
            return await RemoteVideoCache.shared.fileURL(for: videoURL)
        }
        let url = URL(fileURLWithPath: videoURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
