import SwiftUI
import UIKit

struct PhotoContentView: View {
    let photoURL: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if let remoteURL = remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    configured(image)
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        placeholder
                        ProgressView()
                    }
                @unknown default:
                    placeholder
                }
            }
        } else if let uiImage = UIImage(contentsOfFile: photoURL) {
            configured(Image(uiImage: uiImage))
        } else {
            placeholder
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

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.surface)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
    }
}
