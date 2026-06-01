import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct IdentifiableVideoSource: Identifiable {
    let id = UUID()
    let url: URL
}

struct DailyVideoTrimmerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceURL: URL
    let onSave: (URL, TimeInterval) -> Void

    @State private var player = AVPlayer()
    @State private var duration: TimeInterval = 0
    @State private var startTime: TimeInterval = 0
    @State private var clipDuration: TimeInterval = 0
    @State private var timelineThumbnails: [UIImage] = []
    @State private var isExporting = false
    @State private var errorMessage: String?

    private let targetDuration: TimeInterval = 10
    private let minimumClipDuration: TimeInterval = 0.5

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 520)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text(clipRangeText)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.black.opacity(0.42))
                                .clipShape(Capsule())
                                .padding(12)
                        }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(NSLocalizedString("最长 10 秒片段", comment: ""))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            Text(clipRangeText)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                                .monospacedDigit()
                        }

                        DailyVideoTimelineSelector(
                            startTime: $startTime,
                            clipDuration: $clipDuration,
                            duration: duration,
                            targetDuration: targetDuration,
                            minimumClipDuration: minimumClipDuration,
                            thumbnails: timelineThumbnails,
                            isEnabled: canSaveSelection && !isExporting,
                            durationText: durationText
                        )
                    }
                    .padding(18)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if isExporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(NSLocalizedString("正在保存片段…", comment: ""))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .padding(18)
                .padding(.bottom, 40)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("选择片段", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                    .disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存片段", comment: "")) {
                        Task { await exportSelection() }
                    }
                    .disabled(!canSaveSelection || isExporting)
                }
            }
            .task {
                await loadVideo()
            }
            .onChange(of: startTime) { _, _ in
                seekToStart(shouldPlay: player.rate > 0)
            }
            .onChange(of: clipDuration) { _, _ in
                normalizeSelection()
            }
            .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
                guard player.rate > 0 else { return }
                let endTime = startTime + effectiveClipDuration
                guard player.currentTime().seconds >= endTime else { return }
                seekToStart(shouldPlay: true)
            }
            .onDisappear {
                player.pause()
            }
            .alert(NSLocalizedString("提示", comment: ""), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(NSLocalizedString("知道了", comment: "")) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private var maxStartTime: TimeInterval {
        max(0, duration - effectiveClipDuration)
    }

    private var effectiveClipDuration: TimeInterval {
        min(max(clipDuration, 0), max(duration - startTime, 0), targetDuration)
    }

    private var canSaveSelection: Bool {
        duration > 0 && effectiveClipDuration >= 0.1
    }

    private var clipRangeText: String {
        "\(durationText(startTime)) - \(durationText(startTime + effectiveClipDuration))"
    }

    @MainActor
    private func loadVideo() async {
        let asset = AVURLAsset(url: sourceURL)
        do {
            let loadedDuration = try await asset.load(.duration).seconds
            duration = loadedDuration.isFinite ? max(0, loadedDuration) : 0
            clipDuration = min(targetDuration, duration)
            startTime = min(startTime, maxStartTime)
            timelineThumbnails = DailyVideoTimelineThumbnailGenerator.makeThumbnails(
                for: sourceURL,
                duration: duration
            )
            DailyVideoAudioSession.activatePlayback()
            player.isMuted = false
            player.volume = 1
            player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
            seekToStart(shouldPlay: true)
        } catch {
            errorMessage = NSLocalizedString("无法读取视频：", comment: "") + error.localizedDescription
        }
    }

    @MainActor
    private func exportSelection() async {
        guard canSaveSelection else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let exportedURL = try await DailyVideoExporter.export(
                sourceURL: sourceURL,
                startTime: startTime,
                duration: effectiveClipDuration
            )
            onSave(exportedURL, effectiveClipDuration)
            dismiss()
        } catch {
            errorMessage = NSLocalizedString("保存片段失败：", comment: "") + error.localizedDescription
        }
    }

    private func seekToStart(shouldPlay: Bool) {
        let target = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if shouldPlay {
            player.play()
        }
    }

    private func normalizeSelection() {
        let maxDuration = min(targetDuration, duration)
        clipDuration = min(max(clipDuration, 0), maxDuration)
        startTime = min(max(startTime, 0), max(0, duration - effectiveClipDuration))
    }

    private func durationText(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "00:00" }
        let totalSeconds = max(0, Int(value.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct DailyVideoTimelineSelector: View {
    @Binding var startTime: TimeInterval
    @Binding var clipDuration: TimeInterval

    let duration: TimeInterval
    let targetDuration: TimeInterval
    let minimumClipDuration: TimeInterval
    let thumbnails: [UIImage]
    let isEnabled: Bool
    let durationText: (TimeInterval) -> String

    @State private var dragSnapshot: DragSnapshot?

    private struct DragSnapshot {
        let startTime: TimeInterval
        let clipDuration: TimeInterval
    }

    private var maxClipDuration: TimeInterval {
        min(targetDuration, max(duration, 0))
    }

    private var resolvedMinimumClipDuration: TimeInterval {
        min(minimumClipDuration, maxClipDuration)
    }

    private var selectedEndTime: TimeInterval {
        min(duration, startTime + clipDuration)
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let selectionX = offset(for: startTime, in: width)
                let naturalSelectionWidth = offset(for: selectedEndTime, in: width) - selectionX
                let selectionWidth = visualSelectionWidth(naturalSelectionWidth, in: width)
                let selectionOffset = min(selectionX, max(width - selectionWidth, 0))

                ZStack(alignment: .leading) {
                    DailyVideoTimelineThumbnailStrip(thumbnails: thumbnails)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.46))
                            .frame(width: max(selectionOffset, 0))

                        Color.clear
                            .frame(width: selectionWidth)

                        Rectangle()
                            .fill(Color.black.opacity(0.46))
                    }
                }
                .overlay(alignment: .leading) {
                    selectionOverlay(width: selectionWidth, height: height, trackWidth: width)
                        .offset(x: selectionOffset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.55)
            }
            .frame(height: 78)

            HStack {
                Text(durationText(startTime))
                Spacer()
                Text(durationText(selectedEndTime))
                Spacer()
                Text(durationText(duration))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .monospacedDigit()
        }
    }

    private func selectionOverlay(width: CGFloat, height: CGFloat, trackWidth: CGFloat) -> some View {
        let handleWidth = min(30, max(16, width * 0.28))

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(AppTheme.accent, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay {
                HStack(spacing: 0) {
                    handleTouchArea(width: handleWidth)
                        .gesture(leftHandleDragGesture(trackWidth: trackWidth))

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(selectionDragGesture(trackWidth: trackWidth))

                    handleTouchArea(width: handleWidth)
                        .gesture(rightHandleDragGesture(trackWidth: trackWidth))
                }
            }
            .frame(width: width, height: height)
    }

    private var selectionHandle: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 4, height: 34)
            .shadow(color: Color.black.opacity(0.22), radius: 3, x: 0, y: 1)
    }

    private func handleTouchArea(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: width)
            .overlay {
                selectionHandle
            }
    }

    private func visualSelectionWidth(_ naturalWidth: CGFloat, in trackWidth: CGFloat) -> CGFloat {
        min(trackWidth, max(44, naturalWidth))
    }

    private func offset(for time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return width * CGFloat(min(max(time / duration, 0), 1))
    }

    private func seconds(for translationWidth: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        guard trackWidth > 0, duration > 0 else { return 0 }
        return Double(translationWidth / trackWidth) * duration
    }

    private func selectionDragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, duration > 0, clipDuration > 0 else { return }
                let snapshot = currentSnapshot()
                let nextStartTime = snapshot.startTime + seconds(
                    for: value.translation.width,
                    trackWidth: trackWidth
                )
                setSelection(
                    start: nextStartTime,
                    duration: snapshot.clipDuration
                )
            }
            .onEnded { _ in
                dragSnapshot = nil
            }
    }

    private func leftHandleDragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, duration > 0 else { return }
                let snapshot = currentSnapshot()
                let previousEndTime = snapshot.startTime + snapshot.clipDuration
                let proposedStartTime = snapshot.startTime + seconds(
                    for: value.translation.width,
                    trackWidth: trackWidth
                )

                if previousEndTime - proposedStartTime > maxClipDuration {
                    setSelection(start: proposedStartTime, duration: maxClipDuration)
                } else {
                    let clampedStartTime = min(
                        max(proposedStartTime, 0),
                        max(previousEndTime - resolvedMinimumClipDuration, 0)
                    )
                    setSelection(
                        start: clampedStartTime,
                        duration: previousEndTime - clampedStartTime
                    )
                }
            }
            .onEnded { _ in
                dragSnapshot = nil
            }
    }

    private func rightHandleDragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, duration > 0 else { return }
                let snapshot = currentSnapshot()
                let proposedEndTime = snapshot.startTime + snapshot.clipDuration + seconds(
                    for: value.translation.width,
                    trackWidth: trackWidth
                )

                if proposedEndTime - snapshot.startTime > maxClipDuration {
                    setSelection(
                        start: proposedEndTime - maxClipDuration,
                        duration: maxClipDuration
                    )
                } else {
                    let clampedEndTime = max(
                        min(proposedEndTime, duration),
                        snapshot.startTime + resolvedMinimumClipDuration
                    )
                    setSelection(
                        start: snapshot.startTime,
                        duration: clampedEndTime - snapshot.startTime
                    )
                }
            }
            .onEnded { _ in
                dragSnapshot = nil
            }
    }

    private func currentSnapshot() -> DragSnapshot {
        if let dragSnapshot {
            return dragSnapshot
        }

        let snapshot = DragSnapshot(startTime: startTime, clipDuration: clipDuration)
        dragSnapshot = snapshot
        return snapshot
    }

    private func setSelection(start proposedStart: TimeInterval, duration proposedDuration: TimeInterval) {
        guard maxClipDuration > 0 else {
            startTime = 0
            clipDuration = 0
            return
        }

        let nextDuration = min(max(proposedDuration, resolvedMinimumClipDuration), maxClipDuration)
        let nextStart = min(max(proposedStart, 0), max(0, duration - nextDuration))
        startTime = nextStart
        clipDuration = min(nextDuration, max(0, duration - nextStart))
    }
}

