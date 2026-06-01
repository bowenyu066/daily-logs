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
            if isRemoteSource {
                remoteContent
            } else if let fileURL = LocalPhotoStorageService.resolvedURL(for: photoURL),
                      let uiImage = UIImage(contentsOfFile: fileURL.path) {
                configured(Image(uiImage: uiImage))
            } else {
                placeholder
            }
        }
        .task(id: photoURL) {
            guard isRemoteSource else {
                remoteUIImage = nil
                loadedRemotePhotoURL = nil
                isLoadingRemoteImage = false
                return
            }
            await loadRemoteImage(from: photoURL)
        }
    }

    private var isRemoteSource: Bool {
        photoURL.hasPrefix("http://")
            || photoURL.hasPrefix("https://")
            || SecureCloudPhotoReference.isSecureReference(photoURL)
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
    private func loadRemoteImage(from source: String) async {
        guard loadedRemotePhotoURL != source else { return }
        remoteUIImage = nil
        loadedRemotePhotoURL = source
        isLoadingRemoteImage = true
        remoteUIImage = await RemotePhotoCache.shared.image(for: source)
        isLoadingRemoteImage = false
    }
}

struct ZoomablePhotoContentView: View {
    let photoURL: String
    var contentMode: ContentMode = .fit

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minimumScale: CGFloat = 1
    private let maximumScale: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            PhotoContentView(photoURL: photoURL, contentMode: contentMode)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    magnificationGesture(in: proxy.size)
                        .simultaneously(with: dragGesture(in: proxy.size))
                )
                .onTapGesture(count: 2) {
                    toggleZoom(in: proxy.size)
                }
        }
        .clipped()
        .onChange(of: photoURL) { _, _ in
            resetZoom()
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextScale = clampedScale(lastScale * value)
                scale = nextScale
                offset = clampedOffset(offset, scale: nextScale, in: size)
            }
            .onEnded { value in
                scale = clampedScale(lastScale * value)
                if scale <= minimumScale {
                    resetZoom()
                } else {
                    offset = clampedOffset(offset, scale: scale, in: size)
                    lastScale = scale
                    lastOffset = offset
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minimumScale else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, scale: scale, in: size)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if scale > minimumScale {
                resetZoom()
            } else {
                scale = 2
                lastScale = scale
                offset = clampedOffset(.zero, scale: scale, in: size)
                lastOffset = offset
            }
        }
    }

    private func resetZoom() {
        scale = minimumScale
        lastScale = minimumScale
        offset = .zero
        lastOffset = .zero
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }

    private func clampedOffset(_ value: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        guard scale > minimumScale else { return .zero }
        let horizontalLimit = max(0, size.width * (scale - 1) / 2)
        let verticalLimit = max(0, size.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(value.width, -horizontalLimit), horizontalLimit),
            height: min(max(value.height, -verticalLimit), verticalLimit)
        )
    }
}
