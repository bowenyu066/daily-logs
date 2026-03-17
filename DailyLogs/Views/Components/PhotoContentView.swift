import SwiftUI
import UIKit

struct PhotoContentView: View {
    let photoURL: String
    var contentMode: ContentMode = .fill

    @State private var remoteUIImage: UIImage?
    @State private var isLoadingRemoteImage = false
    @State private var loadedRemotePhotoURL: String?

    var body: some View {
        Group {
            if remoteURL != nil {
                remoteContent
            } else if let uiImage = UIImage(contentsOfFile: photoURL) {
                configured(Image(uiImage: uiImage))
            } else {
                placeholder
            }
        }
        .task(id: photoURL) {
            guard let remoteURL else {
                remoteUIImage = nil
                loadedRemotePhotoURL = nil
                isLoadingRemoteImage = false
                return
            }
            await loadRemoteImage(from: remoteURL)
        }
    }

    private var remoteURL: URL? {
        guard photoURL.hasPrefix("http://") || photoURL.hasPrefix("https://") else { return nil }
        return URL(string: photoURL)
    }

    private func configured(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }

    @ViewBuilder
    private var remoteContent: some View {
        if let remoteUIImage {
            configured(Image(uiImage: remoteUIImage))
        } else if isLoadingRemoteImage {
            ZStack {
                placeholder
                ProgressView()
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.surface)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
    }

    @MainActor
    private func loadRemoteImage(from remoteURL: URL) async {
        guard loadedRemotePhotoURL != remoteURL.absoluteString else { return }
        remoteUIImage = nil
        loadedRemotePhotoURL = remoteURL.absoluteString
        isLoadingRemoteImage = true
        remoteUIImage = await RemotePhotoCache.shared.image(for: remoteURL)
        isLoadingRemoteImage = false
    }
}