private struct DailyVideoTimelineThumbnailStrip: View {
    let thumbnails: [UIImage]

    var body: some View {
        GeometryReader { proxy in
            if thumbnails.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.accentSoft)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            } else {
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { index in
                        Image(uiImage: thumbnails[index])
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: proxy.size.width / CGFloat(max(thumbnails.count, 1)),
                                height: proxy.size.height
                            )
                            .clipped()
                    }
                }
            }
        }
    }
}

private enum DailyVideoTimelineThumbnailGenerator {
    static func makeThumbnails(
        for sourceURL: URL,
        duration: TimeInterval,
        count: Int = 12
    ) -> [UIImage] {
        guard duration > 0, count > 0 else { return [] }

        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 260, height: 260)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let step = duration / Double(count)
        return (0..<count).compactMap { index in
            let seconds = min(duration, max(0, (Double(index) + 0.5) * step))
            do {
                let image = try generator.copyCGImage(
                    at: CMTime(seconds: seconds, preferredTimescale: 600),
                    actualTime: nil
                )
                return UIImage(cgImage: image)
            } catch {
                return nil
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private enum DailyVideoExporter {
    private static let preferredPresets = [
        AVAssetExportPreset1920x1080,
        AVAssetExportPreset1280x720,
        AVAssetExportPresetHighestQuality,
        AVAssetExportPresetMediumQuality
    ]

    static func export(sourceURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportConfiguration = await makeExportConfiguration(for: asset) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let exportSession = exportConfiguration.session
        let outputFileType = exportConfiguration.outputFileType
        let outputExtension = outputFileType == .mp4 ? "mp4" : "mov"

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-video-\(UUID().uuidString).\(outputExtension)")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, startTime), preferredTimescale: 600),
            duration: CMTime(seconds: max(0.1, duration), preferredTimescale: 600)
        )

        let exportBox = ExportSessionBox(exportSession)
        return try await withCheckedThrowingContinuation { continuation in
            exportBox.session.exportAsynchronously {
                switch exportBox.session.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    continuation.resume(throwing: exportBox.session.error ?? CocoaError(.fileWriteUnknown))
                default:
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private static func makeExportConfiguration(for asset: AVURLAsset) async -> (session: AVAssetExportSession, outputFileType: AVFileType)? {
        for presetName in preferredPresets {
            for outputFileType in [AVFileType.mp4, .mov] {
                let isCompatible = await AVAssetExportSession.compatibility(
                    ofExportPreset: presetName,
                    with: asset,
                    outputFileType: outputFileType
                )
                guard isCompatible,
                      let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
                    continue
                }
                return (exportSession, outputFileType)
            }
        }
        return nil
    }
}

struct DailyVideoPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    var maximumDuration: TimeInterval = 60
    let onVideoPicked: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = maximumDuration
        if sourceType == .camera {
            picker.cameraCaptureMode = .video
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoPicked: onVideoPicked)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onVideoPicked: (URL?) -> Void

        init(onVideoPicked: @escaping (URL?) -> Void) {
            self.onVideoPicked = onVideoPicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onVideoPicked(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let pickedURL = info[.mediaURL] as? URL
            let stableURL = pickedURL.flatMap { copyToTemporaryFile($0) }
            onVideoPicked(stableURL)
            picker.dismiss(animated: true)
        }

        private func copyToTemporaryFile(_ url: URL) -> URL? {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("daily-video-source-\(UUID().uuidString).mov")
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                return destination
            } catch {
                return url
            }
        }
    }
}
